// The four exports a card's declarations decide: the callables, the event
// dispatch, and the method dispatch.
//
// Dispatch is a chain of name comparisons rather than a table, for the reason
// it always was: the names are known, there are a handful of them, and a jump
// table would be a second structure that has to agree with the first.
//
// What changed is the comparison. It was `mem_eq` against pool bytes, once per
// arm; the name now arrives as a `utf8_string` lifted ONCE per call, and
// `tc_is` compares cached hashes before it compares any bytes.

///|
/// The local an enricher's bindings live in while its body runs.
///
/// One per emitted function and never nested, so a fixed name is enough — the
/// same argument `target_local` makes for `@cur`.
let bind_local : String = "binds"

///|
/// Which arguments a declaration reached through the RENDER stack is handed.
///
/// `component/instance.mbt` is the authority, and it passes different things to
/// each of the three shapes:
///
///   `@when` pred      (this, key, value, iter)
///   `enrich`          (this, binds, key, value, iter)
///   `enrichScope`     (this)
///
/// `drop_this` takes the receiver off, so what a compiled declaration sees
/// through `call-method` is what is left. A `compute` called from a view slot
/// is handed its own parameters instead and none of this, which is why the map
/// is empty for one: a `compute` that read `@value` would be reading whatever
/// the caller's first argument happened to be.
fn bind_index(kind : @tscript.DeclKind) -> Map[String, Int] {
  match kind {
    DPred | DInvariant => Map([("key", 0), ("value", 1), ("iter", 2)])
    DEnrich => Map([("key", 1), ("value", 2), ("iter", 3)])
    _ => Map([])
  }
}

///|
/// One wasm function per `compute` / `pred` / `invariant` / `enrich` /
/// `enrichScope` that compiles.
///
/// Compiled to a fixpoint: a callable that refers to one which was itself
/// refused has to be refused too, and which those are is not known until the
/// first pass has run. Two rounds settle every card that is not a cycle, and
/// the bound is what stops one that is.
///
/// The two enrichers are here rather than absent, which is what they were: they
/// appeared nowhere in this package at all, so a card using `@enrich-with`
/// compiled "successfully" and quietly lost its bindings. They answer a MAP
/// rather than a value, and their bodies are statements that write `@name`
/// rather than state — see `enrich_body`.
fn callable_fields(g : Gen, decls : Array[@tscript.Decl]) -> Array[@abi.Field] {
  let mut out : Array[@abi.Field] = []
  for _round in 0..<4 {
    let fresh_refusals : Array[Refusal] = []
    let fields : Array[@abi.Field] = []
    let survived : Map[String, @tscript.Decl] = Map([])
    let before = g.callables.length()
    for d in decls {
      guard d.kind is (DCompute | DPred | DInvariant | DEnrich | DEnrichScope) else {
        continue
      }
      guard g.callables.get(d.name) is Some(_) else { continue }
      let enriching = d.kind is (DEnrich | DEnrichScope)
      let ctx : ECtx = {
        g,
        state: "s",
        params: param_index(d),
        binds: bind_index(d.kind),
        bind_local: if enriching {
          Some(bind_local)
        } else {
          None
        },
        args: "args",
        kind: @tscript.kind_word(d.kind),
        name: d.name,
        uses_target: false,
      }
      g.temp = 0
      let sink = g.refusals.length()
      try {
        let body_ = if enriching {
          enrich_body(ctx, d)
        } else {
          match d.body {
            Value(e) => [ctx.expr(e)]
            // A `compute` with a statement body is not a thing the parser
            // makes — `kind_takes_stmts` says so — so reaching here is an AST
            // built by hand.
            Stmts(_) => {
              ctx.bail("a value declaration needs one expression", d.span)
              []
            }
          }
        }
        survived[d.name] = d
        fields.push(
          func(
            callable_fn(d.name),
            params=[("s", rec_), ("args", args_)],
            results=[jv_],
            body=body_,
          ),
        )
      } catch {
        // The refusal it recorded is the one to keep, but only from the round
        // that ends up being the last.
        _ =>
          for i in sink..<g.refusals.length() {
            fresh_refusals.push(g.refusals[i])
          }
      }
      while g.refusals.length() > sink {
        g.refusals.pop() |> ignore
      }
    }
    g.callables.clear()
    for k, v in survived {
      g.callables[k] = v
    }
    out = fields
    if survived.length() == before {
      for r in fresh_refusals {
        g.refusals.push(r)
      }
      break
    }
    if _round == 3 {
      for r in fresh_refusals {
        g.refusals.push(r)
      }
    }
  }
  out
}

