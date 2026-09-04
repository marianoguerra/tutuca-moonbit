// Declarations, and the one op-coded `call` they hang off.

///|
/// Every declaration of a component, plus the dispatch that reaches them.
///
/// A declaration that cannot be lowered is REFUSED and left out of both the
/// dispatch and the manifest, so a host is never told a component answers
/// something it does not. The card still compiles and the rest of it still
/// runs; the host hears `unhandled` for that one name and falls back to
/// whatever the declared field implies, exactly as it would for a handler
/// nobody wrote.
fn emit_decls(src : Src, c : Comp) -> Unit {
  let callable : Map[String, @tscript.DeclKind] = Map([])
  for d in c.decls {
    callable[d.name] = d.kind
  }
  // RULES FIRST, and the order is load-bearing rather than tidy: a transition
  // is guarded by every invariant the component declares, so it cannot be
  // emitted until it is known which invariants lowered.
  let rules = c.decls.filter(d => d.kind is (DPred | DInvariant))
  let rest = c.decls.filter(d => !(d.kind is (DPred | DInvariant)))
  // The FORMAT sentences first, because a rule's guard asks whether its own
  // sentence lowered before it decides what to say.
  let formats : @set.Set[String] = Set([])
  for d in rules {
    guard d.format is Some(text) else { continue }
    let ctx = rule_ctx(c, callable, d, formats)
    let body = Src::new()
    body.depth = 1
    try {
      let v = emit_expr(ctx, body, text)
      let t = ctx.temp()
      body.line("let \{t} = \{v};")
      body.line("if \{t} == null { return tg_null(); }")
      body.line(t)
      src.line(
        "fn \{c.id}_format_\{mangle(d.name)}(f: &tg_vals, args: &tg_vals, dyn: &?tg_val) -> &?tg_val {",
      )
      src.buf.write_string(body.text())
      src.line("}")
      src.blank()
      formats.add(d.name)
    } catch {
      // A sentence that will not lower is not a refusal of the RULE: the rule
      // still holds or does not, and the transition still stops. What is lost
      // is the half that explains it, and the generic line still says which
      // rule declined.
      Refused(_) => ()
    }
  }
  let invariants = []
  for d in rules {
    if lower_one(src, c, callable, [], formats, d) && d.kind is DInvariant {
      invariants.push(d.name)
    }
  }
  // An invariant that did not lower is a guarantee nobody checks, and a
  // transition that ran anyway would be claiming one. So every transition goes
  // with it — refused by name, which is the answer a host can act on.
  let lost = []
  for d in rules {
    if d.kind is DInvariant && !invariants.contains(d.name) {
      lost.push(d.name)
    }
  }
  for d in rest {
    if lost.length() > 0 && (@tscript.is_transition(d.kind) || d.kind is DSet) {
      c.refusals.push({
        comp: c.name,
        kind: @tscript.kind_word(d.kind),
        name: d.name,
        reason: "the invariant " +
        lost.map(n => "`" + n + "`").join(", ") +
        " did not compile, and a transition guarded by a rule that is not there " +
        "would be claiming a guarantee nobody checks",
        line: 0,
        span: d.span,
      })
      continue
    }
    let _ = lower_one(src, c, callable, invariants, formats, d)
  }
  emit_call(src, c)
}

///|
/// Emit one declaration, or record why it could not be.
fn lower_one(
  src : Src,
  c : Comp,
  callable : Map[String, @tscript.DeclKind],
  invariants : Array[String],
  formats : @set.Set[String],
  d : @tscript.Decl,
) -> Bool {
  let ctx = {
    comp: c,
    kind: d.kind,
    params: params_of(d),
    callable,
    temps: 0,
    binds: binds_var(d),
    invariants,
    formats,
    cur: CurNone,
  }
  let body = Src::new()
  body.depth = 1
  let head = decl_head(c, d)
  try {
    emit_decl(ctx, body, d)
    src.line(head)
    src.buf.write_string(body.text())
    src.line("}")
    src.blank()
    true
  } catch {
    Refused(why) => {
      c.refusals.push({
        comp: c.name,
        kind: @tscript.kind_word(d.kind),
        name: d.name,
        reason: why,
        line: 0,
        span: d.span,
      })
      false
    }
  }
}

