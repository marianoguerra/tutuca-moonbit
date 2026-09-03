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
fn ECtx::stmts(
  self : ECtx,
  ss : Array[@tscript.Stmt],
) -> Array[@abi.I] raise Bail {
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
/// Refuse a path that descends INTO a child instance.
///
/// `.items[0].text` reads a token and answers null; `.focus.text = 'x'` writes
/// into a value that is not a record and abandons the transition. Both fail
/// silently at run time, which is the worst of the three outcomes available —
/// a card author sees a handler that does nothing and no reason why.
///
/// It is not a gap this backend could close. A child belongs to the HOST: the
/// guest holds a token, the instance is constructed after the current call
/// returns, and there is nothing on the boundary for a guest to read a child's
/// field through. A card reaches a child by SENDING it a message.
///
/// The walk stops at the first type it cannot follow. That is deliberate: a
/// `record` field's members are not in `index`, and refusing what it cannot see
/// would turn "this backend does not know" into "you may not".
fn ECtx::refuse_into_child(
  self : ECtx,
  name : String,
  steps : Array[@tutuca.PathStep],
  span : @tutuca.Span,
) -> Unit raise Bail {
  guard self.g.field_ty(name) is Some(ty) else { return }
  let mut at = ty
  for i, st in steps {
    if at is TyComp(_) {
      self.bail(
        "`." +
        name +
        "` holds a child component, and a card cannot read or write through one — the instance belongs to the host and a guest holds only a token. Send it a message instead",
        span,
      )
      return
    }
    ignore(i)
    match (at, st) {
      (TyList(e), PIndex(_)) => at = e
      (TyOMap(v), PIndex(_)) => at = v
      (TyOption(inner), _) => {
        at = inner
        continue
      }
      // Anything else — a record's member, an `Any`, a variant's payload — is
      // a type this walk does not follow, and stopping is the honest answer.
      _ => return
    }
  }
}

///|
/// A value on its way into a field, truncated if the field is an integer.
///
/// The schema cannot do this. tutuca has ONE number type, so an `Int` field and
/// a `Double` field are both `jv_type_f64` and nothing in the record layer can
/// tell them apart — but the interpreter truncates on the way into an Int
/// — the corpus pins it — so the compiled backend has to emit the
/// truncation at the sites where it knows.
fn Gen::coerce(self : Gen, name : String, v : @abi.I) -> @abi.I {
  match self.field_ty(name) {
    Some(TyInt(..)) => call("tc_trunc", [v])
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
        // `@tag = str @value` — an enricher writes BINDINGS, not state, and the
        // map it writes is what it answers with. Only an enricher has one, so
        // this is still a refusal everywhere else.
        PBind(b) if self.bind_local is Some(_) =>
          self.assign_bind(b, place.steps, op, value)
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
    SEffect(name~, args~, route~, span~) => self.effect(name, args, route, span)
    SMethod(place~, call~, args~, span~) => self.mutate(place, call, args, span)
    // `new Label` — the zero of a declared type, into `@cur`.
    //
    // Resolved and built HERE rather than at run time: a zero is a property of
    // a declared type, and the type is written in the source. A type nothing
    // can name is a refusal where the interpreter abandons the transition, so
    // the card is told when it compiles instead of when it runs.
    SNew(ty~, span~) => {
      // A SIBLING component first, because a component and a record can share
      // a name and the child is the more surprising one to have shadowed —
      // the same order `statedef` resolves a field's type in.
      if ty.args.is_empty() && self.g.siblings.contains(ty.name) {
        self.uses_target = true
        self.uses_child = true
        self.g.uses_children = true
        return [
          // Pending: an empty argument map, and the component it is for.
          set(target_local, call("jv_ordered_map_empty", [])),
          set(child_local, i32c(self.g.pool.string_index(ty.name))),
        ]
      }
      guard @info.zero_of_ref(self.g.def, ty) is Some(zero) else {
        self.bail(
          "`new " + ty.to_source() + "` names a type this card does not declare",
          span,
        )
        return []
      }
      self.uses_target = true
      [
        set(target_local, const_value(self.g, zero)),
        // Not a child. A second `new` starts over, and starting over has to
        // clear the marker too or a record would materialize as one.
        set(child_local, i32c(-1)),
      ]
    }
  }
}

///|
/// `.field = e`, `.field += e`, and the same through a path.
///
/// The path case walks DOWN into locals and rebuilds UP through
/// `tc_step_put` — a read down and a rebuild up, spelled as
/// a chain of temporaries so that a key expression is evaluated once rather
/// than once per level.
fn ECtx::assign(
  self : ECtx,
  name : String,
  steps : Array[@tutuca.PathStep],
  op : @tscript.AssignOp,
  value : @tutuca.Expr,
  _span : @tutuca.Span,
) -> Array[@abi.I] raise Bail {
  self.refuse_into_child(name, steps, _span)
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
/// `@tag = e`, and the same through a path — an enricher writing a binding.
///
/// Structurally the same walk as a field assignment, and simpler in one way
/// that matters: there is no schema. A binding has no declared type, so nothing
/// truncates and nothing validates, and a name nobody bound yet is created
/// rather than refused. That is what `Env.binds` is in the interpreter — a
/// plain map — and reading one back sees the write, which is what makes the
/// corpus's `@echo = str @tag` answer what it does.
fn ECtx::assign_bind(
  self : ECtx,
  name : String,
  steps : Array[@tutuca.PathStep],
  op : @tscript.AssignOp,
  value : @tutuca.Expr,
) -> Array[@abi.I] raise Bail {
  guard self.bind_local is Some(b) else { return [] }
  let out : Array[@abi.I] = []
  let key = text_const_str(self.g.pool, name)
  let rs : Array[String] = [self.g.fresh("r")]
  out.push(let_(rs[0], call("tc_step_field", [get(b), key])))
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
  out.push(set(b, call("tc_bind_put", [get(b), key, acc])))
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
/// The local that says WHICH component the target's arguments are for.
///
/// `-1` for every `new` the language had before children — a declared record,
/// which is a value and not a pending anything. A component's constant-pool
/// index otherwise, which costs nothing to carry: the name is already interned
/// as its record type's.
///
/// A second local rather than a tag inside the value, because the value is an
/// ordinary ordered map while it is pending — that is what lets
/// `@cur.text = .draft` be the read-modify-write it already was, with no arm
/// taught about children.
let child_local : String = "cur_comp"

///|
/// `@cur = e`, and the same through a path.
fn ECtx::assign_target(
  self : ECtx,
  steps : Array[@tutuca.PathStep],
  op : @tscript.AssignOp,
  value : @tutuca.Expr,
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
fn ECtx::step_key(self : ECtx, st : @tutuca.PathStep) -> @abi.I raise Bail {
  match st {
    PField(f) => text_const_str(self.g.pool, f)
    PIndex(e) => self.expr(e)
  }
}

///|
/// Which reader a step uses. See the note in `ECtx::walk`.
fn ECtx::step_fn(self : ECtx, st : @tutuca.PathStep) -> String {
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
fn ECtx::put_fn(self : ECtx, st : @tutuca.PathStep) -> String {
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
/// and the semantics are the corpus's. Four of the
/// eleven — `clear`, `delete`, `set`, `removeAt` — are parsed by tscript and
/// implemented by NEITHER backend: the interpreter answers `None` for them, so
/// compiling them into something would be inventing a meaning the language does
/// not have.
fn ECtx::mutate(
  self : ECtx,
  place : @tutuca.Place,
  name : String,
  args : Array[@tutuca.Expr],
  span : @tutuca.Span,
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
  steps : Array[@tutuca.PathStep],
  which : Int,
  args : Array[@tutuca.Expr],
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
/// An `intent` needs less than it looks like: the block language gives one a
/// name, arguments and a ROUTE, and the route is the only part written at the
/// call site — the answer names come from the schema.
///
/// A `sendAt` needs more. Its first argument is a PLACE, which is reified into
/// `control.path-step`s rather than read — see `send_at_effect`.
/// A route as the one small integer the effect buffer carries
/// (`@abi.route_*`). The WIRE form is the WIT's `list<leg>`, which `flush_fn`
/// lowers this code to.
///
/// Written as WRITTEN: an empty route is `route_none`, not `dyn lex`. The
/// default lives in `@tutuca.IntentOpts::new`, and a compiler that resolved it
/// here would be a second place for it to live — the same rule the parser and
/// the AOT emitter already follow.
fn route_code(route : Array[@tutuca.Leg]) -> Int {
  match route {
    [] => @abi.route_none
    [Dyn] => @abi.route_dyn
    [Lex] => @abi.route_lex
    [Dyn, Lex] => @abi.route_dyn_lex
    [Lex, Dyn] => @abi.route_lex_dyn
    // The parser reads leg words until it finds a literal, so a longer or a
    // repeated route is writable — `forward dyn dyn` parses. It denotes
    // nothing the design gives a meaning to, and the closed table above is
    // where that is said.
    _ => @abi.route_none
  }
}

///|
/// The effect vocabulary as an English list, for the sentence that reports a
/// name that is not in it.
fn effect_list() -> String {
  let words = @tscript.effect_names().map(w => "`" + w + "`")
  match words {
    [] => ""
    [one] => one
    [.. init, last] => init.join(", ") + " and " + last
  }
}

///|
/// Why an effect with too few arguments is refused, in the terms the effect
/// itself is written in.
fn effect_arity_why(name : String, min_args : Int, kind : String) -> String {
  match name {
    "fail" => "`fail` needs the value it answers with"
    // `reply` is on both lines, because which one it is depends on where it is
    // written: in an `intent` body the walk names it and the argument is the
    // value; in a `receive` body the replier names it and the argument is the
    // name. The caller passes the kind so this can say which.
    "reply" =>
      if kind == "intent" {
        "`reply` needs the value it answers with"
      } else {
        "`reply` needs a message name"
      }
    "send" | "intent" => "`" + name + "` needs a message name"
    _ =>
      "`" + name + "` needs at least " + min_args.to_string() + " argument(s)"
  }
}

///|
fn ECtx::effect(
  self : ECtx,
  name : String,
  args : Array[@tutuca.Expr],
  route : Array[@tutuca.Leg],
  span : @tutuca.Span,
) -> Array[@abi.I] raise Bail {
  // The vocabulary is `tscript`'s table and not a second copy of it: an effect
  // the parser accepts and this backend forgot would compile to nothing at all,
  // and the corpus that holds the two backends together cannot see a name
  // neither of them names.
  guard @tscript.effect_min_arity(name) is Some(min_args) else {
    self.bail(
      "`" +
      name +
      "` is not an effect this language has — " +
      effect_list() +
      " are the ones it does",
      span,
    )
    return []
  }
  if name == "drop" {
    self.g.uses_control = true
    // Buffered, like the other two. A `drop` before a failing statement is a
    // `drop` that did not happen.
    return [
      call("tc_effect_push", [i32c(3), call("tc_empty_str", []), nullref()]),
    ]
  }
  if name == "sendAt" {
    // Before the arity guard below: `send_at` says which of its two arguments
    // is missing, and that is the more useful sentence.
    return self.send_at(args, span)
  }
  guard args.length() >= min_args else {
    self.bail(effect_arity_why(name, min_args, self.kind), span)
    return []
  }
  // The three v2 effects that carry no message name. `forward` re-dispatches
  // the one that arrived; `reply` and `fail` are addressed by the walk. Each
  // buffers like the rest, because a `reply` before a failing statement is a
  // `reply` that did not happen.
  if name == "fail" || (name == "reply" && self.kind == "intent") {
    self.g.uses_control = true
    self.g.uses_routed_effects = true
    let pl = self.g.fresh("pl")
    return [
      let_(pl, arg_list([self.expr(args[0])])),
      call("tc_effect_push", [
        i32c(if name == "reply" { 8 } else { 9 }),
        call("tc_empty_str", []),
        get(pl),
      ]),
    ]
  }
  if name == "forward" {
    self.g.uses_control = true
    self.g.uses_routed_effects = true
    let pl = self.g.fresh("pl")
    let amended : Array[@abi.I] = []
    for a in args {
      amended.push(self.expr(a))
    }
    return [
      let_(pl, arg_list(amended)),
      call("tc_effect_push_routed", [
        i32c(7),
        call("tc_empty_str", []),
        get(pl),
        i32c(route_code(route)),
      ]),
    ]
  }
  self.g.uses_control = true
  if @tscript.takes_route(name) {
    self.g.uses_routed_effects = true
  }
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
    let_(msg, self.effect_message(args[0], span)),
    let_(pl, arg_list(payload)),
    // BUFFERED, not sent. The host cannot un-hear a `send`, and the
    // interpreter drops the effects of a transition that is abandoned — so
    // these are held until the contracts have held and flushed then.
    if @tscript.takes_route(name) {
      call("tc_effect_push_routed", [
        i32c(6),
        get(msg),
        get(pl),
        i32c(route_code(route)),
      ])
    } else {
      // A reply carries a name the way a send does, so it is the same shape
      // with a different kind — the difference is who it reaches, and that is
      // the host's to work out.
      call("tc_effect_push", [
        // `reply` here is the `receive`-body one — the intent-body `reply` was
        // taken above — so it is a send with a different kind: the name is
        // written the same way, and who it reaches is the host's to work out.
        i32c(if name == "reply" { 10 } else { 1 }),
        get(msg),
        get(pl),
      ])
    },
  ]
}

///|
fn ECtx::effect_message(
  self : ECtx,
  expr : @tutuca.Expr,
  span : @tutuca.Span,
) -> @abi.I raise Bail {
  match expr {
    ELit(lit=LStr(raw), ..) => text_const_str(self.g.pool, raw)
    EName(name=source_name, ..) =>
      match self.g.def.operation_name(source_name) {
        Some(wire_name) => text_const_str(self.g.pool, wire_name)
        None => {
          self.bail("unknown protocol operation `" + source_name + "`", span)
          call("tc_empty_str", [])
        }
      }
    _ => {
      self.bail(
        "an effect name is a raw quoted name or a declared protocol operation", span,
      )
      call("tc_empty_str", [])
    }
  }
}

///|
/// `sendAt &.place 'name' args…` — the one effect that addresses somewhere else.
///
/// The place is REIFIED rather than read: `&.rows[k]` denotes the position, and
/// a position survives the root being rebuilt, which is what makes an answer
/// land on the row that asked for it. The corpus fixes what a
/// reified path means, and this is the walk that produces one: a `.field` and a following `[key]` pair
/// up into one keyed step, a `.field` with nothing after it is a step of its
/// own, and the root's own name starts the walk.
fn ECtx::send_at(
  self : ECtx,
  args : Array[@tutuca.Expr],
  span : @tutuca.Span,
) -> Array[@abi.I] raise Bail {
  guard args.get(0) is Some(ERef(place~, ..)) else {
    self.bail(
      "`sendAt` addresses a place, so its first argument is `&.field…` — a value would say WHAT to send to rather than WHERE",
      span,
    )
    return []
  }
  // The interpreter requires a string LITERAL here and abandons the transition
  // otherwise, so a computed name is refused when it compiles rather than
  // failing when it runs. `send` and `bubble` take an expression because the
  // interpreter lets them.
  guard args.get(1) is Some(message_expr) else {
    self.bail(
      "`sendAt` needs a raw quoted name or a declared protocol operation", span,
    )
    return []
  }
  guard place.root is PState(root) else {
    self.bail(
      "`sendAt` addresses a place in this card's own state, so the path starts at a `.field`",
      span,
    )
    return []
  }
  let steps : Array[@abi.I] = []
  let mut pending : String? = Some(root)
  for st in place.steps {
    match st {
      PField(name) => {
        match pending {
          Some(f) =>
            steps.push(call("tc_path_field", [text_const_str(self.g.pool, f)]))
          None => ()
        }
        pending = Some(name)
      }
      PIndex(key) => {
        guard pending is Some(field) else {
          self.bail("`sendAt`: `[key]` needs a field to index into", span)
          return []
        }
        // The one form with no wire shape. `&.sheets[.selId]` means "re-read
        // `.selId` on every dispatch" — the interpreter makes it a
        // `SeqAccessStep` for exactly that — and `control.path-step` has no
        // case that says so. Freezing the key instead would be a DIFFERENT
        // path that looks like this one, so it is refused rather than
        // approximated.
        if key is ERead(place=kp, ..) &&
          kp.root is PState(_) &&
          kp.steps.is_empty() {
          self.bail(
            "`sendAt` with a key read from live state re-resolves on every dispatch, and `control.path-step` has no case for that — index by a literal or by a parameter instead",
            span,
          )
          return []
        }
        steps.push(
          call("tc_path_keyed", [
            text_const_str(self.g.pool, field),
            self.expr(key),
          ]),
        )
        pending = None
      }
    }
  }
  match pending {
    Some(f) =>
      steps.push(call("tc_path_field", [text_const_str(self.g.pool, f)]))
    None => ()
  }
  self.g.uses_control = true
  self.g.uses_send_at = true
  let sp = self.g.fresh("path")
  let pl = self.g.fresh("pl")
  let payload : Array[@abi.I] = []
  for i, a in args {
    if i > 1 {
      payload.push(self.expr(a))
    }
  }
  [
    // `arg_list` is a `pv_push` fold over whatever it is handed, so it builds
    // the step list as readily as the payload.
    let_(sp, arg_list(steps)),
    let_(pl, arg_list(payload)),
    // Buffered like the rest. A `sendAt` before a failing statement is a
    // `sendAt` that did not happen — and `tc_path_keyed` may itself be what
    // fails, when the key is not one.
    call("tc_effect_push_at", [
      i32c(5),
      self.effect_message(message_expr, span),
      get(pl),
      get(sp),
    ]),
  ]
}