///|
/// An enricher's body: the bindings it starts with, what it writes, and the map
/// it answers.
///
/// The two forms differ only in where the map starts. An in-loop `enrich` is
/// handed the row's bindings so it can READ one it did not write — the corpus
/// has `@echo = str @tag` reading a `@tag` bound the line above, and a card can
/// as easily read one an earlier enricher bound. An `enrichScope` is handed
/// nothing and builds its map from empty.
///
/// It answers the WHOLE map rather than only what it added, because a guest
/// cannot write into a host's map: the interpreter's in-loop form mutates the
/// argument it was passed (`tutucard/obj.mbt`), and `call-method` has a return
/// value and no arguments it can reach back through. The host merges what comes
/// back — see `dyncomp/host/dynobj.mbt`.
fn enrich_body(ctx : ECtx, d : @tscript.Decl) -> Array[@abi.I] raise Bail {
  let out : Array[@abi.I] = []
  out.push(
    let_(
      bind_local,
      match d.kind {
        // Arg 0 is the row's bindings, and `tc_binds_in` is what makes a caller
        // that passed something else — or nothing — an empty map rather than a
        // trap.
        DEnrich =>
          call("tc_binds_in", [call("tc_arg_at", [get(ctx.args), i32c(0)])])
        _ => call("tc_binds_empty", [])
      },
    ),
  )
  // A map crosses the boundary, so a card with an enricher can produce a
  // compound value whatever its fields say.
  ctx.g.uses_values = true
  match d.body {
    Stmts(ss) =>
      for i in ctx.stmts(ss) {
        out.push(i)
      }
    // `enrich row { @tag }` is not what anyone writes and not what the parser
    // makes — `kind_takes_stmts` puts both enrichers on the statement side — so
    // a value body here is an AST built by hand.
    Value(_) => {
      ctx.bail("an enricher's body is statements that bind `@name`", d.span)
      return []
    }
  }
  out.push(get(bind_local))
  out
}

///|
/// A declaration's parameters, by position.
fn param_index(d : @tscript.Decl) -> Map[String, Int] {
  let m : Map[String, Int] = Map([])
  for i, p in d.params {
    m[p.name] = i
  }
  m
}

///|
/// An escaped transition: the same wrapper a compiled one gets, with a call to
/// a hand-written function where the body would be.
///
/// The wrapper is the point. A card author writing Wax should have to say what
/// the handler DOES and nothing else — the `requires` still guards, the
/// `ensures` and the invariants still hold, `tc_fail` is still read where the
/// interpreter would have seen a `None`, and the effects the escape buffers are
/// still flushed only once every rule has held. All of that is the language's
/// and none of it is the escape's to reimplement.
fn escape_transition(
  g : Gen,
  e : EscapeFn,
  d : @tscript.Decl?,
  invariants : Array[String],
) -> Array[@abi.I] {
  let ctx : ECtx = {
    g,
    state: "t",
    params: Map([]),
    binds: Map([]),
    bind_local: None,
    args: "args",
    kind: e.kind,
    name: e.name,
    uses_target: false,
  }
  let unchanged = [
    mem("store32", [i32c(@abi.ret_handle_event), i32c(1)]),
    ret(Some(i32c(@abi.ret_handle_event))),
  ]
  fn declined(
    kind : ContractKind,
    rule : String,
    state : String,
  ) -> Array[@abi.I] {
    let out = ctx.contract_log(e.name, kind, rule, state)
    for i in unchanged {
      out.push(i)
    }
    out
  }

  let out : Array[@abi.I] = [
    set("tc_fail", i32c(0)),
    call("tc_effect_reset", []),
  ]
  // A contract the SCRIPT block declared still applies. An escape answers a
  // declaration's body, not its rules — which is what makes it an escape from
  // the expression language rather than from the component's guarantees.
  let requires_ = match d {
    Some(dd) => dd.requires_
    None => None
  }
  match requires_ {
    Some(a) if g.callables.get(a.name) is Some(_) =>
      out.push(
        if_(
          eq(
            call("tc_truthy", [call(callable_fn(a.name), [get("s"), nullref()])]),
            i32c(0),
          ),
          declined(Precondition, a.name, "s"),
          [],
        ),
      )
    _ => ()
  }
  out.push(
    let_(
      "t",
      call("tcx_next", [call(e.fn_name, [get("s"), get("args")]), get("s")]),
    ),
  )
  out.push(if_(ne(get("tc_fail"), i32c(0)), unchanged, []))
  let posts : Array[(ContractKind, String)] = []
  match d {
    Some(dd) =>
      match dd.ensures_ {
        Some(a) if g.callables.get(a.name) is Some(_) =>
          posts.push((Postcondition, a.name))
        _ => ()
      }
    None => ()
  }
  for name in invariants {
    posts.push((Invariant, name))
  }
  for pair in posts {
    let (kind, name) = pair
    out.push(
      if_(
        eq(
          call("tc_truthy", [call(callable_fn(name), [get("t"), nullref()])]),
          i32c(0),
        ),
        declined(kind, name, "t"),
        [],
      ),
    )
  }
  if g.uses_control {
    out.push(call("tc_flush", []))
  }
  out.push(if_(call("tc_same", [get("t"), get("s")]), unchanged, []))
  out.push(mem("store32", [i32c(@abi.ret_handle_event), i32c(2)]))
  out.push(
    mem("store32", [
      i32c(@abi.ret_handle_event + 4),
      call("resource_new", [call("tc_intern", [get("t")])]),
    ]),
  )
  out.push(ret(Some(i32c(@abi.ret_handle_event))))
  out
}

