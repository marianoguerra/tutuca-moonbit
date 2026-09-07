///|
fn main raise {
  let args = @env.args()
  let outdir = if args.length() >= 2 { args[1] } else { "." }
  let rows : Array[Json] = []
  let mut compiled = 0
  let mut rejected = 0
  for i, c in @conformance.cases() {
    let card = card_of(c.schema, c.script)
    let row : Json = match
      (Ok(@emit.compile(card, name="case\{i}")) catch { e => Err(e) }) {
      Ok(out) => {
        @fs.write_bytes_to_file("\{outdir}/case\{i}.wasm", out.wasm)
        @fs.write_string_to_file("\{outdir}/case\{i}.wap", out.wap)
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
          // Under the name the CARD carries: a `.tutu` spells a member in
          // snake_case, so `resetTo` is declared `reset_to` and the module
          // answers that.
          "handler": Json::string(@names.snake_of(c.handler)),
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
    let card = card_of(c.schema, c.script, row=row_of(c.role, c.callable))
    let row : Json = match
      (Ok(@emit.compile(card, name="value\{i}")) catch { e => Err(e) }) {
      Ok(out) => {
        @fs.write_bytes_to_file("\{outdir}/value\{i}.wasm", out.wasm)
        {
          "name": Json::string(c.name),
          "status": Json::string("compiled"),
          "module": Json::string("value\{i}.wasm"),
          "component": Json::string(out.component),
          "role": Json::string(role_word(c.role)),
          // Under the name the CARD carries. A `.tutu` spells a member in
          // snake_case, so `containsText` is declared `contains_text` and the
          // compiled module answers that — the row has to name what the
          // module has, not what the corpus wrote.
          "callable": Json::string(@names.snake_of(c.callable)),
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
///
/// The corpus SPECIFIES the block language — that is what a `@statedef.StateDef`
/// and a `@tscript.Decl` are parses of — and a card is a `.tutu`, so the row is
/// read once and printed as shrubbery. `cmd/conformance` does the same thing
/// for the same reason.
fn card_of(
  schema : String,
  script : String,
  row? : String = "",
) -> String raise {
  let defs = @statedef.parse_state(schema)
  guard defs is [def, ..] else {
    abort("tgc-corpus: a corpus schema declares no component")
  }
  let decls = @tscript.parse_script(script).map(d => {
    if row != "" && d.name == row {
      // A ROW MEMBER names its row. The old notation gave a `when` filter and an
      // in-loop enricher none — they read `@value` out of the air — and the new
      // one has no way to spell that, so the projection declares the parameters
      // the renderer binds. `tutufile/tologic` reads them back as the bindings
      // the body's `value` and `key` already are.
      {
        ..d,
        params: [
          ({ name: "value", span: d.name_span, } : @tscript.Param),
          { name: "key", span: d.name_span, },
        ],
      }
    } else {
      d
    }
  })
  let spec = StringBuilder()
  for t in def.types {
    @totutu.print_user_ty(t, spec) catch {
      @totutu.NoSpelling(what~, help~) =>
        abort(
          "tgc-corpus: a declared type does not spell: " + what + " — " + help,
        )
    }
    spec.write_string("\n")
  }
  @totutu.print_spec(def, root=true, names=Map([]), spec) catch {
    @totutu.NoSpelling(what~, help~) =>
      abort("tgc-corpus: a schema does not spell: " + what + " — " + help)
  }
  let logic = StringBuilder()
  @totutu.print_logic(def.component, decls, Some(def), logic) catch {
    @totutu.NoSpelling(what~, help~) =>
      abort("tgc-corpus: a case does not spell: " + what + " — " + help)
  }
  // The view NAMES a row member, because that is the only place a `pred` says
  // which of its two shapes it has — a slot calls one and a render-time option
  // hands the other its row.
  let view = if row == "" {
    "    b()\n"
  } else {
    "    ul():\n" +
    "      each(value, key in it.items, ~when: \{@names.snake_of(row)}):\n" +
    "        li()\n"
  }
  "spec:\n" +
  spec.to_string() +
  "\nlogic:\n" +
  logic.to_string() +
  "\nview:\n  " +
  def.component +
  ":\n" +
  view
}

///|
/// The member a render-time option names, when this case's role is one.
fn row_of(role : @conformance.ValueRole, callable : String) -> String {
  match role {
    VWhen => callable
    _ => ""
  }
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
