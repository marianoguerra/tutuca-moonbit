// Statements.
//
// A statement writes: to the successor state, or to the host through `control`.
// Both are `Unit`, which is why these return a list of instructions where
// `expr.mbt` returns one.
//
// The state local holds a `&jv_record_value` and every write REBINDS it. That
// is the shape copy-on-write wants and it is what the cell runtime could not
// have: there, a successor was a fresh 32 bytes and a write was a `memory.copy`
// into it, so the local never changed and two handlers could not have shared a
// byte. Here `jv_record_try_set` answers a record that shares everything it did
// not change, including — when the value is equal — the SAME record.

///|
fn ECtx::stmts(self : ECtx, ss : Array[@tscript.Stmt]) -> Array[@abi.I] raise Bail {
  let out : Array[@abi.I] = []
  for s in ss {
    for i in self.stmt(s) {
      out.push(i)
    }
  }
  out
}

///|
/// The declared type of one of this card's fields, if it has one.
fn Gen::field_ty(self : Gen, name : String) -> @statedef.StateTy? {
  match self.index.get(name) {
    Some(i) => Some(self.fields[i].ty)
    None => None
  }
}

///|
/// A value on its way into a field, truncated if the field is an integer.
///
/// The schema cannot do this. tutuca has ONE number type, so an `Int` field and
/// a `Double` field are both `jv_type_f64` and nothing in the record layer can
/// tell them apart — but the interpreter truncates on the way into an Int
/// (`coerce_root`, `interp/run.mbt`), so the compiled backend has to emit the
/// truncation at the sites where it knows.
fn Gen::coerce(self : Gen, name : String, v : @abi.I) -> @abi.I {
  match self.field_ty(name) {
    Some(TInt(..)) => call("tc_trunc", [v])
    _ => v
  }
}

///|
fn ECtx::stmt(self : ECtx, s : @tscript.Stmt) -> Array[@abi.I] raise Bail {
  match s {
    SAssign(place~, op~, value~, span~) =>
      match place.root {
        PState(name) => {
          guard self.g.index.get(name) is Some(_) else {
            self.bail(
              "this card's state declares no field `" + name + "`",
              span,
            )
            return []
          }
          self.assign(name, place.steps, op, value, span)
        }
        // `@cur.text = 'z'` — the target a `new` made, written the same way a
        // field is: down through the steps into locals, back up through the
        // putters. The only difference is where the root comes from and where
        // it goes back to.
        PBind(b) if b == @tscript.target_bind => {
          self.uses_target = true
          self.assign_target(place.steps, op, value)
        }
        _ => {
          self.bail(
            "only a `.field` of this card's own state and the `@cur` a `new` makes are assignable in a compiled handler",
            span,
          )
          []
        }
      }
    SIf(cond~, then_~, else_~, ..) =>
      [if_(self.truthy(cond), self.stmts(then_), self.stmts(else_))]
    SEffect(name~, args~, span~) => self.effect(name, args, span)
    SMethod(place~, call~, args~, span~) => self.mutate(place, call, args, span)
    // `new Label` — the zero of a declared type, into `@cur`.
    //
    // Resolved and built HERE rather than at run time: a zero is a property of
    // a declared type, and the type is written in the source. A type nothing
    // can name is a refusal where the interpreter abandons the transition, so
    // the card is told when it compiles instead of when it runs.
    SNew(ty~, span~) => {
      guard @info.zero_of_ref(self.g.def, ty) is Some(zero) else {
        self.bail(
          "`new " + ty.to_source() + "` names a type this card does not declare",
          span,
        )
        return []
      }
      self.uses_target = true
      [set(target_local, const_value(self.g, zero))]
    }
  }
}