///|
/// Whether a body needs the `cur` local at all.
///
/// Declared only when used, because Wax has no notion of an intentionally
/// unused binding and every transition would otherwise carry one.
fn uses_cur(stmts : Array[@tscript.Stmt]) -> Bool {
  for s in stmts {
    let hit = match s {
      SNew(..) => true
      SAssign(place~, ..) | SMethod(place~, ..) => place.root is PTarget
      SEffect(args~, ..) => args.iter().any(reads_cur)
      SIf(cond~, then_~, else_~, ..) =>
        reads_cur(cond) || uses_cur(then_) || uses_cur(else_)
    }
    if hit {
      return true
    }
  }
  false
}

///|
fn reads_cur(e : @tutuca.Expr) -> Bool {
  match e {
    ERead(place~, ..) | ERef(place~, ..) => place.root is PTarget
    EApp(args~, ..) => args.iter().any(reads_cur)
    EChain(operands~, ..) => operands.iter().any(reads_cur)
    EUnary(operand~, ..) => reads_cur(operand)
    EIf(cond~, then_~, else_~, ..) =>
      reads_cur(cond) || reads_cur(then_) || reads_cur(else_)
    ETpl(parts~, ..) =>
      parts
      .iter()
      .any(p => {
        match p {
          TExpr(inner) => reads_cur(inner)
          TText(..) => false
        }
      })
    _ => false
  }
}

///|
/// The context a rule's `format` sentence is emitted in: it reads the state and
/// the arguments exactly as the rule itself does.
fn rule_ctx(
  c : Comp,
  callable : Map[String, @tscript.DeclKind],
  d : @tscript.Decl,
  formats : @set.Set[String],
) -> Ctx {
  {
    comp: c,
    kind: d.kind,
    params: params_of(d),
    callable,
    temps: 0,
    binds: None,
    invariants: [],
    formats,
    cur: CurNone,
  }
}

///|
/// An enricher accumulates into a local and answers it; nothing else does.
fn binds_var(d : @tscript.Decl) -> String? {
  match d.kind {
    DEnrich | DBindWith => Some("binds")
    _ => None
  }
}

///|
fn params_of(d : @tscript.Decl) -> Map[String, Int] {
  let out : Map[String, Int] = Map([])
  for i, p in d.params {
    out[p.name] = i
  }
  out
}

///|
/// The signature a declaration compiles to.
///
/// Two shapes and no more. A TRANSITION is handed the state's slots and the
/// dispatch's arguments and answers the successor's slots, or null for "it did
/// not happen". A CALLABLE is handed the same and answers a value, or null for
/// "there is no answer" — which is the same null, meaning the same thing, in
/// the only two places a declaration can end.
fn decl_head(c : Comp, d : @tscript.Decl) -> String {
  let n = mangle(d.name)
  match d.kind {
    DReceive =>
      "fn \{c.id}_receive_\{n}(f: &tg_vals, args: &tg_vals, dyn: &?tg_val) -> &?tg_vals {"
    DAnswer =>
      "fn \{c.id}_answer_\{n}(f: &tg_vals, args: &tg_vals, dyn: &?tg_val) -> &?tg_vals {"
    DSet =>
      "fn \{c.id}_set_\{n}(f: &tg_vals, args: &tg_vals, dyn: &?tg_val) -> &?tg_vals {"
    DCompute =>
      "fn \{c.id}_compute_\{n}(f: &tg_vals, args: &tg_vals, dyn: &?tg_val) -> &?tg_val {"
    DGet =>
      "fn \{c.id}_get_\{n}(f: &tg_vals, args: &tg_vals, dyn: &?tg_val) -> &?tg_val {"
    DPred =>
      "fn \{c.id}_pred_\{n}(f: &tg_vals, args: &tg_vals, dyn: &?tg_val) -> &?tg_val {"
    DInvariant =>
      "fn \{c.id}_invariant_\{n}(f: &tg_vals, args: &tg_vals, dyn: &?tg_val) -> &?tg_val {"
    DEnrich =>
      "fn \{c.id}_enrich_\{n}(f: &tg_vals, args: &tg_vals, dyn: &?tg_val) -> &?tg_val {"
    DBindWith =>
      "fn \{c.id}_bindwith_\{n}(f: &tg_vals, args: &tg_vals, dyn: &?tg_val) -> &?tg_val {"
    // Unreachable: every kind is above. Wax needs the arm; the reader does not.
  }
}

