///|
fn main raise {
  let args = @env.args()
  let outdir = if args.length() >= 2 { args[1] } else { "." }
  let rows : Array[Json] = []
  let mut compiled = 0
  let mut rejected = 0
  for i, c in @conformance.cases() {
    let card = card_of(c.schema, c.script)
    let row : Json = match (try? @emit.compile(card, name="case\{i}")) {
      Ok(out) => {
        @fs.write_bytes_to_file("\{outdir}/case\{i}.wasm", out.wasm)
        @fs.write_string_to_file("\{outdir}/case\{i}.wax", out.wax)
        compiled = compiled + 1
        {
          "name": Json::string(c.name),
          "status": Json::string("compiled"),
          "module": Json::string("case\{i}.wasm"),
          "component": Json::string(out.component),
          "bucket": Json::string(
            if c.bucket is BReceive {
              "receive"
            } else {
              "intent"
            },
          ),
          "handler": Json::string(c.handler),
          "args": Json::array(c.args.map(json_of)),
          "before": map_json(c.before),
          "after": match c.after {
            Some(m) => map_json(m)
            None => Json::null()
          },
          "effects": Json::array(
            c.effects.map(e => {
              "kind": Json::string(e.kind),
              "name": Json::string(e.name),
              "args": Json::array(e.args.map(json_of)),
              "route": Json::string(e.route),
            }),
          ),
          "refusals": Json::array(
            out.refusals.map(r => {
              Json::string("\{r.kind} \{r.name}: \{r.reason}")
            }),
          ),
        }
      }
      // A rejected case is one the corpus states as invalid — a name that
      // resolves to nothing, arithmetic on a String. The harness asserts the
      // count rather than the reason, because the reason is the checker's.
      Err(e) => {
        rejected = rejected + 1
        {
          "name": Json::string(c.name),
          "status": Json::string("rejected"),
          "why": Json::string(e.message()),
        }
      }
    }
    rows.push(row)
  }
  @fs.write_string_to_file(
    "\{outdir}/cases.json",
    Json::array(rows).stringify(indent=2),
  )

  // The OTHER table: seventeen-odd rows about what a block SAID rather than
  // what the state became. The backend this replaced had its worst gap here — `enrich`
  // and `bindWith` were absent from its generator entirely, which no
  // transition case was asking about.
  let vrows : Array[Json] = []
  for i, c in @conformance.value_cases() {
    let card = card_of(c.schema, c.script)
    let row : Json = match (try? @emit.compile(card, name="value\{i}")) {
      Ok(out) => {
        @fs.write_bytes_to_file("\{outdir}/value\{i}.wasm", out.wasm)
        {
          "name": Json::string(c.name),
          "status": Json::string("compiled"),
          "module": Json::string("value\{i}.wasm"),
          "component": Json::string(out.component),
          "role": Json::string(role_word(c.role)),
          "callable": Json::string(c.callable),
          "args": Json::array(c.args.map(json_of)),
          "key": json_of(c.key),
          "value": json_of(c.value),
          "state": map_json(c.state),
          "answer": answer_json(c.answer),
          "refusals": Json::array(
            out.refusals.map(r => {
              Json::string("\{r.kind} \{r.name}: \{r.reason}")
            }),
          ),
        }
      }
      Err(e) =>
        {
          "name": Json::string(c.name),
          "status": Json::string("rejected"),
          "why": Json::string(e.message()),
        }
    }
    vrows.push(row)
  }
  @fs.write_string_to_file(
    "\{outdir}/value_cases.json",
    Json::array(vrows).stringify(indent=2),
  )
  println("\{compiled} compiled, \{rejected} rejected, \{rows.length()} rows")
  println("\{vrows.length()} value rows")
}

///|
fn role_word(r : @conformance.ValueRole) -> String {
  match r {
    VMethod => "method"
    VWhen => "when"
    VEnrich => "enrich"
    VEnrichScope => "bindWith"
  }
}

///|
/// What a value case expects. `ANothing` is a real answer and the one a backend
/// is most tempted to replace with something plausible.
fn answer_json(a : @conformance.Answer) -> Json {
  match a {
    AValue(v) => { "kind": Json::string("value"), "v": json_of(v) }
    ABool(b) => { "kind": Json::string("bool"), "v": Json::boolean(b) }
    ABinds(m) => { "kind": Json::string("binds"), "v": map_json(m) }
    ANothing => { "kind": Json::string("nothing") }
  }
}

///|
/// A corpus row as the smallest card that carries it.
fn card_of(schema : String, script : String) -> String {
  let comp = component_of(schema)
  "<script type=\"tutuca/spec\">\n" +
  schema +
  "\n</script>\n<script type=\"tutuca/script\">\n" +
  script +
  "\n</script>\n<template id=\"" +
  comp +
  ":main\" data-root><b></b></template>\n"
}

///|
/// The component a schema declares — the word after the first `state`.
fn component_of(schema : String) -> String {
  for line in schema.split("\n") {
    let text = line.trim(chars=" \t").to_string()
    if text.has_prefix("state ") {
      let rest = text[6:].trim(chars=" \t").to_string()
      let out = StringBuilder()
      for ch in rest {
        if (ch >= 'a' && ch <= 'z') || (ch >= 'A' && ch <= 'Z') || ch == '_' {
          out.write_char(ch)
        } else {
          break
        }
      }
      return out.to_string()
    }
  }
  "C"
}

///|
/// A `core.Value` as the format's `$`-tagged JSON.
///
/// One line, since `core.Value` and the `tgc/1` value are the same value: the
/// bridge this used to need was a mirror of one onto the other, and there is no
/// longer anything to mirror.
fn json_of(v : @tutuca.Value) -> Json {
  v.to_json()
}

///|
fn map_json(m : Map[String, @tutuca.Value]) -> Json {
  let out : Map[String, Json] = Map([])
  for k, v in m {
    out[k] = json_of(v)
  }
  Json::object(out)
}