///|
/// `.field = e`, `.field += e`, and the same through a path.
///
/// The path case walks DOWN into locals and rebuilds UP through
/// `tc_step_put` — `write_place` and `rebuild` in `interp/run.mbt`, spelled as
/// a chain of temporaries so that a key expression is evaluated once rather
/// than once per level.
fn ECtx::assign(
  self : ECtx,
  name : String,
  steps : Array[@tscript.PathStep],
  op : @tscript.AssignOp,
  value : @tscript.Expr,
  _span : @tscript.Span,
) -> Array[@abi.I] raise Bail {
  let out : Array[@abi.I] = []
  let field = text_const_str(self.g.pool, name)

  // Down: r[0] is the field, r[i+1] is one step below r[i].
  let rs : Array[String] = [self.g.fresh("r")]
  out.push(let_(rs[0], call("tc_get", [get(self.state), field])))
  let keys : Array[String] = []
  for st in steps {
    let k = self.g.fresh("k")
    out.push(let_(k, self.step_key(st)))
    keys.push(k)
    let r = self.g.fresh("r")
    out.push(
      let_(r, call(self.step_fn(st), [get(rs[rs.length() - 1]), get(k)])),
    )
    rs.push(r)
  }

  // The new innermost value.
  let cur = get(rs[rs.length() - 1])
  let v = self.expr(value)
  let mut acc = match op {
    ASet => v
    AAdd => call("tc_add", [cur, v])
    ASub => call("tc_sub", [cur, v])
  }
  // Only a write straight AT the field lands in the field's declared type; a
  // write deeper in lands wherever the collection puts it, and the schema has
  // nothing to say about that.
  if steps.is_empty() {
    acc = self.g.coerce(name, acc)
  }

  // Up: replace each level in its parent.
  let mut i = steps.length()
  while i > 0 {
    acc = call(self.put_fn(steps[i - 1]), [
      get(rs[i - 1]),
      get(keys[i - 1]),
      acc,
    ])
    i = i - 1
  }
  out.push(set(self.state, call("tc_set", [get(self.state), field, acc])))
  out
}

///|
/// The local `@cur` lives in.
///
/// A single function-level local rather than a `let` per `new`, so that a
/// second `new` starts over — the corpus asks for exactly that — without the
/// scoping of a shadowing binding to reason about.
///
/// It also means a `new` inside an `if` survives the branch, which is a quirk
/// and a shared one: `exec` hands both arms the same `Env` and `SNew` writes
/// `env.binds`, so the interpreter leaks it too. Unobservable either way — the
/// checker merges the target across an `if` and keeps only what both arms
/// agree on, so reading `@cur` after a one-armed `new` is `NO_TARGET`. See
/// README.md.
let target_local : String = "cur"

///|
/// `@cur = e`, and the same through a path.
fn ECtx::assign_target(
  self : ECtx,
  steps : Array[@tscript.PathStep],
  op : @tscript.AssignOp,
  value : @tscript.Expr,
) -> Array[@abi.I] raise Bail {
  let out : Array[@abi.I] = []
  let rs : Array[String] = [self.g.fresh("r")]
  out.push(let_(rs[0], call("tc_target", [get(target_local)])))
  let keys : Array[String] = []
  for st in steps {
    let k = self.g.fresh("k")
    out.push(let_(k, self.step_key(st)))
    keys.push(k)
    let r = self.g.fresh("r")
    out.push(
      let_(r, call(self.step_fn(st), [get(rs[rs.length() - 1]), get(k)])),
    )
    rs.push(r)
  }
  let cur = get(rs[rs.length() - 1])
  let v = self.expr(value)
  let mut acc = match op {
    ASet => v
    AAdd => call("tc_add", [cur, v])
    ASub => call("tc_sub", [cur, v])
  }
  let mut i = steps.length()
  while i > 0 {
    acc = call(self.put_fn(steps[i - 1]), [
      get(rs[i - 1]),
      get(keys[i - 1]),
      acc,
    ])
    i = i - 1
  }
  out.push(set(target_local, acc))
  out
}

