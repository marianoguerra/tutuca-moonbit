// Dump the conformance corpus as JSON, for the wasm backend's adapter.
//
// The corpus is MoonBit data and the wasm backend can only be driven from
// node — a compiled card is a module, and running one means `WebAssembly`
// and `dyncomp/host/wasm/abi.mjs`. So the table crosses as JSON, and
// `test/conformance.test.mjs` is the third adapter over it (the interpreter's
// is `tscript/interp/conformance_test.mbt`).
//
//   moon run --target native cmd/corpus -- <out.json>
//
// EFFECTS ARE EMITTED STRUCTURALLY, which the corpus does not store: it keeps
// them as `show_effect`'s printed form on purpose, so that no backend's
// spelling of an effect becomes the language's. Replicating that printing in
// JavaScript would mean replicating MoonBit's derived `Debug` — including the
// iteration order of a `Map` — which is exactly the kind of incidental detail
// the printed form exists to avoid pinning.
//
// So this runs the INTERPRETER to get the effects as values, and then checks
// that printing them back gives the corpus string. If that check ever fails,
// the JSON is wrong and this says so rather than emitting it.

///|
fn bucket_name(b : @conformance.Bucket) -> String {
  match b {
    BInput => "input"
    BReceive => "receive"
    BBubble => "bubble"
    BResponse => "response"
  }
}

///|
fn kind_for(b : @conformance.Bucket) -> @tscript.DeclKind {
  match b {
    BInput => DOn
    BReceive => DReceive
    BBubble => DBubble
    BResponse => DResponse
  }
}

///|
/// One effect in the corpus's printed form — the same function the
/// interpreter's adapter uses, and the reason this dump can be trusted.
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
/// The same effect as `{ kind, name, args }`, which is what a JS adapter can
/// compare against what the host actually saw.
fn structural(e : @interp.Effect) -> Json {
  let (kind, name, args) = match e {
    ESend(name~, args~) => ("send", name, args)
    EBubble(name~, args~) => ("bubble", name, args)
    ERequest(name~, args~) => ("request", name, args)
    ESendAt(name~, args~, ..) => ("sendAt", name, args)
    EStop => ("stop", "", [])
  }
  Json::object({
    "kind": Json::string(kind),
    "name": Json::string(name),
    "args": Json::array(args.map(a => a.to_json())),
  })
}

///|
fn state_json(m : Map[String, @tutuca.Value]) -> Json {
  let out : Map[String, Json] = Map([])
  for k, v in m {
    out[k] = v.to_json()
  }
  Json::object(out)
}

///|
fn main raise {
  let args = @env.args()
  guard args.length() >= 2 else {
    println("usage: corpus <out.json>")
    panic()
  }
  let out = args[1]

  // A contract that does not hold REPORTS, and the corpus exercises several.
  // Quiet here for the same reason the interpreter's adapter quiets it: what a
  // case asserts is the successor and the effects.
  @tutuca.warn_hook.val = _ => ()
  let rows : Array[Json] = []
  let problems : Array[String] = []
  for c in @conformance.cases() {
    let decls = @tscript.parse_script(c.script) catch {
      e => {
        problems.push(c.name + ": the script does not parse — " + e.message())
        continue
      }
    }
    let defs = @statedef.parse_state(c.schema) catch {
      e => {
        problems.push(c.name + ": the schema does not parse — " + e.message())
        continue
      }
    }
    let want_kind = kind_for(c.bucket)
    let callables : Map[String, @tscript.Decl] = Map([])
    let mut found : @tscript.Decl? = None
    for d in decls {
      if d.kind is (DPred | DCompute | DInvariant) {
        callables[d.name] = d
      }
      if d.kind == want_kind && d.name == c.handler {
        found = Some(d)
      }
    }
    let schema = @info.schema_info(defs[0])
    let env = @interp.Env::of_state(c.before, callables~, schema~, zero=t => {
      @info.zero_of_ref(defs[0], t)
    })
    let outcome = match found {
      Some(d) => @interp.dispatch(d, c.args, env)
      None => @interp.Outcome::nothing()
    }
    // The check that makes the structural effects trustworthy.
    let got = outcome.effects.map(printed)
    if got != c.effects {
      problems.push(
        c.name +
        ": the interpreter's effects [" +
        got.join(", ") +
        "] are not the corpus's [" +
        c.effects.join(", ") +
        "] — the corpus and the interpreter disagree, so this dump would be a lie",
      )
      continue
    }
    if outcome.state != c.after {
      problems.push(
        c.name +
        ": the interpreter's successor is not the corpus's — same problem",
      )
      continue
    }
    rows.push(
      Json::object({
        "name": Json::string(c.name),
        "schema": Json::string(c.schema),
        "script": Json::string(c.script),
        "component": Json::string(defs[0].source_name),
        "bucket": Json::string(bucket_name(c.bucket)),
        "handler": Json::string(c.handler),
        "args": Json::array(c.args.map(a => a.to_json())),
        "before": state_json(c.before),
        "after": match c.after {
          Some(m) => state_json(m)
          None => Json::null()
        },
        "effects": Json::array(outcome.effects.map(structural)),
      }),
    )
  }
  guard problems.is_empty() else {
    for p in problems {
      println("PROBLEM " + p)
    }
    panic()
  }
  @fs.write_string_to_file(
    out,
    Json::object({ "cases": Json::array(rows) }).stringify(),
  )
  println("wrote " + rows.length().to_string() + " cases to " + out)
}
