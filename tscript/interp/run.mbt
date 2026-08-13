// Running a statement body.
//
// All or nothing. A body that cannot finish produces no successor state AND no
// effects — half a transition, where the state did not move but a `send` went
// out, is the one outcome worse than nothing happening, because it is the one
// nobody can reason about afterwards.
//
// State is threaded as a fresh map rather than mutated in place, so abandoning
// a body costs nothing: the caller still holds the state it passed in, and
// physical identity — which the transactor reads as "nothing changed" — is
// preserved by the caller returning that same map.

///|
pub fn dispatch(
  d : @tscript.Decl,
  args : Array[@tutuca.Value],
  env : Env,
) -> Outcome {
  let params : Map[String, @tutuca.Value] = Map([])
  for i, p in d.params {
    params[p.name] = args.get(i).unwrap_or(Null)
  }
  match d.body {
    Stmts(ss) => run(ss, { ..env, params, })
    // A `compute` or a `pred` reached through a dispatch changes nothing; it
    // is a value, and asking it a question is not a transition.
    Value(_) => Outcome::nothing()
  }
}

///|
pub fn call(d : @tscript.Decl, env : Env) -> @tutuca.Value? {
  guard d.body is Value(e) else { return None }
  eval(e, env)
}

///|
pub fn run(body : Array[@tscript.Stmt], env : Env) -> Outcome {
  // A copy, so the caller's map is untouched whatever happens below.
  let state : Map[String, @tutuca.Value] = Map([])
  for k, v in env.state {
    state[k] = v
  }
  let binds : Map[String, @tutuca.Value] = Map([])
  for k, v in env.binds {
    binds[k] = v
  }
  let effects : Array[Effect] = []
  let cur : Env = { ..env, state, binds }
  if exec(body, cur, effects, 0) {
    { state: Some(state), effects, binds }
  } else {
    Outcome::nothing()
  }
}

///|
/// Execute statements against `env`'s (already copied) maps. False means the
/// body did not finish.
fn exec(
  body : Array[@tscript.Stmt],
  env : Env,
  effects : Array[Effect],
  depth : Int,
) -> Bool {
  if depth > MAX_DEPTH {
    return false
  }
  for s in body {
    if !exec_one(s, env, effects, depth) {
      return false
    }
  }
  true
}

///|
fn exec_one(
  s : @tscript.Stmt,
  env : Env,
  effects : Array[Effect],
  depth : Int,
) -> Bool {
  match s {
    SAssign(place~, op~, value~, ..) => {
      guard eval(value, env) is Some(rhs) else { return false }
      let next = match op {
        ASet => rhs
        AAdd | ASub => {
          guard read_place(place, env, depth) is Some(old) else { return false }
          guard old is Num(a) && rhs is Num(b) else { return false }
          Num(if op is AAdd { a + b } else { a - b })
        }
      }
      write_place(place, next, env)
    }
    SMethod(place~, call~, args~, ..) => {
      let vals : Array[@tutuca.Value] = []
      for a in args {
        guard eval(a, env) is Some(v) else { return false }
        vals.push(v)
      }
      guard read_place(place, env, depth) is Some(old) else { return false }
      guard collection_op(call, old, vals) is Some(next) else { return false }
      write_place(place, next, env)
    }
    SEffect(name~, args~, ..) => effect(name, args, env, effects, depth)
    SIf(cond~, then_~, else_~, ..) => {
      guard eval(cond, env) is Some(c) else { return false }
      if c.is_truthy() {
        exec(then_, env, effects, depth + 1)
      } else {
        exec(else_, env, effects, depth + 1)
      }
    }
  }
}

// ---------------------------------------------------------------------------
// Writing