///|
/// `instance.handle-event`: the four buckets, and the transitions in each.
fn handle_event_fn(g : Gen, decls : Array[@tscript.Decl]) -> @abi.Field {
  let invariants = decls
    .filter(d => d.kind is DInvariant && g.callables.get(d.name) is Some(_))
    .map(d => d.name)
  let arms : Array[@abi.I] = []
  for
    pair in [
      (@tscript.DeclKind::DOn, @abi.bucket_input),
      (DReceive, @abi.bucket_receive),
      (DIntent, @abi.bucket_intent),
      (DResponse, @abi.bucket_response),
      (DBubble, @abi.bucket_bubble),
    ] {
    let (kind, bucket) = pair
    let word = @tscript.kind_word(kind)
    let inner : Array[@abi.I] = []
    // The escapes FIRST, so a name the block language also declared and this
    // backend refused is answered by the hand-written function rather than
    // falling through to a compiled arm that does not exist.
    for _key, e in g.escapes {
      guard e.kind == word else { continue }
      g.temp = 0
      let d = decls.filter(x => x.kind == kind && x.name == e.name).get(0)
      inner.push(
        if_(
          call("tc_is", [get("name"), i32c(g.pool.string_index(e.name))]),
          escape_transition(g, e, d, invariants),
          [],
        ),
      )
    }
    for d in decls {
      guard d.kind == kind else { continue }
      // A transition with a VALUE body is not a thing the parser makes
      // (`kind_takes_stmts`), so this is an AST built by hand — and a
      // declaration that leaves without a `Refusal` is exactly the failure the
      // two enrichers used to be: absent from the module, absent from the
      // manifest, and absent from the reason list a host or an author reads.
      guard d.body is Stmts(ss) else {
        g.refuse(
          @tscript.kind_word(d.kind),
          d.name,
          "a transition's body is statements, and this one is a single expression",
          d.span,
        )
        continue
      }
      g.temp = 0
      let sink = g.refusals.length()
      try {
        let block = transition(g, d, invariants, ss)
        // Compiled — but ANSWERED IN WAX, so the arm is the escape's and this
        // one is dropped. It is still built rather than skipped, because a
        // declaration the block language turns away records its reason on the
        // way out, and that reason is the whole story of why the escape is
        // there. Skipping the build to save it would lose the reason with it.
        if !g.escaped(word, d.name) {
          inner.push(
            if_(
              call("tc_is", [get("name"), i32c(g.pool.string_index(d.name))]),
              block,
              [],
            ),
          )
        }
      } catch {
        // Refused, with the reason already recorded against its own span.
        _ => ignore(sink)
      }
    }
    if inner.length() > 0 {
      arms.push(if_(eq(get("b"), i32c(bucket)), inner, []))
    }
  }
  arms.push(mem("store32", [i32c(@abi.ret_handle_event), i32c(0)]))
  arms.push(i32c(@abi.ret_handle_event))
  // The instance, the name and the arguments are lifted ONCE, ahead of every
  // arm. A card with twelve handlers used to compare twelve times against
  // linear memory; it now builds one `utf8_string` and compares hashes.
  let body : Array[@abi.I] = [
    let_("s", call("tc_deref", [get("h")])),
    let_("name", call("tc_str_in", [get("np"), get("nl")])),
    let_("args", call("tc_args_lift", [get("ap"), get("al")])),
  ]
  for i in arms {
    body.push(i)
  }
  func(
    "handle_event",
    params=[
      ("h", i32_),
      ("b", i32_),
      ("np", i32_),
      ("nl", i32_),
      ("ap", i32_),
      ("al", i32_),
    ],
    results=[i32_],
    export_as=@abi.guest_iface + "#[method]instance.handle-event",
    body~,
  )
}

