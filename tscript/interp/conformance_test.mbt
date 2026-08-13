// The interpreter, run against the corpus.
//
// The corpus is the language's semantics as data; this is one of the three
// backends being held to it. When the MoonBit emitter lands it writes a second
// adapter over the same table, and a case the two disagree about is a bug in
// one of them rather than a difference of opinion.

///|
/// The bucket a case dispatches, as the declaration kind that answers it.
fn kind_for(b : @conformance.Bucket) -> @tscript.DeclKind {
  match b {
    BInput => DOn
    BReceive => DReceive
    BBubble => DBubble
    BResponse => DResponse
  }
}

///|
/// One effect in the corpus's printed form.
fn printed(e : @interp.Effect) -> String {
  match e {
    ESend(name~, args~) => @conformance.show_effect("send " + name, args)
    EBubble(name~, args~) => @conformance.show_effect("bubble " + name, args)
    ERequest(name~, args~) => @conformance.show_effect("request " + name, args)
    ESendAt(name~, args~, ..) =>
      @conformance.show_effect("sendAt " + name, args)
    EStop => "stop"
  }
}

///|
/// A state map in a stable order, for a failure message.
fn show_state(s : Map[String, @tutuca.Value]?) -> String {
  match s {
    None => "(no change)"
    Some(m) => {
      let keys : Array[String] = []
      for k, _ in m {
        keys.push(k)
      }
      keys.sort()
      "{" +
      keys
      .map(k => k + ": " + m.get(k).unwrap().to_repr().to_string())
      .join(", ") +
      "}"
    }
  }
}

///|
test "the interpreter agrees with the corpus" {
  let failures : Array[String] = []
  for c in @conformance.cases() {
    let decls = @tscript.parse_script(c.script) catch {
      e => {
        failures.push("\{c.name}: the script does not parse — \{e.message()}")
        continue
      }
    }
    // The declaration that answers this dispatch, found the way a runtime
    // finds it: by bucket AND name, never by name alone.
    let want_kind = kind_for(c.bucket)
    let callables : Map[String, @tscript.Decl] = Map([])
    let mut found : @tscript.Decl? = None
    for d in decls {
      if d.kind is (DPred | DCompute) {
        callables[d.name] = d
      }
      if d.kind == want_kind && d.name == c.handler {
        found = Some(d)
      }
    }
    // The declared schema, which is what makes `.count = 2.7` land as 2 in an
    // `s32` field — the same thing the generated codec's decode does.
    let defs = @statedef.parse_state(c.schema) catch {
      e => {
        failures.push("\{c.name}: the schema does not parse — \{e.message()}")
        continue
      }
    }
    let schema = @info.schema_info(defs[0])
    let env = @interp.Env::of_state(c.before, callables~, schema~)
    let out = match found {
      Some(d) => @interp.dispatch(d, c.args, env)
      // No arm answers it, which for a corpus case is the same outcome as a
      // body that could not finish: no successor.
      None => @interp.Outcome::nothing()
    }
    if out.state != c.after {
      failures.push(
        "\{c.name}: state is \{show_state(out.state)}, want \{show_state(c.after)}",
      )
    }
    let got = out.effects.map(printed)
    if got != c.effects {
      failures.push(
        "\{c.name}: effects are [" +
        got.join(", ") +
        "], want [" +
        c.effects.join(", ") +
        "]",
      )
    }
  }
  assert_eq(failures, [])
}

///|
test "the corpus is not empty and every case is distinct" {
  // A corpus that silently lost its cases would pass forever.
  let cs = @conformance.cases()
  assert_true(cs.length() >= 30)
  let seen : Map[String, Unit] = Map([])
  for c in cs {
    assert_false(seen.contains(c.name))
    seen[c.name] = ()
  }
}

///|
/// The bindings a role is handed, as the renderer hands them.
fn binds_for(c : @conformance.ValueCase) -> Map[String, @tutuca.Value] {
  match c.role {
    VMethod | VEnrichScope => Map([])
    VWhen | VEnrich => { "key": c.key, "value": c.value }
  }
}

///|
test "the interpreter agrees with the corpus about value bodies" {
  let failures : Array[String] = []
  for c in @conformance.value_cases() {
    let decls = @tscript.parse_script(c.script) catch {
      e => {
        failures.push("\{c.name}: the script does not parse — \{e.message()}")
        continue
      }
    }
    let callables : Map[String, @tscript.Decl] = Map([])
    let mut found : @tscript.Decl? = None
    for d in decls {
      if d.kind is (DPred | DCompute) {
        callables[d.name] = d
      }
      if d.name == c.callable {
        found = Some(d)
      }
    }
    guard found is Some(d) else {
      failures.push("\{c.name}: nothing declares `\{c.callable}`")
      continue
    }
    let defs = @statedef.parse_state(c.schema) catch {
      e => {
        failures.push("\{c.name}: the schema does not parse — \{e.message()}")
        continue
      }
    }
    let schema = @info.schema_info(defs[0])
    let params : Map[String, @tutuca.Value] = Map([])
    for i, prm in d.params {
      params[prm.name] = c.args.get(i).unwrap_or(Null)
    }
    let env : @interp.Env = {
      ..@interp.Env::of_state(c.state, callables~, schema~),
      params,
      binds: binds_for(c),
    }
    let got : @conformance.Answer = match c.role {
      VMethod =>
        match @interp.call(d, env) {
          Some(v) => AValue(v)
          // What a SLOT reads when a body could not finish, which is what
          // `CardObj::callable_fn` hands back for exactly this: nothing at a
          // slot is Null.
          None => AValue(Null)
        }
      VWhen =>
        match @interp.call(d, env) {
          Some(v) => ABool(v.is_truthy())
          // A body that could not finish is a row that does not survive: the
          // filter answers no rather than answering nothing.
          None => ABool(false)
        }
      VEnrich | VEnrichScope =>
        match d.body {
          Stmts(body) => {
            let out = @interp.run(body, env)
            match out.state {
              // Only what the body WROTE: the loop's own key and value are the
              // renderer's, not the enricher's answer.
              Some(_) => {
                let wrote : Map[String, @tutuca.Value] = Map([])
                for k, v in out.binds {
                  if !(k == "key" || k == "value" || k == "iter") {
                    wrote[k] = v
                  }
                }
                ABinds(wrote)
              }
              None => ANothing
            }
          }
          Value(_) => ANothing
        }
    }
    if got != c.answer {
      failures.push(
        "\{c.name}: expected \{c.answer} but the interpreter answered \{got}",
      )
    }
  }
  assert_eq(failures, [])
}