///|
/// Write `v` at a place, rebuilding the spine above it.
///
/// Copy-on-write all the way down, exactly as the generated mutators are: an
/// untouched subtree is the SAME object afterwards, which is what makes the
/// render cache's identity check answer correctly.
fn write_place(p : @tscript.Place, v : @tutuca.Value, env : Env) -> Bool {
  let root_name = match p.root {
    PState(n) => n
    PBind(n) => n
  }
  let target : Map[String, @tutuca.Value] = match p.root {
    PState(_) => env.state
    PBind(_) => env.binds
  }
  if p.steps.is_empty() {
    // The one place the declared schema is consulted: an integer field
    // truncates, matching what the generated codec's decode does with the
    // same value rather than storing a fraction the type says cannot be there.
    target[root_name] = coerce_root(root_name, v, env, p.root)
    return true
  }
  let root = target.get(root_name).unwrap_or(Null)
  guard rebuild(root, p.steps, 0, v, env) is Some(next) else { return false }
  target[root_name] = next
  true
}

///|
/// Truncate into an integer field. Only for a STATE root: a binding has no
/// declared type, and a nested field's type is the record's to state.
fn coerce_root(
  name : String,
  v : @tutuca.Value,
  env : Env,
  root : @tscript.PlaceRoot,
) -> @tutuca.Value {
  guard root is PState(_) else { return v }
  guard env.schema is Some(schema) else { return v }
  guard schema.field(name) is Some(fi) else { return v }
  match (fi.kind(), v) {
    (FInt, Num(n)) => Num(n.to_int().to_double())
    _ => v
  }
}

///|
/// Rebuild the spine from `steps[i]` down, placing `v` at the end.
fn rebuild(
  node : @tutuca.Value,
  steps : Array[@tscript.PathStep],
  i : Int,
  v : @tutuca.Value,
  env : Env,
) -> @tutuca.Value? {
  if i >= steps.length() {
    return Some(v)
  }
  match steps[i] {
    PField(name) => {
      let child = node.field_opt(name).unwrap_or(Null)
      guard rebuild(child, steps, i + 1, v, env) is Some(next) else {
        return None
      }
      node.with_field_opt(name, next)
    }
    PIndex(key) => {
      guard eval(key, env) is Some(kv) else { return None }
      guard kv.as_key() is Some(k) else { return None }
      // A key that is not there refuses the whole write. Growing a collection
      // by assigning past its end is what `push` and `insertAt` are for, and a
      // write that silently created a slot would make a typo into data.
      guard node.item_opt(k) is Some(child) else { return None }
      guard rebuild(child, steps, i + 1, v, env) is Some(next) else {
        return None
      }
      node.with_item_opt(k, next)
    }
  }
}

// ---------------------------------------------------------------------------
// Collection methods

///|
/// A mutating collection method, as a pure function of the old value.
///
/// These mirror the runtime-generic mutators in `component/component.mbt` one
/// for one — `.items.push v` IS `pushInItems` — so a card and a compiled
/// component do the same thing to the same state. Where one refuses, so does
/// the other.
fn collection_op(
  call : String,
  old : @tutuca.Value,
  args : Array[@tutuca.Value],
) -> @tutuca.Value? {
  match (call, old) {
    ("push", List(xs)) => {
      let out = xs.copy()
      out.push(args[0])
      Some(List(out))
    }
    // Insert BEFORE index i, and past the end appends — the same bounds rule
    // `insertInXAt` follows.
    ("insertAt", List(xs)) => {
      guard args[0] is Num(idx) else { return None }
      let out = xs.copy()
      let at = idx.to_int()
      if at >= 0 && at <= out.length() {
        out.insert(at, args[1])
      } else {
        out.push(args[1])
      }
      Some(List(out))
    }
    ("setAt", _) => {
      guard args[0].as_key() is Some(k) else { return None }
      old.with_item_opt(k, args[1])
    }
    ("deleteAt", List(xs)) => {
      guard args[0] is Num(idx) else { return None }
      let at = idx.to_int()
      guard at >= 0 && at < xs.length() else { return None }
      let out = xs.copy()
      out.remove(at) |> ignore
      Some(List(out))
    }
    ("deleteAt", Map(m)) => {
      let k = args[0].to_display_string()
      guard m.contains(k) else { return None }
      let out : Map[String, @tutuca.Value] = Map([])
      for key, v in m {
        if key != k {
          out[key] = v
        }
      }
      Some(Map(out))
    }
    // The set operations, over the Map-backed representation every set has:
    // member -> Bool(true), keyed by the member's display string.
    ("add", Map(m)) => {
      let out : Map[String, @tutuca.Value] = Map([])
      for key, v in m {
        out[key] = v
      }
      out[args[0].to_display_string()] = Bool(true)
      Some(Map(out))
    }
    ("remove", Map(m)) => {
      let k = args[0].to_display_string()
      let out : Map[String, @tutuca.Value] = Map([])
      for key, v in m {
        if key != k {
          out[key] = v
        }
      }
      Some(Map(out))
    }
    ("toggle", Map(m)) => {
      let k = args[0].to_display_string()
      let out : Map[String, @tutuca.Value] = Map([])
      let mut had = false
      for key, v in m {
        if key == k {
          had = true
        } else {
          out[key] = v
        }
      }
      if !had {
        out[k] = Bool(true)
      }
      Some(Map(out))
    }
    _ => None
  }
}