///|
/// One step of a path, as the value it addresses with.
///
/// A field name and a subscript are the same thing here — a value the
/// collection is asked to look up — because `tc_step` dispatches on what it is
/// walking rather than on how the step was written.
fn ECtx::step_key(self : ECtx, st : @tscript.PathStep) -> @abi.I raise Bail {
  match st {
    PField(f) => text_const_str(self.g.pool, f)
    PIndex(e) => self.expr(e)
  }
}

///|
/// Which reader a step uses. See the note in `ECtx::walk`.
fn ECtx::step_fn(self : ECtx, st : @tscript.PathStep) -> String {
  ignore(self)
  match st {
    PField(_) => "tc_step_field"
    PIndex(_) => "tc_step_index"
  }
}

///|
/// Which writer, on the way back up. The same split, and for the same reason:
/// a `[k]` that is not there refuses the whole write, where a `.field` that is
/// not there is simply created.
fn ECtx::put_fn(self : ECtx, st : @tscript.PathStep) -> String {
  ignore(self)
  match st {
    PField(_) => "tc_step_put_field"
    PIndex(_) => "tc_step_put_index"
  }
}

///|
/// `.items.push v` — a mutating collection method.
///
/// The names and arities are `collection_method`'s (`tscript/script_parse.mbt`)
/// and the semantics are `collection_op`'s (`interp/run.mbt`). Four of the
/// eleven — `clear`, `delete`, `set`, `removeAt` — are parsed by tscript and
/// implemented by NEITHER backend: the interpreter answers `None` for them, so
/// compiling them into something would be inventing a meaning the language does
/// not have.
fn ECtx::mutate(
  self : ECtx,
  place : @tscript.Place,
  name : String,
  args : Array[@tscript.Expr],
  span : @tscript.Span,
) -> Array[@abi.I] raise Bail {
  let which = match name {
    "push" => 1
    "insertAt" => 2
    "setAt" => 3
    "deleteAt" => 4
    "add" => 5
    "remove" => 6
    "toggle" => 7
    _ => 0
  }
  guard which != 0 else {
    self.bail(
      "`." +
      name +
      "` is parsed by the card language but the interpreter does not implement it either, so there is no behaviour to compile",
      span,
    )
    return []
  }
  // `@cur.push 'p'` — a `new Array[String]` being filled before it is
  // assigned. Routed through the target's own read-modify-write rather than
  // the state's.
  if place.root is PBind(bind) && bind == @tscript.target_bind {
    self.uses_target = true
    self.g.uses_values = true
    return self.mutate_target(place.steps, which, args)
  }
  guard place.root is PState(field) else {
    self.bail(
      "only a collection in this card's own state, or the `@cur` a `new` made, may be mutated in a compiled handler",
      span,
    )
    return []
  }
  guard self.g.index.get(field) is Some(_) else {
    self.bail("this card's state declares no field `" + field + "`", span)
    return []
  }
  // Mutating a collection means one can exist, and one that exists can be
  // asked for through `get-field`.
  self.g.uses_values = true
  let a = if args.length() > 0 {
    self.expr(args[0])
  } else {
    call("tc_null", [])
  }
  let b = if args.length() > 1 {
    self.expr(args[1])
  } else {
    call("tc_null", [])
  }
  // A method is a read-modify-write of the place it names, which is exactly
  // what `assign` already spells — so it is routed through the same walk rather
  // than given a second one that could disagree about paths.
  let out : Array[@abi.I] = []
  let f = text_const_str(self.g.pool, field)
  let rs : Array[String] = [self.g.fresh("r")]
  out.push(let_(rs[0], call("tc_get", [get(self.state), f])))
  let keys : Array[String] = []
  for st in place.steps {
    let k = self.g.fresh("k")
    out.push(let_(k, self.step_key(st)))
    keys.push(k)
    let r = self.g.fresh("r")
    out.push(
      let_(r, call(self.step_fn(st), [get(rs[rs.length() - 1]), get(k)])),
    )
    rs.push(r)
  }
  let mut acc = call("tc_method", [get(rs[rs.length() - 1]), i32c(which), a, b])
  let mut i = place.steps.length()
  while i > 0 {
    acc = call(self.put_fn(place.steps[i - 1]), [
      get(rs[i - 1]),
      get(keys[i - 1]),
      acc,
    ])
    i = i - 1
  }
  out.push(set(self.state, call("tc_set", [get(self.state), f, acc])))
  out
}