///|
/// Which of the three rules turned a transition away.
///
/// The interpreter reports them through three different functions and each
/// prints a different sentence (`core/warn.mbt`), so the distinction has to
/// survive down to the line this emits.
priv enum ContractKind {
  Precondition
  Postcondition
  Invariant
}

///|
/// The line a declined rule says, and the `control.log` that says it.
///
/// `core/warn.mbt`'s wording, verbatim, because two backends that describe the
/// same refusal differently are two backends a card author has to read twice.
/// Both halves are interned — with and without the `": "` a sentence hangs off
/// — because both are known here, and only whether there IS a sentence is not.
///
/// A rule with no `format` says the short line. So does a rule whose `format`
/// this backend cannot compile, or whose `format` fails when it runs: all three
/// are the empty sentence the language already had, and a refusal that cannot
/// describe itself is still a refusal.
fn ECtx::contract_log(
  self : ECtx,
  handler : String,
  kind : ContractKind,
  rule : String,
  state : String,
) -> Array[@abi.I] {
  let head = match kind {
    Precondition =>
      "contract: `" +
      handler +
      "` declined — its precondition `" +
      rule +
      "` does not hold"
    Postcondition =>
      "contract: `" +
      handler +
      "` was abandoned — its postcondition `" +
      rule +
      "` does not hold after it"
    Invariant =>
      "contract: `" +
      handler +
      "` was abandoned — it broke the invariant `" +
      rule +
      "`"
  }
  self.g.uses_contract_log = true
  let h = text_const_str(self.g.pool, head)
  let hc = text_const_str(self.g.pool, head + ": ")
  let out : Array[@abi.I] = []

  // The rule's own `format`, over the state the rule was ASKED about and with
  // no parameters and no bindings, which is what a contract is: a statement
  // about state and nothing else. The state matters: a precondition is asked about the state as it
  // arrived, and at that point in the transition the successor's local does not
  // exist yet.
  let rule_ctx : ECtx = {
    g: self.g,
    state,
    // A contract is a statement about state: no parameters and no bindings,
    // A contract is a statement about state and nothing else.
    params: Map([]),
    binds: Map([]),
    bind_local: None,
    args: self.args,
    kind: self.kind,
    name: self.name,
    uses_target: false,
  }
  let fmt = match self.g.callables.get(rule) {
    Some(rd) => rd.format
    None => None
  }
  match fmt {
    None =>
      out.push(call("tc_contract_msg", [h, hc, i32c(0), call("tc_null", [])]))
    Some(e) => {
      // Compiling the sentence must not refuse the HANDLER. A `format` this
      // backend cannot build is a sentence the interpreter would also have
      // failed to evaluate, and that is a short line rather than a missing
      // transition — so the refusals it recorded on the way out are rolled
      // back, the way `callable_fields` rolls back a round it discards.
      let sink = self.g.refusals.length()
      try {
        let sentence = rule_ctx.expr(e)
        let tmp = self.g.fresh("say")
        // `tc_fail` is the interpreter's `None`, and a `format` that divides by
        // zero is a sentence that could not be evaluated. Clobbering the flag
        // costs nothing: every path out of here returns `unchanged`.
        out.push(set("tc_fail", i32c(0)))
        out.push(let_(tmp, sentence))
        out.push(
          call("tc_contract_msg", [h, hc, eq(get("tc_fail"), i32c(0)), get(tmp)]),
        )
      } catch {
        _ =>
          out.push(
            call("tc_contract_msg", [h, hc, i32c(0), call("tc_null", [])]),
          )
      }
      while self.g.refusals.length() > sink {
        self.g.refusals.pop() |> ignore
      }
    }
  }
  out.push(
    call("ctl_log", [
      i32c(@abi.log_warn),
      call("tc_log_ptr", []),
      call("tc_log_len", []),
    ]),
  )
  out
}