///|
fn emit_decl(ctx : Ctx, src : Src, d : @tscript.Decl) -> Unit raise Refused {
  // An enricher's body is statements and it answers a MAP, so it is neither a
  // transition over the state nor a single value. It gets its own shape.
  if ctx.binds is Some(b) {
    guard d.body is Stmts(stmts) else {
      raise Refused(
        "an enricher accumulates bindings, and this one is a single value",
      )
    }
    // A scope enricher is handed no row at all, so it starts from nothing; a
    // row enricher starts from the map the renderer passed in.
    let start = if d.kind is DEnrich {
      "tg_arg_at(args, 0)"
    } else {
      "tg_map([tg_entries| null; 0])"
    }
    src.line("let \{b}: &?tg_val = \{start};")
    emit_stmts(ctx, src, stmts)
    src.line(b)
    return
  }
  let transition = @tscript.is_transition(d.kind) || d.kind is DSet
  match d.body {
    Stmts(stmts) => {
      guard transition else {
        raise Refused(
          "a \{@tscript.kind_word(d.kind)} answers a value and this one has a body of statements",
        )
      }
      // `requires` guards before anything happens; `ensures` and the
      // invariants hold after. Both are the language's guarantees rather than
      // a handler's, which is why they are emitted around the body instead of
      // inside it.
      emit_attach(ctx, src, d.name, d.requires_, "requires")
      // `cur` is a single FUNCTION-LEVEL local, so "no `new` has run yet" is
      // the null it starts at and a `new` inside an `if` survives the branch.
      // That is not looseness: the interpreter does the same — both arms get
      // one `Env` — and the checker makes the difference unobservable, because
      // a `new` in one arm leaves the target unset and reading `cur` after it
      // is `NO_TARGET`.
      if uses_cur(stmts) {
        src.line("let cur: &?tg_val = null;")
      }
      emit_stmts(ctx, src, stmts)
      emit_attach(ctx, src, d.name, d.ensures_, "ensures")
      // THE INVARIANTS — the rules nothing has to mention.
      //
      // A `requires` and an `ensures` are named by the handler they guard; an
      // invariant is checked after EVERY transition the component declares,
      // including the ones written without a thought for it. That is the whole
      // difference between a contract and an `if` at the top of a body, and
      // leaving it out is how `overbook` seated seven people in a room with
      // six chairs.
      for name in ctx.invariants {
        emit_rule_guard(
          ctx,
          src,
          DInvariant,
          name,
          "contract: `\{d.name}` was abandoned — it broke the invariant `\{name}`",
        )
      }
      src.line("f")
    }
    Value(e) => {
      guard !transition else {
        raise Refused(
          "a \{@tscript.kind_word(d.kind)} is a transition and this one is a single value",
        )
      }
      let v = emit_expr(ctx, src, e)
      // A CALLABLE with no answer answers the null VALUE; a TRANSITION with no
      // answer does not happen. Both are the same `ref.null` on the way up and
      // they part here, at the only boundary where the difference is
      // observable — which is why the format keeps `ref.null` and `kind 0`
      // apart in the first place.
      let t = ctx.temp()
      src.line("let \{t} = \{v};")
      src.line("if \{t} == null { return tg_null(); }")
      src.line(t)
    }
  }
}

///|
/// A `requires` or an `ensures`, as a guard around the body.
///
/// A rule that does not hold makes the transition NOT HAPPEN, which is the
/// whole of what a contract is here. It is not a thrown error and not a logged
/// warning: the state does not change, and a scene asserts that.
fn emit_attach(
  ctx : Ctx,
  src : Src,
  handler : String,
  attach : @tscript.Attach?,
  which : String,
) -> Unit raise Refused {
  guard attach is Some(a) else { return }
  guard ctx.callable.get(a.name) is Some(kind) else {
    raise Refused("`\{which} \{a.name}` names no rule this component declares")
  }
  guard kind is (DPred | DInvariant) else {
    raise Refused(
      "`\{which} \{a.name}` names a \{@tscript.kind_word(kind)}, not a rule",
    )
  }
  // Word for word from `core/warn.mbt`. A card author reading a log should not
  // have to work out which backend wrote it, and a scene asserting `expect:
  // log` is asserting on THAT sentence — "declined" and "was abandoned" are
  // the two different things a contract does, and they are not
  // interchangeable.
  let line = if which == "requires" {
    "contract: `\{handler}` declined — its precondition `\{a.name}` does not hold"
  } else {
    "contract: `\{handler}` was abandoned — its postcondition `\{a.name}` does not hold after it"
  }
  emit_rule_guard(ctx, src, kind, a.name, line)
}