// ---------------------------------------------------------------------------
// Effects

///|
fn effect(
  name : String,
  args : Array[@tscript.Expr],
  env : Env,
  effects : Array[Effect],
  depth : Int,
) -> Bool {
  if name == "stop" {
    effects.push(EStop)
    return true
  }
  // `sendAt` is the one effect whose first argument is a PLACE. It is reified
  // rather than read: `&.rows[k]` denotes the position, and a position
  // survives the root being rebuilt — which is what makes an async response
  // land on the row that asked for it.
  if name == "sendAt" {
    guard args.get(0) is Some(ERef(place~, ..)) else { return false }
    guard place_steps(place, env) is Some(steps) else { return false }
    guard args.get(1) is Some(ELit(lit=LStr(msg), ..)) else { return false }
    let rest : Array[@tutuca.Value] = []
    for i in 2..<args.length() {
      guard eval(args[i], env) is Some(v) else { return false }
      rest.push(v)
    }
    effects.push(ESendAt(steps~, name=msg, args=rest))
    return true
  }
  guard args.get(0) is Some(ELit(lit=LStr(msg), ..)) else { return false }
  let rest : Array[@tutuca.Value] = []
  for i in 1..<args.length() {
    guard eval(args[i], env) is Some(v) else { return false }
    rest.push(v)
  }
  match name {
    "send" => effects.push(ESend(name=msg, args=rest))
    "bubble" => effects.push(EBubble(name=msg, args=rest))
    "request" => effects.push(ERequest(name=msg, args=rest))
    _ => return false
  }
  let _ = depth
  true
}

///|
/// Turn a `&` place into the path steps it reifies.
///
/// The three key forms differ in WHEN the key resolves, and that difference is
/// the async-race material rather than cosmetics:
///
///   `&.rows[3]`        a literal key, resolved now
///   `&.rows[k]`        `k` a parameter — resolved now, from the value in hand
///   `&.sheets[.selId]` resolved EVERY TIME it runs, from live state
///
/// Only the third follows a moving selection and only the third can race, so
/// only the third becomes a `SeqAccessStep`. The others are frozen here.
fn place_steps(p : @tscript.Place, env : Env) -> Array[@tutuca.Step]? {
  guard p.root is PState(root) else { return None }
  let out : Array[@tutuca.Step] = []
  let mut pending : String? = Some(root)
  for st in p.steps {
    match st {
      PField(name) => {
        match pending {
          Some(f) => out.push(FieldStep(f))
          None => ()
        }
        pending = Some(name)
      }
      PIndex(key) => {
        guard pending is Some(field) else { return None }
        // A key that names a live state FIELD stays a field reference, so it
        // is re-read on every dispatch and pinned at request time. Anything
        // else is frozen to the value it has now.
        match key {
          ERead(place=kp, ..) if kp.root is PState(kf) && kp.steps.is_empty() =>
            out.push(SeqAccessStep(seq_field=field, key_field=kf))
          _ => {
            guard eval(key, env) is Some(kv) else { return None }
            guard kv.as_key() is Some(k) else { return None }
            out.push(SeqStep(field~, key=k))
          }
        }
        pending = None
      }
    }
  }
  match pending {
    Some(f) => out.push(FieldStep(f))
    None => ()
  }
  Some(out)
}
