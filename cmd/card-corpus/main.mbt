// Dump the conformance corpus as JSON, for the wasm backend's adapter.
//
// The corpus is MoonBit data and the wasm backend can only be driven from
// node — a compiled card is a module, and running one means `WebAssembly`
// and `dyncomp/host/wasm/abi.mjs`. So the table crosses as JSON, and
// `test/conformance.test.mjs` is one of the two adapters over it; the MoonBit
// emitter's is `tscript/conformance/mbt/`.
//
//   moon run --target native cmd/card-corpus -- <out.json>
//
// A PROJECTION and nothing else. This used to run the interpreter, because the
// corpus stored an effect as `send flash RStr("ada")` and the wasm adapter sees
// a name and a list of values — so the values had to be recovered from
// somewhere, and the only place that had them was a second implementation.
// That made the compiled backend's conformance harness depend on the
// interpreter existing, which is a strange thing for a corpus to arrange.
//
// The corpus stores the values now (`CaseEffect`), so there is nothing to
// recover and nothing to run: every field below is copied out of the table.
// Both halves of it — the transitions and the value bodies — cross the same way.

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
fn role_name(r : @conformance.ValueRole) -> String {
  match r {
    VMethod => "method"
    VWhen => "when"
    VEnrich => "enrich"
    VEnrichScope => "enrichScope"
  }
}

///|
fn effect_json(e : @conformance.CaseEffect) -> Json {
  Json::object({
    "kind": Json::string(e.kind),
    "name": Json::string(e.name),
    "args": Json::array(e.args.map(a => a.to_json())),
    // Empty for every v1 effect; `intent` and `forward` are the two that
    // carry one, and the card adapter reads it in the plan's task 11.
    "route": Json::string(e.route),
  })
}

///|
/// An answer as `{ kind, … }`. A tagged object rather than a bare value,
/// because `ANothing` and `AValue(Null)` are DIFFERENT answers — a body that
/// could not finish against one that answered null — and JSON has one spelling
/// for both.
fn answer_json(a : @conformance.Answer) -> Json {
  match a {
    AValue(v) =>
      Json::object({ "kind": Json::string("value"), "value": v.to_json() })
    ABool(b) =>
      Json::object({ "kind": Json::string("bool"), "value": Json::boolean(b) })
    ABinds(m) =>
      Json::object({ "kind": Json::string("binds"), "value": state_json(m) })
    ANothing => Json::object({ "kind": Json::string("nothing") })
  }
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
    println("usage: card-corpus <out.json>")
    panic()
  }
  let out = args[1]
  let problems : Array[String] = []

  // The card a case becomes needs a template named after the state, or the
  // script block is about a component the file does not declare. That name is
  // the one thing here the corpus does not state outright, so the schema is
  // parsed for it — and a schema that does not parse is a broken corpus rather
  // than a failing backend, which is why it is reported here.
  fn component_of(name : String, schema : String) -> String? {
    let defs = @statedef.parse_state(schema) catch {
      e => {
        problems.push(name + ": the schema does not parse — " + e.message())
        return None
      }
    }
    match defs.get(0) {
      Some(d) => Some(d.source_name)
      None => {
        problems.push(name + ": the schema declares no state")
        None
      }
    }
  }

  let rows : Array[Json] = []
  for c in @conformance.cases() {
    guard component_of(c.name, c.schema) is Some(comp) else { continue }
    rows.push(
      Json::object({
        "name": Json::string(c.name),
        "schema": Json::string(c.schema),
        "script": Json::string(c.script),
        "component": Json::string(comp),
        "bucket": Json::string(bucket_name(c.bucket)),
        "handler": Json::string(c.handler),
        "args": Json::array(c.args.map(a => a.to_json())),
        "before": state_json(c.before),
        "after": match c.after {
          Some(m) => state_json(m)
          None => Json::null()
        },
        "effects": Json::array(c.effects.map(effect_json)),
      }),
    )
  }

  // The OTHER table. `cases()` asks what the state became; these ask what the
  // block SAID — a `compute`, a `@when` filter, an enricher — and the wasm
  // backend was never held to any of it, which is exactly where its
  // `enrich` / `enrichScope` gap lived.
  let value_rows : Array[Json] = []
  for c in @conformance.value_cases() {
    guard component_of(c.name, c.schema) is Some(comp) else { continue }
    value_rows.push(
      Json::object({
        "name": Json::string(c.name),
        "schema": Json::string(c.schema),
        "script": Json::string(c.script),
        "component": Json::string(comp),
        "state": state_json(c.state),
        "role": Json::string(role_name(c.role)),
        "callable": Json::string(c.callable),
        "args": Json::array(c.args.map(a => a.to_json())),
        "key": c.key.to_json(),
        "value": c.value.to_json(),
        "answer": answer_json(c.answer),
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
    Json::object({
      "cases": Json::array(rows),
      "valueCases": Json::array(value_rows),
    }).stringify(),
  )
  println(
    "wrote " +
    rows.length().to_string() +
    " cases and " +
    value_rows.length().to_string() +
    " value cases to " +
    out,
  )
}