///|
/// A rule, checked, and SAID when it does not hold.
///
/// A declined transition that says nothing is indistinguishable from a click
/// that missed: the state is the same either way and the DOM cannot tell them
/// apart. That is the difference between a contract and an `if` at the top of a
/// body, and it only exists if somebody hears about it.
///
/// The sentence is `core/warn.mbt`'s, word for word, because a card author
/// reading a log should not have to work out which backend wrote it. The rule's
/// own `format` clause follows, evaluated over the state that was rejected —
/// the half only the rule's author could have written.
fn emit_rule_guard(
  ctx : Ctx,
  src : Src,
  kind : @tscript.DeclKind,
  name : String,
  line : String,
) -> Unit {
  let t = ctx.temp()
  src.line(
    "let \{t} = \{ctx.comp.id}_\{callable_suffix(kind)}_\{mangle(name)}(f, args, dyn);",
  )
  src.line("if \{t} == null { return null; }")
  src.open("if tg_truthy(\{t}) == 0 {")
  if ctx.formats.contains(name) {
    let sentence = ctx.temp()
    src.line(
      "let \{sentence} = \{ctx.comp.id}_format_\{mangle(name)}(f, args, dyn);",
    )
    src.open("if \{sentence} == null {")
    src.line("eff_log(\{wax_str(line)});")
    src.close("} else {")
    src.depth = src.depth + 1
    src.line("eff_log(concat(\{wax_str(line + ": ")}, display(\{sentence})));")
    src.depth = src.depth - 1
    src.line("}")
  } else {
    src.line("eff_log(\{wax_str(line)});")
  }
  src.line("return null;")
  src.close("}")
}

