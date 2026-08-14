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
/// One wasm function per `compute` / `pred` / `invariant` that compiles.
///
/// Compiled to a fixpoint: a callable that refers to one which was itself
/// refused has to be refused too, and which those are is not known until the
/// first pass has run. Two rounds settle every card that is not a cycle, and
/// the bound is what stops one that is.
fn callable_fields(g : Gen, decls : Array[@tscript.Decl]) -> Array[@abi.Field] {
  let mut out : Array[@abi.Field] = []
  for _round in 0..<4 {
    let fresh_refusals : Array[Refusal] = []
    let fields : Array[@abi.Field] = []
    let survived : Map[String, @tscript.Decl] = Map([])
    let before = g.callables.length()
    for d in decls {
      guard d.kind is (DCompute | DPred | DInvariant) else { continue }
      guard g.callables.get(d.name) is Some(_) else { continue }
      guard d.body is Value(e) else { continue }
      let ctx : ECtx = {
        g,
        state: "s",
        params: param_index(d),
        args: "args",
        kind: @tscript.kind_word(d.kind),
        name: d.name,
        uses_target: false,
      }
      g.temp = 0
      let sink = g.refusals.length()
      try {
        let body_ = ctx.expr(e)
        survived[d.name] = d
        fields.push(
          func(
            callable_fn(d.name),
            params=[("s", rec_), ("args", args_)],
            results=[jv_],
            body=[body_],
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
/// A declaration's parameters, by position.
fn param_index(d : @tscript.Decl) -> Map[String, Int] {
  let m : Map[String, Int] = Map([])
  for i, p in d.params {
    m[p.name] = i
  }
  m
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
      (DResponse, @abi.bucket_response),
      (DBubble, @abi.bucket_bubble),
    ] {
    let (kind, bucket) = pair
    let inner : Array[@abi.I] = []
    for d in decls {
      guard d.kind == kind else { continue }
      guard d.body is Stmts(ss) else { continue }
      g.temp = 0
      let sink = g.refusals.length()
      try {
        let block = transition(g, d, invariants, ss)
        inner.push(
          if_(
            call("tc_is", [get("name"), i32c(g.pool.string_index(d.name))]),
            block,
            [],
          ),
        )
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
    args: "args",
    kind: @tscript.kind_word(d.kind),
    name: d.name,
    uses_target: false,
  }
  let unchanged = [
    mem("store32", [i32c(@abi.ret_handle_event), i32c(1)]),
    ret(Some(i32c(@abi.ret_handle_event))),
  ]
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
          unchanged,
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
  // that does not hold means the transition did not happen. What is lost
  // against the interpreter is the refusal RECORD — a `format` sentence naming
  // what went wrong — which needs a channel back to the host that the guest
  // world has no shape for yet.
  let posts : Array[String] = []
  match d.ensures_ {
    Some(a) => {
      guard g.callables.get(a.name) is Some(_) else {
        ctx.bail(
          "`ensures " + a.name + "` names a pred this card does not compile",
          a.span,
        )
        return []
      }
      posts.push(a.name)
    }
    None => ()
  }
  for name in invariants {
    posts.push(name)
  }
  for name in posts {
    out.push(
      if_(
        eq(
          call("tc_truthy", [call(callable_fn(name), [get("t"), nullref()])]),
          i32c(0),
        ),
        unchanged,
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
  let arms : Array[@abi.I] = []
  for d in decls {
    guard d.kind is (DCompute | DPred | DInvariant) else { continue }
    guard g.callables.get(d.name) is Some(_) else { continue }
    arms.push(
      if_(
        call("tc_is", [get("name"), i32c(g.pool.string_index(d.name))]),
        [
          set("tc_fail", i32c(0)),
          let_("v", call(callable_fn(d.name), [get("s"), get("args")])),
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
