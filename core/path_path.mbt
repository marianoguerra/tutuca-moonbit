// Path operations over Values, plus the leaf-update core of
// the transactor (updateRootValue).

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
/// `Path::new().field("rows").index("rows", 2)` — the absolute twin of the
/// relative `PathChanges` builder, which delegates to these so the two spell
/// a step the same way. Each returns a fresh Path, so a base is reusable.
pub fn Path::field(self : Path, name : String) -> Path {
  self.concat([FieldStep(name)])
}

///|
/// A positional item of a sequence FIELD. There is no bare-index step: a Path
/// addresses field-then-key, so a nested `.a[0][1]` is not expressible and the
/// value-level `item`/`index` are what read one.
pub fn Path::index(self : Path, name : String, i : Int) -> Path {
  self.concat([SeqStep(field=name, key=KInt(i))])
}

///|
/// A keyed item of a sequence field.
pub fn Path::key(self : Path, name : String, k : String) -> Path {
  self.concat([SeqStep(field=name, key=KStr(k))])
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
pub fn Path::lookup(self : Path, root : Value) -> Value? {
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
pub fn Path::set_value(self : Path, root : Value, v : Value) -> Value {
  let n = self.steps.length()
  let intermediates : Array[Value] = []
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
pub fn Path::resolve_chain(self : Path, root : Value) -> Array[Value] {
  let out : Array[Value] = [root]
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
pub fn Path::pin_keys(self : Path, root : Value) -> Path {
  let mut out : Array[Step]? = None
  let mut cur : Value? = Some(root)
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
/// A key as its addressing text: `2` or `title`.
pub fn PathKey::to_label(self : PathKey) -> String {
  match self {
    KInt(i) => i.to_string()
    KStr(s) => s
  }
}

///|
/// A key as a Value — what `@key` binds to inside a loop, and what a
/// seq-access read compares against.
pub fn PathKey::to_value(self : PathKey) -> Value {
  match self {
    KInt(i) => Num(i.to_double())
    KStr(s) => Str(s)
  }
}

///|
/// Addressing steps as readable text: `value.rows[1].title`.
///
/// Over `StepKey` rather than `Step`, because that is the projection a
/// transaction is RECORDED as (`ObserveRecord.path_keys`) — so a log line and
/// a `Path` print the same way without the log having to keep the Path.
pub fn step_keys_label(keys : Array[StepKey]) -> String {
  keys
  .map(k => {
    match k.key {
      Some(pk) => "\{k.field}[\{pk.to_label()}]"
      None => k.field
    }
  })
  .join(".")
}

///|
/// The addressing steps as readable text.
///
/// Over `to_keys`, so the frame-only steps (which address nothing) are absent
/// and a seq-access step shows as its field.
pub fn Path::to_label(self : Path) -> String {
  step_keys_label(self.to_keys())
}

///|
pub impl Show for Path with fn output(self, logger) {
  logger.write_string(self.to_label())
}

///|
/// `route` defaults to `default_route()` — the one place `dyn lex` is written.
pub fn IntentOpts::new(
  route? : Array[Leg] = default_route(),
  on_ok_name? : String,
  on_error_name? : String,
  on_unhandled_name? : String,
  live_path? : Bool = false,
) -> IntentOpts {
  { route, on_ok_name, on_error_name, on_unhandled_name, live_path }
}

///|
/// The handlers a value carries: component instances answer through the `Obj`
/// trait, pure data has none.
pub fn Value::handler(
  self : Value,
  bucket : HandlerBucket,
  name : String,
) -> Handler? {
  match self {
    Obj(o) => o.obj_handler(bucket, name)
    _ => None
  }
}

///|
pub fn Path::update(
  self : Path,
  root : Value,
  bucket : HandlerBucket,
  name : String,
  args : Array[Value],
) -> Value {
  guard self.lookup(root) is Some(leaf) else {
    // The two guards here are the whole reason the refusal channel exists: from
    // outside, they are the same `root` a handler that ran and changed nothing
    // hands back. They report OUTSIDE the dispatch scope opened below, because
    // each one already is where the chain ends — there is no handler under them
    // to have decided anything more specific.
    if refusing() {
      refuse({
        code: PathUnresolved,
        asked: name,
        rule: "",
        sentence: "",
        state: root,
        path: self,
      })
    }
    return root
  }
  // One lookup. A typed `update` is one pattern match whose
  // `_ => None` already IS the catch-all, and the generated `<C>Msg` hands the
  // unmatched name to an `Unknown(name, args)` arm.
  guard leaf.handler(bucket, name) is Some(Handler(f)) else {
    if refusing() {
      refuse({
        code: NoHandler,
        asked: name,
        rule: "",
        sentence: "",
        state: leaf,
        path: self,
      })
    }
    return root
  }
  // From here down a handler exists and whatever happens is its answer, so this
  // is the dispatch a record belongs to: a contract inside the body knows the
  // rule it broke and not where it ran, and the scope is what supplies the rest.
  // A handler that dispatches again nests into this same scope — one dispatch,
  // one record, however many layers it walked.
  let opened = begin_dispatch(self)
  let out = match f(args, NullCtx::{  }) {
    Some(new_leaf) =>
      // Parity with the original `newLeaf !== curLeaf` check: a handler that
      // hands back the value
      // it was given skips the rebuild, whether it says so by answering None
      // or by handing the same object back. Neither is a refusal: an arm that
      // answers `None` DECLINED, and the mutator behind it is the design.
      if physical_equal(new_leaf, leaf) {
        root
      } else {
        self.set_value(root, new_leaf)
      }
    None => root
  }
  end_dispatch(opened)
  out
}

///|
/// `route` defaults to `default_route()`, the same one an intent takes.
pub fn LookupOpts::new(route? : Array[Leg] = default_route()) -> LookupOpts {
  { route, }
}