///|
/// The single op-coded `call`.
///
/// One entry point rather than one vtable slot per operation, because the
/// vtable's TYPE is inside the frozen group and a slot added later would change
/// the identity of every type in it. An `i32` op space extends forever.
fn emit_call(src : Src, c : Comp) -> Unit {
  let lowered = (d : @tscript.Decl) => {
    !c.refusals.iter().any(r => r.name == d.name)
  }
  src.open("fn \{c.id}_call: tg_call(self: &tg_inst, op: i32, name: &tg_bytes,")
  src.line("                        args: &tg_vals, v: &?tg_val) -> &?tg_val {")
  src.depth = src.depth - 1
  src.depth = src.depth + 1
  src.line("let st = self.state! as &\{c.id}_state;")
  src.blank()

  src.line(
    "// OpImplements — asked of the INSTANCE, with no catalog in the path.",
  )
  src.open("if op == \{op_code(OpImplements)} {")
  if c.def.implements.length() == 0 {
    src.line("return tg_bool(0);")
  } else {
    for id in c.def.implements {
      src.line("if str_eq(name, \{wax_str(id)}) != 0 { return tg_bool(1); }")
    }
    src.line("return tg_bool(0);")
  }
  src.close("}")
  src.blank()

  src.line(
    "// OpWithField — the COW write-through a host path writes through.",
  )
  src.open("if op == \{op_code(OpWithField)} {")
  src.line("let i = \{c.id}_slot(name);")
  src.line("if i <s 0 { return null; }")
  src.line("let f = \{c.id}_copy(st);")
  src.line("f[i] = v;")
  src.line("return tg_comp(\{c.id}_inst(self.desc, f));")
  src.close("}")
  src.blank()

  // A property declared `pub count: Int { get .count set .count }` is BACKED
  // BY A FIELD: the spec block says where it lives, and no `set count` is
  // written in the script because there is nothing to write. So the accessor
  // is synthesized here, from the declaration, rather than looked up among the
  // script's own arms — and only when the script wrote none, because an
  // explicit `set` is the author overriding the backing.
  let field_backed = (pick : (@statedef.PropertyDef) -> String?) => {
    let out : Array[(String, String)] = []
    for prop in c.def.properties {
      guard pick(prop) is Some(src_) else { continue }
      guard src_.has_prefix(".") else { continue }
      out.push((prop.name, src_[1:].to_owned()))
    }
    out
  }
  let backed_set = field_backed(prop => prop.setter).filter(pair => {
    !c.decls.iter().any(d => d.kind is DSet && d.name == pair.0)
  })
  if backed_set.length() > 0 {
    src.open("if op == \{op_code(OpSetProperty)} {")
    for pair in backed_set {
      let (prop, field) = pair
      src.open("if str_eq(name, \{wax_str(prop)}) != 0 {")
      src.line("let i = \{c.id}_slot(\{wax_str(field)});")
      src.line("if i <s 0 { return null; }")
      src.line("let f = \{c.id}_copy(st);")
      src.line("f[i] = v;")
      src.line("return tg_comp(\{c.id}_inst(self.desc, f));")
      src.close("}")
    }
    src.close("}")
    src.blank()
  }
  for
    pair in [
      (@abi.Op::OpHandleMessage, @tscript.DeclKind::DReceive),
      (OpHandleIntent, DAnswer),
      (OpSetProperty, DSet),
    ] {
    let (op, kind) = pair
    let arms = c.decls.filter(d => d.kind == kind && lowered(d))
    if arms.length() == 0 {
      continue
    }
    src.open("if op == \{op_code(op)} {")
    src.line("let f = \{c.id}_copy(st);")
    for d in arms {
      let prefix = transition_prefix(kind)
      src.open("if str_eq(name, \{wax_str(d.name)}) != 0 {")
      // A property write is handed its value rather than an argument list, so
      // it arrives as `v` and is spliced in as argument zero.
      if kind is DSet {
        src.line("let a = [tg_vals| null; 1];")
        src.line("a[0] = v;")
        // A property write is the one op whose fifth slot already carries a
        // value, so there is nowhere for the bindings to ride and a `*name`
        // in a `set` body reads null. The checker says so; nothing here can.
        src.line("let next = \{c.id}_\{prefix}_\{mangle(d.name)}(f, a, null);")
      } else {
        src.line("let next = \{c.id}_\{prefix}_\{mangle(d.name)}(f, args, v);")
      }
      // Null is "it did not happen": a rule declined, or an operation had no
      // answer. The host hears no successor and the state does not change.
      src.line("if next == null { return null; }")
      src.line("return tg_comp(\{c.id}_inst(self.desc, next!));")
      src.close("}")
    }
    src.close("}")
    src.blank()
  }

  let backed_get = field_backed(prop => prop.getter).filter(pair => {
    !c.decls.iter().any(d => d.kind is DGet && d.name == pair.0)
  })
  if backed_get.length() > 0 {
    src.open("if op == \{op_code(OpGetProperty)} {")
    for pair in backed_get {
      let (prop, field) = pair
      src.open("if str_eq(name, \{wax_str(prop)}) != 0 {")
      src.line("let i = \{c.id}_slot(\{wax_str(field)});")
      src.line("if i <s 0 { return null; }")
      src.line("return st.fields[i];")
      src.close("}")
    }
    src.close("}")
    src.blank()
  }

  // A `pred` answers on TWO ops, and that is the language rather than a
  // convenience: read as a method it answers its own expression, and reached
  // through `@when` it answers that value's truthiness. One generated function,
  // two doors.
  for
    pair in [
      (@abi.Op::OpCompute, [@tscript.DeclKind::DCompute, DPred, DInvariant]),
      (OpWhen, [DPred, DInvariant]),
      (OpGetProperty, [DGet]),
      (OpEnrich, [DEnrich]),
      (OpEnrichScope, [DBindWith]),
    ] {
    let (op, kinds) = pair
    let arms = c.decls.filter(d => kinds.contains(d.kind) && lowered(d))
    if arms.length() == 0 {
      continue
    }
    src.open("if op == \{op_code(op)} {")
    for d in arms {
      let prefix = callable_prefix(d.kind)
      let call = "\{c.id}_\{prefix}_\{mangle(d.name)}(st.fields, args, v)"
      // A `pred` read as a METHOD answers its own expression; the same pred
      // reached through `@when` answers that value's TRUTHINESS. Truthiness is
      // applied by whoever asked, so a backend that boxed it into the pred
      // would print "true" where a card prints "ada".
      let answer = if op is OpWhen {
        "tg_bool(tg_truthy(\{call}))"
      } else {
        call
      }
      src.line("if str_eq(name, \{wax_str(d.name)}) != 0 { return \{answer}; }")
    }
    src.close("}")
    src.blank()
  }

  src.line(
    "// An op or a name this module does not answer — the same answer an",
  )
  src.line("// older module gives for an op invented after it was built.")
  src.line("null")
  src.close("}")
  src.blank()
}

///|
fn transition_prefix(kind : @tscript.DeclKind) -> String {
  match kind {
    DReceive => "receive"
    DAnswer => "answer"
    DSet => "set"
    _ => "receive"
  }
}

///|
fn callable_prefix(kind : @tscript.DeclKind) -> String {
  match kind {
    DCompute => "compute"
    DPred => "pred"
    DGet => "get"
    DEnrich => "enrich"
    DBindWith => "bindwith"
    DInvariant => "invariant"
    _ => "compute"
  }
}

///|
fn op_code(op : @abi.Op) -> Int {
  op.code()
}