///|
/// One transition: precondition, body, postcondition, successor.
///
/// The answer distinguishes three things the host acts on differently.
/// `unhandled` (0) is a name this card does not answer, and the host then
/// falls back to the mutator the declared field implies. `unchanged` (1) is a
/// handler that ran and left the state where it was — which is also what a
/// declined `requires` looks like from outside, and deliberately so: a
/// transition that does not hold is a transition that does not happen.
/// `changed` (2) carries a NEW instance, and new identity is what drives
/// tutuca's change detection.
fn transition(
  g : Gen,
  d : @tscript.Decl,
  invariants : Array[String],
  ss : Array[@tscript.Stmt],
) -> Array[@abi.I] raise Bail {
  let ctx : ECtx = {
    g,
    state: "t",
    params: param_index(d),
    // A handler is handed no row and writes no bindings. `@cur` is the one
    // binding it owns and it is answered before either of these is consulted.
    binds: Map([]),
    bind_local: None,
    args: "args",
    kind: @tscript.kind_word(d.kind),
    name: d.name,
    uses_target: false,
  }
  let unchanged = [
    mem("store32", [i32c(@abi.ret_handle_event), i32c(1)]),
    ret(Some(i32c(@abi.ret_handle_event))),
  ]
  // A rule that does not hold takes the same exit, and says so on the way.
  // `state` is the one the rule was ASKED about — the arriving state for a
  // precondition, the successor for the other two — because the values in the
  // sentence have to be the ones that made the rule false.
  fn declined(
    kind : ContractKind,
    rule : String,
    state : String,
  ) -> Array[@abi.I] {
    let out = ctx.contract_log(d.name, kind, rule, state)
    for i in unchanged {
      out.push(i)
    }
    out
  }
  // A body has no option type to propagate, so an operation with no answer —
  // a division by zero, an index past the end — raises `tc_fail` and this
  // reads it where the interpreter would have seen a `None`. Effects are
  // buffered for the same reason: the interpreter drops the effects of a
  // transition it abandons, and the host cannot un-hear a `send`.
  let out : Array[@abi.I] = [
    set("tc_fail", i32c(0)),
    call("tc_effect_reset", []),
  ]
  // A precondition reads the state as it ARRIVED, which is `s` — the successor
  // does not exist yet, and asking a rule about a state the transition has
  // already half-written would be asking it the wrong question.
  match d.requires_ {
    Some(a) => {
      guard g.callables.get(a.name) is Some(_) else {
        ctx.bail(
          "`requires " + a.name + "` names a pred this card does not compile",
          a.span,
        )
        return []
      }
      out.push(
        if_(
          eq(
            call("tc_truthy", [call(callable_fn(a.name), [get("s"), nullref()])]),
            i32c(0),
          ),
          declined(Precondition, a.name, "s"),
          [],
        ),
      )
    }
    None => ()
  }
  // No clone. The successor STARTS as the arriving state and every write
  // rebinds `t` to a record that shares whatever it did not touch — which is
  // what made `clone_state` and its `memory.copy` disappear.
  out.push(let_("t", get("s")))
  // The body first, so that whether it reaches `@cur` is known before the
  // local is declared: an unused local is a lint, and a lint in generated code
  // is a thing nobody can act on.
  let body_ = ctx.stmts(ss)
  if ctx.uses_target {
    // `&?jv_value`, and it starts null. "No `new` has run yet" is that null
    // rather than a second flag beside it — see `tc_target`.
    out.push(let_zero(target_local, refopt_("jv_value")))
  }
  for i in body_ {
    out.push(i)
  }
  // The body did something with no answer. `Outcome::nothing()`, spelled in
  // the shape the ABI has for it.
  out.push(if_(ne(get("tc_fail"), i32c(0)), unchanged, []))
  // A postcondition and every invariant are asked of the SUCCESSOR, and a rule
  // that does not hold means the transition did not happen. What is still lost
  // against the interpreter is the refusal RECORD — a structured `Refusal` with
  // the state in it, which needs a channel the guest world has no shape for.
  // What is NOT lost any more is the LINE: `control.log` carries the same
  // sentence `core/warn.mbt` prints, `format` clause and all.
  let posts : Array[(ContractKind, String)] = []
  match d.ensures_ {
    Some(a) => {
      guard g.callables.get(a.name) is Some(_) else {
        ctx.bail(
          "`ensures " + a.name + "` names a pred this card does not compile",
          a.span,
        )
        return []
      }
      posts.push((Postcondition, a.name))
    }
    None => ()
  }
  for name in invariants {
    posts.push((Invariant, name))
  }
  for pair in posts {
    let (kind, name) = pair
    out.push(
      if_(
        eq(
          call("tc_truthy", [call(callable_fn(name), [get("t"), nullref()])]),
          i32c(0),
        ),
        declined(kind, name, "t"),
        [],
      ),
    )
  }
  // Whether anything changed is still ASKED rather than assumed from the shape
  // of the body: a handler whose `if` did not fire changed nothing, and telling
  // the host otherwise costs a re-render of everything below it.
  //
  // The question is now a reference comparison. `jv_record_try_set` answers the
  // same record when the value it is given equals the one already there, so
  // `.count = .count` really does leave `t` pointing at `s` — where the cell
  // runtime had to compare every byte of the instance to find that out.
  // Every rule held, so the effects the body buffered are now the host's. The
  // flush is emitted only when this card imports `control`; a card with no
  // effects has nothing to flush and no import to flush it through.
  if g.uses_control {
    out.push(call("tc_flush", []))
  }
  out.push(if_(call("tc_same", [get("t"), get("s")]), unchanged, []))
  out.push(mem("store32", [i32c(@abi.ret_handle_event), i32c(2)]))
  out.push(
    mem("store32", [
      i32c(@abi.ret_handle_event + 4),
      call("resource_new", [call("tc_intern", [get("t")])]),
    ]),
  )
  out.push(ret(Some(i32c(@abi.ret_handle_event))))
  out
}

