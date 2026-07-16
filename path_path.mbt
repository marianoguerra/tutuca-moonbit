// Path operations (src/path.js Path) over &PathNode trait objects, plus the
// leaf-update core of the transactor (updateRootValue).

///|
pub fn Path::new(steps? : Array[Step]) -> Path {
  match steps {
    Some(s) => { steps: s }
    None => { steps: [] }
  }
}

///|
pub fn Path::concat(self : Path, steps : Array[Step]) -> Path {
  let out = self.steps.copy()
  for s in steps {
    out.push(s)
  }
  { steps: out }
}

///|
pub fn Path::pop_step(self : Path) -> Path {
  let n = self.steps.length()
  if n == 0 {
    self
  } else {
    { steps: self.steps[0:n - 1].to_owned() }
  }
}

///|
pub fn Path::lookup(self : Path, root : &PathNode) -> &PathNode? {
  let mut cur = root
  for step in self.steps {
    match step_get(cur, step) {
      Some(next) => cur = next
      None => return None
    }
  }
  Some(cur)
}

///|
pub fn Path::set_value(
  self : Path,
  root : &PathNode,
  v : &PathNode,
) -> &PathNode {
  let n = self.steps.length()
  let intermediates : Array[&PathNode] = []
  let mut cur = root
  for step in self.steps {
    intermediates.push(cur)
    match step_get(cur, step) {
      Some(next) => cur = next
      None => return root
    }
  }
  let mut new_val = v
  for i = n - 1; i >= 0; i = i - 1 {
    match step_put(intermediates[i], self.steps[i], new_val) {
      Some(nv) => new_val = nv
      None => return root
    }
  }
  new_val
}

///|
pub fn Path::resolve_chain(self : Path, root : &PathNode) -> Array[&PathNode] {
  let out : Array[&PathNode] = [root]
  let mut cur = root
  for step in self.steps {
    match step_get(cur, step) {
      Some(next) => {
        cur = next
        out.push(next)
      }
      None => break
    }
  }
  out
}

///|
pub fn Path::pin_keys(self : Path, root : &PathNode) -> Path {
  let mut out : Array[Step]? = None
  let mut cur : &PathNode? = Some(root)
  for i in 0..<self.steps.length() {
    let step = self.steps[i]
    guard cur is Some(node) else { break }
    let pinned = step_pin(step, node)
    if pinned != step {
      let steps = match out {
        Some(s) => s
        None => {
          let s = self.steps.copy()
          out = Some(s)
          s
        }
      }
      steps[i] = pinned
    }
    cur = step_get(node, step)
  }
  match out {
    Some(steps) => { steps, }
    None => self
  }
}

///|
pub fn Path::compact(self : Path) -> Path {
  let out : Array[Step] = []
  for step in self.steps {
    match step_to_abstract(step) {
      Some(s) => out.push(s)
      None => ()
    }
  }
  { steps: out }
}

///|
pub fn Path::to_keys(self : Path) -> Array[StepKey] {
  let out : Array[StepKey] = []
  for step in self.steps {
    match step_to_key(step) {
      Some(k) => out.push(k)
      None => ()
    }
  }
  out
}

///|
pub fn RequestOpts::new(
  on_ok_name? : String,
  on_error_name? : String,
  on_res_name? : String,
  live_path? : Bool = false,
) -> RequestOpts {
  { on_ok_name, on_error_name, on_res_name, live_path }
}

///|
pub fn Path::update(
  self : Path,
  root : &PathNode,
  bucket : HandlerBucket,
  name : String,
  args : Array[Value],
) -> &PathNode {
  guard self.lookup(root) is Some(leaf) else { return root }
  let resolved = match leaf.handler(bucket, name) {
    Some(h) => Some(h)
    None => leaf.handler(bucket, "$unknown")
  }
  guard resolved is Some(Handler(f)) else { return root }
  match f(args, NullCtx::{  }) {
    Some(new_leaf) =>
      // Best-effort JS `newLeaf !== curLeaf` parity: a handler that somehow
      // hands back the very same box skips the rebuild. The reliable no-change
      // signal is returning None (boxing into &PathNode breaks identity).
      if physical_equal(new_leaf, leaf) {
        root
      } else {
        self.set_value(root, new_leaf)
      }
    None => root
  }
}
