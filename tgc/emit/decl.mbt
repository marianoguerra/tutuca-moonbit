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
fn emit_decls(b : B, c : Comp) -> Array[@wast.Decl] {
  let out : Array[@wast.Decl] = []
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
    try {
      let body : Array[@wast.Node] = []
      let t = ctx.temp()
      let v = emit_expr(ctx, b, body, text)
      body.push(b.bind(t, v))
      body.push(b.if_(b.is_null(b.var_(t)), [b.ret(Some(b.rt("tg_null", [])))]))
      body.push(b.var_(t))
      out.push(
        b.fn_(
          "\{c.id}_format_\{mangle(d.name)}",
          decl_params(b),
          [opt_val()],
          body,
        ),
      )
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
    if lower_one(b, out, c, callable, [], formats, d) && d.kind is DInvariant {
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
    let _ = lower_one(b, out, c, callable, invariants, formats, d)
  }
  out.push(emit_call(b, c))
  out
}

///|
/// The three parameters every generated declaration takes.
///
/// The state's slots, the dispatch's arguments, and whatever the call's fifth
/// slot carried — the resolved lookups for most ops, the value being written
/// for a property set.
fn decl_params(b : B) -> Array[@wast.Param] {
  [
    b.param("f", abi_type("tg_vals")),
    b.param("args", abi_type("tg_vals")),
    b.param("dyn", opt_val()),
  ]
}

///|
/// Emit one declaration, or record why it could not be.
fn lower_one(
  b : B,
  out : Array[@wast.Decl],
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
  try {
    let body : Array[@wast.Node] = []
    emit_decl(ctx, b, body, d)
    out.push(b.fn_(decl_name(c, d), decl_params(b), [decl_result(d)], body))
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
/// Declared only when used, because wap has no notion of an intentionally
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
/// The name a declaration compiles to.
fn decl_name(c : Comp, d : @tscript.Decl) -> String {
  let n = mangle(d.name)
  let prefix = match d.kind {
    DReceive => "receive"
    DAnswer => "answer"
    DSet => "set"
    DCompute => "compute"
    DGet => "get"
    DPred => "pred"
    DInvariant => "invariant"
    DEnrich => "enrich"
    DBindWith => "bindwith"
  }
  "\{c.id}_\{prefix}_\{n}"
}

///|
/// What a declaration answers.
///
/// Two shapes and no more. A TRANSITION is handed the state's slots and the
/// dispatch's arguments and answers the successor's slots, or null for "it did
/// not happen". A CALLABLE is handed the same and answers a value, or null for
/// "there is no answer" — which is the same null, meaning the same thing, in
/// the only two places a declaration can end.
fn decl_result(d : @tscript.Decl) -> @wast.Type {
  match d.kind {
    DReceive | DAnswer | DSet =>
      Nullable(Named(@abi.preamble_module + ".tg_vals"))
    _ => opt_val()
  }
}

///|
fn emit_decl(
  ctx : Ctx,
  b : B,
  out : Array[@wast.Node],
  d : @tscript.Decl,
) -> Unit raise Refused {
  // An enricher's body is statements and it answers a MAP, so it is neither a
  // transition over the state nor a single value. It gets its own shape.
  if ctx.binds is Some(bind) {
    guard d.body is Stmts(stmts) else {
      raise Refused(
        "an enricher accumulates bindings, and this one is a single value",
      )
    }
    // A scope enricher is handed no row at all, so it starts from nothing; a
    // row enricher starts from the map the renderer passed in.
    let start = if d.kind is DEnrich {
      b.rt("tg_arg_at", [b.var_("args"), b.int_(0)])
    } else {
      b.rt("tg_map", [b.entries_of([])])
    }
    out.push(b.bind(bind, start, typ=opt_val(), mutable=true))
    emit_stmts(ctx, b, out, stmts)
    out.push(b.var_(bind))
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
      // `requires` guards before anything happens; `ensures` and the invariants
      // hold after. Both are the language's guarantees rather than a handler's,
      // which is why they are emitted around the body instead of inside it.
      emit_attach(ctx, b, out, d.name, d.requires_, "requires")
      // `cur` is a single FUNCTION-LEVEL local, so "no `new` has run yet" is
      // the null it starts at and a `new` inside an `if` survives the branch.
      // That is not looseness: the interpreter does the same — both arms get
      // one `Env` — and the checker makes the difference unobservable, because
      // a `new` in one arm leaves the target unset and reading `cur` after it
      // is `NO_TARGET`.
      if uses_cur(stmts) {
        out.push(b.bind("cur", b.null_(), typ=opt_val(), mutable=true))
      }
      emit_stmts(ctx, b, out, stmts)
      emit_attach(ctx, b, out, d.name, d.ensures_, "ensures")
      // THE INVARIANTS — the rules nothing has to mention.
      //
      // A `requires` and an `ensures` are named by the handler they guard; an
      // invariant is checked after EVERY transition the component declares,
      // including the ones written without a thought for it. That is the whole
      // difference between a contract and an `if` at the top of a body, and
      // leaving it out is how `overbook` seated seven people in a room with six
      // chairs.
      for name in ctx.invariants {
        emit_rule_guard(
          ctx,
          b,
          out,
          DInvariant,
          name,
          "contract: `\{d.name}` was abandoned — it broke the invariant `\{name}`",
        )
      }
      out.push(b.var_("f"))
    }
    Value(e) => {
      guard !transition else {
        raise Refused(
          "a \{@tscript.kind_word(d.kind)} is a transition and this one is a single value",
        )
      }
      // A CALLABLE with no answer answers the null VALUE; a TRANSITION with no
      // answer does not happen. Both are the same null on the way up and they
      // part here, at the only boundary where the difference is observable —
      // which is why the format keeps absence and `kind 0` apart in the first
      // place.
      // A CALLABLE with no answer answers the null VALUE; a TRANSITION with no
      // answer does not happen. Both are the same null on the way up and they
      // part here, at the only boundary where the difference is observable —
      // which is why the format keeps absence and `kind 0` apart in the first
      // place.
      let t = ctx.temp()
      let v = emit_expr(ctx, b, out, e)
      out.push(b.bind(t, v))
      out.push(b.if_(b.is_null(b.var_(t)), [b.ret(Some(b.rt("tg_null", [])))]))
      out.push(b.var_(t))
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
  b : B,
  out : Array[@wast.Node],
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
  // log` is asserting on THAT sentence — "declined" and "was abandoned" are the
  // two different things a contract does, and they are not interchangeable.
  let line = if which == "requires" {
    "contract: `\{handler}` declined — its precondition `\{a.name}` does not hold"
  } else {
    "contract: `\{handler}` was abandoned — its postcondition `\{a.name}` does not hold after it"
  }
  emit_rule_guard(ctx, b, out, kind, a.name, line)
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
  b : B,
  out : Array[@wast.Node],
  kind : @tscript.DeclKind,
  name : String,
  line : String,
) -> Unit {
  let t = ctx.temp()
  out.push(
    b.bind(
      t,
      b.call("\{ctx.comp.id}_\{callable_suffix(kind)}_\{mangle(name)}", [
        b.var_("f"),
        b.var_("args"),
        b.var_("dyn"),
      ]),
    ),
  )
  out.push(b.if_(b.is_null(b.var_(t)), [b.ret(Some(b.null_()))]))
  let said : Array[@wast.Node] = []
  if ctx.formats.contains(name) {
    let sentence = ctx.temp()
    said.push(
      b.bind(
        sentence,
        b.call("\{ctx.comp.id}_format_\{mangle(name)}", [
          b.var_("f"),
          b.var_("args"),
          b.var_("dyn"),
        ]),
      ),
    )
    said.push(
      b.if_(b.is_null(b.var_(sentence)), [b.rt("eff_log", [b.str_(line)])], else_=[
        b.rt("eff_log", [
          b.rt("concat", [
            b.str_(line + ": "),
            b.rt("display", [b.var_(sentence)]),
          ]),
        ]),
      ]),
    )
  } else {
    said.push(b.rt("eff_log", [b.str_(line)]))
  }
  said.push(b.ret(Some(b.null_())))
  out.push(
    b.if_(b.made(Bin(Eq, b.rt("tg_truthy", [b.var_(t)]), b.int_(0))), said),
  )
}

///|
/// The single op-coded `call`.
///
/// One entry point rather than one vtable slot per operation, because the
/// vtable's TYPE is inside the frozen group and a slot added later would change
/// the identity of every type in it. An `i32` op space extends forever.
///
/// It is one of the two functions `retype_named` gives its frozen type after
/// wap has lowered it — wap cannot annotate a definition with a named function
/// type, and `tg_call` is one.
fn emit_call(b : B, c : Comp) -> @wast.Decl {
  let lowered = (d : @tscript.Decl) => {
    !c.refusals.iter().any(r => r.name == d.name)
  }
  let body : Array[@wast.Node] = []
  let st = b.made(
    Cast(
      b.force(b.made(Field(b.var_("self"), "state"))),
      Named("\{c.id}_state"),
    ),
  )
  body.push(b.bind("st", st))
  let names_match = (name : String) => {
    b.made(Bin(Ne, b.rt("str_eq", [b.var_("name"), b.str_(name)]), b.int_(0)))
  }
  let op_is = (op : @abi.Op) => b.made(Bin(Eq, b.var_("op"), b.int_(op.code())))

  // OpImplements — asked of the INSTANCE, with no catalog in the path.
  let impl_body : Array[@wast.Node] = []
  for id in c.def.implements {
    impl_body.push(
      b.if_(names_match(id), [b.ret(Some(b.rt("tg_bool", [b.int_(1)])))]),
    )
  }
  impl_body.push(b.ret(Some(b.rt("tg_bool", [b.int_(0)]))))
  body.push(b.if_(op_is(OpImplements), impl_body))

  // OpWithField — the COW write-through a host path writes through.
  body.push(
    b.if_(op_is(OpWithField), [
      b.bind("i", b.call("\{c.id}_slot", [b.var_("name")])),
      b.if_(b.made(Bin(Lt, b.var_("i"), b.int_(0))), [b.ret(Some(b.null_()))]),
      b.bind("wf", b.call("\{c.id}_copy", [b.var_("st")])),
      b.set(b.made(Index(b.var_("wf"), b.var_("i"))), b.var_("v")),
      b.ret(
        Some(
          b.rt("tg_comp", [
            b.call("\{c.id}_inst", [
              b.made(Field(b.var_("self"), "desc")),
              b.var_("wf"),
            ]),
          ]),
        ),
      ),
    ]),
  )

  // A property declared `pub count: Int { get .count set .count }` is BACKED BY
  // A FIELD: the spec block says where it lives, and no `set count` is written
  // in the script because there is nothing to write. So the accessor is
  // synthesized here, from the declaration, rather than looked up among the
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
    let arms : Array[@wast.Node] = []
    for pair in backed_set {
      let (prop, field) = pair
      arms.push(
        b.if_(names_match(prop), [
          b.bind("i", b.call("\{c.id}_slot", [b.str_(field)])),
          b.if_(b.made(Bin(Lt, b.var_("i"), b.int_(0))), [
            b.ret(Some(b.null_())),
          ]),
          b.bind("sp", b.call("\{c.id}_copy", [b.var_("st")])),
          b.set(b.made(Index(b.var_("sp"), b.var_("i"))), b.var_("v")),
          b.ret(
            Some(
              b.rt("tg_comp", [
                b.call("\{c.id}_inst", [
                  b.made(Field(b.var_("self"), "desc")),
                  b.var_("sp"),
                ]),
              ]),
            ),
          ),
        ]),
      )
    }
    body.push(b.if_(op_is(OpSetProperty), arms))
  }
  for
    pair in [
      (@abi.Op::OpHandleMessage, @tscript.DeclKind::DReceive),
      (OpHandleIntent, DAnswer),
      (OpSetProperty, DSet),
    ] {
    let (op, kind) = pair
    let arms_decls = c.decls.filter(d => d.kind == kind && lowered(d))
    if arms_decls.length() == 0 {
      continue
    }
    let arms : Array[@wast.Node] = [
      b.bind("tf", b.call("\{c.id}_copy", [b.var_("st")])),
    ]
    for d in arms_decls {
      let inner : Array[@wast.Node] = []
      // A property write is handed its value rather than an argument list, so
      // it arrives as `v` and is spliced in as argument zero.
      let call_args = if kind is DSet {
        [b.var_("tf"), b.vals_of([b.var_("v")]), b.null_()]
      } else {
        [b.var_("tf"), b.var_("args"), b.var_("v")]
      }
      inner.push(b.bind("next", b.call(decl_name(c, d), call_args)))
      // Null is "it did not happen": a rule declined, or an operation had no
      // answer. The host hears no successor and the state does not change.
      inner.push(b.if_(b.is_null(b.var_("next")), [b.ret(Some(b.null_()))]))
      inner.push(
        b.ret(
          Some(
            b.rt("tg_comp", [
              b.call("\{c.id}_inst", [
                b.made(Field(b.var_("self"), "desc")),
                b.force(b.var_("next")),
              ]),
            ]),
          ),
        ),
      )
      arms.push(b.if_(names_match(wire_name(c, d)), inner))
    }
    body.push(b.if_(op_is(op), arms))
  }
  let backed_get = field_backed(prop => prop.getter).filter(pair => {
    !c.decls.iter().any(d => d.kind is DGet && d.name == pair.0)
  })
  if backed_get.length() > 0 {
    let arms : Array[@wast.Node] = []
    for pair in backed_get {
      let (prop, field) = pair
      arms.push(
        b.if_(names_match(prop), [
          b.bind("gi", b.call("\{c.id}_slot", [b.str_(field)])),
          b.if_(b.made(Bin(Lt, b.var_("gi"), b.int_(0))), [
            b.ret(Some(b.null_())),
          ]),
          b.ret(
            Some(
              b.made(Index(b.made(Field(b.var_("st"), "fields")), b.var_("gi"))),
            ),
          ),
        ]),
      )
    }
    body.push(b.if_(op_is(OpGetProperty), arms))
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
    let arms_decls = c.decls.filter(d => kinds.contains(d.kind) && lowered(d))
    if arms_decls.length() == 0 {
      continue
    }
    let arms : Array[@wast.Node] = []
    for d in arms_decls {
      let call = b.call(decl_name(c, d), [
        b.made(Field(b.var_("st"), "fields")),
        b.var_("args"),
        b.var_("v"),
      ])
      // A `pred` read as a METHOD answers its own expression; the same pred
      // reached through `@when` answers that value's TRUTHINESS. Truthiness is
      // applied by whoever asked, so a backend that boxed it into the pred
      // would print "true" where a card prints "ada".
      let answer = if op is OpWhen {
        b.rt("tg_bool", [b.rt("tg_truthy", [call])])
      } else {
        call
      }
      arms.push(b.if_(names_match(wire_name(c, d)), [b.ret(Some(answer))]))
    }
    body.push(b.if_(op_is(op), arms))
  }

  // An op or a name this module does not answer — the same answer an older
  // module gives for an op invented after it was built.
  body.push(b.null_())
  b.fn_(
    "\{c.id}_call",
    [
      b.param("self", abi_type("tg_inst")),
      b.param("op", I32),
      b.param("name", abi_type("tg_bytes")),
      b.param("args", abi_type("tg_vals")),
      b.param("v", opt_val()),
    ],
    [opt_val()],
    body,
  )
}

///|
/// The name a handler ANSWERS TO — the runtime name, always.
///
/// A declaration's own spelling is a local one. `receive Holder::hold` names a
/// protocol by the alias this file imported it under, and `receive hold` names
/// it by the bare member; the schema resolved both to `x/Holder@1::hold` before
/// either was read, and that is the only name a host has ever heard of.
///
/// Matching on the declaration's spelling instead is the bug `tscript/emit_mbt`
/// fixed for the ahead-of-time path — see `E::wire_name` there, whose comment
/// describes this exact failure: the arm listens for one name, every sender
/// emits another, and the handler never runs, silently. This backend had it
/// too, and worse: it answered the SCRIPT's spelling, so `receive hold` and
/// `receive Holder::hold` produced two different dispatch names for one
/// operation, neither of them the one a compiled component answers to.
///
/// Matched against the schema by EITHER spelling, which is what collapses all
/// three onto one.
fn wire_name(c : Comp, d : @tscript.Decl) -> String {
  let cases = if d.kind is DAnswer { c.def.intent } else { c.def.receive }
  for m in cases {
    if m.name == d.name || m.source_name == d.name {
      return m.name
    }
  }
  d.name
}
