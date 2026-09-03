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
  let callable = Map::new()
  for d in c.decls {
    callable[d.name] = d.kind
  }
  for d in c.decls {
    let ctx = {
      comp: c,
      kind: d.kind,
      params: params_of(d),
      callable,
      temps: 0,
      binds: binds_var(d),
    }
    let body = Src::new()
    body.depth = 1
    let head = decl_head(c, d)
    match (try? emit_decl(ctx, body, d)) {
      Ok(_) => {
        src.line(head)
        src.buf.write_string(body.text())
        src.line("}")
        src.blank()
      }
      Err(Refused(why)) =>
        c.refusals.push({
          comp: c.name,
          kind: @tscript.kind_word(d.kind),
          name: d.name,
          reason: why,
          line: 0,
          span: d.span,
        })
    }
  }
  emit_call(src, c)
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
  let out = Map::new()
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
      "fn \{c.id}_receive_\{n}(f: &tg_vals, args: &tg_vals) -> &?tg_vals {"
    DAnswer =>
      "fn \{c.id}_answer_\{n}(f: &tg_vals, args: &tg_vals) -> &?tg_vals {"
    DSet => "fn \{c.id}_set_\{n}(f: &tg_vals, args: &tg_vals) -> &?tg_vals {"
    DCompute =>
      "fn \{c.id}_compute_\{n}(f: &tg_vals, args: &tg_vals) -> &?tg_val {"
    DGet => "fn \{c.id}_get_\{n}(f: &tg_vals, args: &tg_vals) -> &?tg_val {"
    DPred => "fn \{c.id}_pred_\{n}(f: &tg_vals, args: &tg_vals) -> &?tg_val {"
    DInvariant =>
      "fn \{c.id}_invariant_\{n}(f: &tg_vals, args: &tg_vals) -> &?tg_val {"
    DEnrich =>
      "fn \{c.id}_enrich_\{n}(f: &tg_vals, args: &tg_vals) -> &?tg_val {"
    DBindWith =>
      "fn \{c.id}_bindwith_\{n}(f: &tg_vals, args: &tg_vals) -> &?tg_val {"
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
      emit_attach(ctx, src, d.requires_, "requires")
      emit_stmts(ctx, src, stmts)
      emit_attach(ctx, src, d.ensures_, "ensures")
      src.line("f")
    }
    Value(e) => {
      guard not(transition) else {
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
  let t = ctx.temp()
  src.line(
    "let \{t} = \{ctx.comp.id}_\{callable_suffix(kind)}_\{mangle(a.name)}(f, args);",
  )
  src.line("if \{t} == null { return null; }")
  src.line("if tg_truthy(\{t}) == 0 { return null; }")
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
  src.open("if op == \{op_code(@abi.OpImplements)} {")
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
  src.open("if op == \{op_code(@abi.OpWithField)} {")
  src.line("let i = \{c.id}_slot(name);")
  src.line("if i <s 0 { return null; }")
  src.line("let f = \{c.id}_copy(st);")
  src.line("f[i] = v;")
  src.line("return tg_comp(\{c.id}_inst(self.desc, f));")
  src.close("}")
  src.blank()

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
        src.line("let next = \{c.id}_\{prefix}_\{mangle(d.name)}(f, a);")
      } else {
        src.line("let next = \{c.id}_\{prefix}_\{mangle(d.name)}(f, args);")
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
      let call = "\{c.id}_\{prefix}_\{mangle(d.name)}(st.fields, args)"
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