///|
/// A collection method on `@cur`, which is `mutate` with the other root.
fn ECtx::mutate_target(
  self : ECtx,
  steps : Array[@tscript.PathStep],
  which : Int,
  args : Array[@tscript.Expr],
) -> Array[@abi.I] raise Bail {
  let a = if args.length() > 0 {
    self.expr(args[0])
  } else {
    call("tc_null", [])
  }
  let b = if args.length() > 1 {
    self.expr(args[1])
  } else {
    call("tc_null", [])
  }
  let out : Array[@abi.I] = []
  let rs : Array[String] = [self.g.fresh("r")]
  out.push(let_(rs[0], call("tc_target", [get(target_local)])))
  let keys : Array[String] = []
  for st in steps {
    let k = self.g.fresh("k")
    out.push(let_(k, self.step_key(st)))
    keys.push(k)
    let r = self.g.fresh("r")
    out.push(
      let_(r, call(self.step_fn(st), [get(rs[rs.length() - 1]), get(k)])),
    )
    rs.push(r)
  }
  let mut acc = call("tc_method", [get(rs[rs.length() - 1]), i32c(which), a, b])
  let mut i = steps.length()
  while i > 0 {
    acc = call(self.put_fn(steps[i - 1]), [
      get(rs[i - 1]),
      get(keys[i - 1]),
      acc,
    ])
    i = i - 1
  }
  out.push(set(target_local, acc))
  out
}

///|
/// The effects a compiled body may perform.
///
/// Three of the five: `bubble`, `send` and `stop`. `request` and `sendAt` are
/// refused rather than approximated — a request carries a `request-opts`
/// record and a `sendAt` a relative path, and both are shapes this generator
/// would have to lower into the canonical ABI to get right rather than nearly
/// right.
fn ECtx::effect(
  self : ECtx,
  name : String,
  args : Array[@tscript.Expr],
  span : @tscript.Span,
) -> Array[@abi.I] raise Bail {
  if name == "stop" {
    self.g.uses_control = true
    // Buffered, like the other two. A `stop` before a failing statement is a
    // `stop` that did not happen.
    return [
      call("tc_effect_push", [i32c(3), call("tc_empty_str", []), nullref()]),
    ]
  }
  guard name is ("send" | "bubble") else {
    self.bail(
      "`" +
      name +
      "` is an effect this generator does not compile yet — `send`, `bubble` and `stop` are the ones it does",
      span,
    )
    return []
  }
  guard args.length() >= 1 else {
    self.bail("`" + name + "` needs a message name", span)
    return []
  }
  guard args.length() <= 5 else {
    self.bail(
      "`" + name + "` with more than four payload values is not compiled yet",
      span,
    )
    return []
  }
  self.g.uses_control = true
  let msg = self.g.fresh("msg")
  let pl = self.g.fresh("pl")
  let payload : Array[@abi.I] = []
  for i, a in args {
    if i > 0 {
      payload.push(self.expr(a))
    }
  }
  [
    // The name crosses as a string, so whatever the expression evaluated to
    // becomes one — the same text a template interpolates through.
    let_(msg, call("tc_display", [self.expr(args[0])])),
    let_(pl, arg_list(payload)),
    // BUFFERED, not sent. The host cannot un-hear a `send`, and the
    // interpreter drops the effects of a transition that is abandoned — so
    // these are held until the contracts have held and flushed then.
    call("tc_effect_push", [
      i32c(if name == "bubble" { 2 } else { 1 }),
      get(msg),
      get(pl),
    ]),
  ]
}