///|
/// `instance.call-method`: the value-returning declarations, by name.
fn call_method_fn(g : Gen, decls : Array[@tscript.Decl]) -> @abi.Field {
  // Every name this card answers a method call with: the ones it compiled, and
  // the ones its escape block answered. Both reach the same `cm_<name>` —
  // `escape_wrappers` is what makes that true — so the arm is one shape.
  let names : Array[String] = []
  for _key, e in g.escapes {
    if !escape_is_transition(e.kind) {
      names.push(e.name)
    }
  }
  for d in decls {
    guard d.kind is (DCompute | DPred | DInvariant | DEnrich | DEnrichScope) else {
      continue
    }
    guard g.callables.get(d.name) is Some(_) else { continue }
    guard !g.escaped(@tscript.kind_word(d.kind), d.name) else { continue }
    names.push(d.name)
  }
  let arms : Array[@abi.I] = []
  for name in names {
    arms.push(
      if_(
        call("tc_is", [get("name"), i32c(g.pool.string_index(name))]),
        [
          set("tc_fail", i32c(0)),
          let_("v", call(callable_fn(name), [get("s"), get("args")])),
          // A body that could not finish answers nothing, which on this
          // boundary is nil — the same `ANothing` the corpus's value cases
          // name.
          if_(
            ne(get("tc_fail"), i32c(0)),
            [
              mem("fill", [
                i32c(@abi.ret_call_method),
                i32c(0),
                i32c(@abi.cell_size),
              ]),
              ret(Some(i32c(@abi.ret_call_method))),
            ],
            [],
          ),
          call("tc_lower", [get("v"), i32c(@abi.ret_call_method)]),
          ret(Some(i32c(@abi.ret_call_method))),
        ],
        [],
      ),
    )
  }
  arms.push(
    mem("fill", [i32c(@abi.ret_call_method), i32c(0), i32c(@abi.cell_size)]),
  )
  arms.push(i32c(@abi.ret_call_method))
  let body : Array[@abi.I] = [
    let_("s", call("tc_deref", [get("h")])),
    let_("name", call("tc_str_in", [get("np"), get("nl")])),
    let_("args", call("tc_args_lift", [get("ap"), get("al")])),
  ]
  for i in arms {
    body.push(i)
  }
  func(
    "call_method",
    params=[("h", i32_), ("np", i32_), ("nl", i32_), ("ap", i32_), ("al", i32_)],
    results=[i32_],
    export_as=@abi.guest_iface + "#[method]instance.call-method",
    body~,
  )
}
