// The init block's type rules.
//
// `parse_init` is the typed-literal checker over `StateTy`: JSON in, MoonBit
// source out, with the schema deciding what fits. It had no test anywhere, and
// it is the closest existing analogue to the checker a real expression
// language needs — the same job, one language smaller. So what is pinned here
// is the CONTRACT rather than the spelling: which JSON shape each declared
// type accepts, what it emits, and which mismatch is REPORTED rather than
// quietly coerced.
//
// The rejections carry most of the weight. A fixture that writes 2.5 into an
// `Int` has said something it did not mean, and a checker that truncates it is
// worse than one with no opinion — the whole reason the block is checked at
// generation time is that nothing downstream will ever look again.

///|
/// Parse a schema expected to hold exactly one component.
fn def_of(src : String) -> @statedef.StateDef raise {
  let defs = @statedef.parse_state(src)
  assert_eq(defs.length(), 1)
  defs[0]
}

///|
/// A block written as bare field maps, in the envelope a fixture actually
/// takes.
///
/// Every test below this line is about the VALUE — which JSON shape each
/// declared type accepts and what it emits — so they are written as the field
/// map and wrapped here. The envelope has tests of its own at the bottom,
/// which call `parse_init` directly.
fn wrap(init : String) -> String {
  // Left alone when it is not parseable JSON: the tests that hand this
  // nonsense are testing that `parse_init` says so.
  let j = @json.parse(init) catch { _ => return init }
  guard j is Object(states) else { return init }
  let out : Map[String, Json] = Map([])
  for name, fields in states {
    out[name] = Json::object({ "value": fields })
  }
  Json::object(out).stringify()
}

///|
/// The fixtures an init block yields against a schema.
fn inits(schema : String, init : String) -> Array[@statedef.InitState] raise {
  @statedef.parse_init(wrap(init), def_of(schema))
}

///|
/// The emitted source for one field of one fixture — the common shape of the
/// type-table rows below. `<unset>` when the fixture names no such field,
/// which is a distinct answer from any literal it could emit.
fn lit(schema : String, init : String, binding : String) -> String raise {
  let out = inits(schema, init)
  assert_eq(out.length(), 1)
  for pair in out[0].fields {
    if pair.0 == binding {
      return pair.1
    }
  }
  "<unset>"
}

///|
/// The message an init block raises, or "" when it does not raise.
fn init_err(schema : String, init : String) -> String raise {
  let d = def_of(schema)
  try {
    @statedef.parse_init(wrap(init), d) |> ignore
    ""
  } catch {
    e => e.message()
  }
}

///|
/// The message an init block raises, WITHOUT the envelope helper — for the
/// tests that are about the block's own shape.
fn raw_err(schema : String, init : String) -> String raise {
  let d = def_of(schema)
  try {
    @statedef.parse_init(init, d) |> ignore
    ""
  } catch {
    e => e.message()
  }
}

///|
/// One field per scalar shape the lattice has a literal for.
fn scalars() -> String {
  (
    #|state Counter {
    #|  label   : String
    #|  count   : Int
    #|  ratio   : Double
    #|  isOpen  : Bool
    #|  note    : String?
    #|  history : Array[Int]
    #|}
  )
}

///|
/// The map-backed shapes, plus the dynamic escape hatch.
fn collections() -> String {
  (
    #|enum Visibility { Done, Active }
    #|state Board {
    #|  tags   : Set[String]
    #|  vis    : Set[Visibility]
    #|  counts : Map[String, String]
    #|  blob   : Any
    #|}
  )
}

///|
/// The two named-type shapes a fixture can name a case or a sub-field of.
fn named() -> String {
  (
    #|enum Priority { Low, HighIsh }
    #|struct Label { text: String, done: Bool }
    #|state Post { pri: Priority, tag: Label }
  )
}

///|
test "a fixture names fields in schema order" {
  // Deliberately out of JSON order. A field has one spelling: the one the
  // state block declares and the view reads.
  let out = inits(
    scalars(),
    "{ \"fresh\": { \"isOpen\": true, \"count\": 3, \"label\": \"Counter\" } }",
  )
  assert_eq(out.length(), 1)
  assert_eq(out[0].name, "fresh")
  assert_eq(out[0].ident, "fresh")
  // Schema order (label, count, isOpen) — not the JSON's.
  assert_eq(out[0].fields, [
    ("label", "\"Counter\""),
    ("count", "3"),
    ("isOpen", "true"),
  ])
}

///|
test "a fixture that sets nothing is legal and names nothing" {
  let out = inits(scalars(), "{ \"fresh\": {} }")
  assert_eq(out.length(), 1)
  assert_eq(out[0].fields, [])
}

///|
test "fixture names are byte-ordered, not length-ordered" {
  // `str_cmp`, not `a < b`: MoonBit's Compare for String is length-first,
  // which would put `zz` before `aaa` and make a generated list read as
  // unordered.
  let out = inits(
    scalars(),
    "{ \"zz\": {}, \"aaa\": {}, \"with-history\": {}, \"a\": {} }",
  )
  assert_eq(out.map(s => s.name), ["a", "aaa", "with-history", "zz"])
  // The MoonBit identifier is the camel form of the fixture name.
  assert_eq(out.map(s => s.ident), ["a", "aaa", "withHistory", "zz"])
}

// -- the type table: one row per declared type ------------------------------

///|
test "scalars emit the literal the field's declared type wants" {
  let s = scalars()
  assert_eq(lit(s, "{ \"f\": { \"label\": \"hi\" } }", "label"), "\"hi\"")
  assert_eq(lit(s, "{ \"f\": { \"isOpen\": true } }", "isOpen"), "true")
  assert_eq(lit(s, "{ \"f\": { \"isOpen\": false } }", "isOpen"), "false")
  assert_eq(lit(s, "{ \"f\": { \"count\": 3 } }", "count"), "3")
  assert_eq(lit(s, "{ \"f\": { \"count\": -7 } }", "count"), "-7")
  // A whole Double still emits a float literal: `3` in MoonBit source would
  // be an Int, and the field is declared Double.
  assert_eq(lit(s, "{ \"f\": { \"ratio\": 3 } }", "ratio"), "3.0")
  assert_eq(lit(s, "{ \"f\": { \"ratio\": 2.5 } }", "ratio"), "2.5")
}

///|
test "a list emits its elements at the element type" {
  let s = scalars()
  assert_eq(
    lit(s, "{ \"f\": { \"history\": [1, 2, 3] } }", "history"),
    "[1, 2, 3]",
  )
  assert_eq(lit(s, "{ \"f\": { \"history\": [] } }", "history"), "[]")
}

///|
test "an option distinguishes absent from null from present" {
  let s = scalars()
  // Null is the option's own empty, not the element's zero.
  assert_eq(lit(s, "{ \"f\": { \"note\": null } }", "note"), "None")
  assert_eq(lit(s, "{ \"f\": { \"note\": \"x\" } }", "note"), "Some(\"x\")")
  // Absent is absent: a fixture spreads over `zero()`, so an unmentioned
  // field is not mentioned at all rather than set to its zero.
  assert_eq(lit(s, "{ \"f\": {} }", "note"), "<unset>")
}

///|
test "null on a non-option field is the type's zero, not a failure" {
  // The fixture said "this one, explicitly, at its default" — a thing a
  // person writes, and one `zero_expr` already knows how to spell.
  let s = scalars()
  assert_eq(lit(s, "{ \"f\": { \"count\": null } }", "count"), "0")
  assert_eq(lit(s, "{ \"f\": { \"label\": null } }", "label"), "\"\"")
  assert_eq(lit(s, "{ \"f\": { \"history\": null } }", "history"), "[]")
  assert_eq(lit(s, "{ \"f\": { \"isOpen\": null } }", "isOpen"), "false")
}

///|
test "a set arrives as a member list and is stored map-backed" {
  // Open membership (`Set[String]`) and closed (`Set[Visibility]`) share one
  // runtime representation, so they share one literal.
  let c = collections()
  assert_eq(
    lit(c, "{ \"f\": { \"tags\": [\"a\", \"b\"] } }", "tags"),
    "Map([\"a\": true, \"b\": true])",
  )
  assert_eq(
    lit(c, "{ \"f\": { \"vis\": [\"Done\"] } }", "vis"),
    "Map([\"Done\": true])",
  )
  assert_eq(lit(c, "{ \"f\": { \"tags\": [] } }", "tags"), "Map([])")
}

///|
test "an ordered map keeps its keys and types its values" {
  assert_eq(
    lit(collections(), "{ \"f\": { \"counts\": { \"a\": \"1\" } } }", "counts"),
    "Map([\"a\": \"1\"])",
  )
}

///|
test "the any marker takes whatever it is given, as a Value" {
  // Including null — the `any` arm is matched before the null-is-zero arm,
  // because there null IS the value rather than an omission.
  let c = collections()
  assert_eq(
    lit(c, "{ \"f\": { \"blob\": null } }", "blob"),
    "@tutuca.Value::from_json(Json::null())",
  )
  assert_eq(
    lit(c, "{ \"f\": { \"blob\": [true] } }", "blob"),
    "@tutuca.Value::from_json(Json::array([Json::boolean(true)]))",
  )
}

///|
test "an enum case resolves under the name the enum declares" {
  // The MoonBit type carries the component prefix (`PostPriority`), because
  // generated types from two components share one module namespace. The
  // *messages* use `show_source`, which keeps the name the author wrote.
  let n = named()
  assert_eq(
    lit(n, "{ \"f\": { \"pri\": \"Low\" } }", "pri"),
    "PostPriority::Low",
  )
  assert_eq(
    lit(n, "{ \"f\": { \"pri\": \"HighIsh\" } }", "pri"),
    "PostPriority::HighIsh",
  )
  // …and the lowerCamel runtime spelling too, which is what a JSON payload
  // from somewhere else is likely to carry.
  assert_eq(
    lit(n, "{ \"f\": { \"pri\": \"highIsh\" } }", "pri"),
    "PostPriority::HighIsh",
  )
}

///|
test "a record fills every declared sub-field, present or not" {
  // The sub-fields the JSON omits are not omitted from the literal: a struct
  // literal has to be total, so they take the sub-field's zero.
  let n = named()
  assert_eq(
    lit(n, "{ \"f\": { \"tag\": { \"text\": \"x\", \"done\": true } } }", "tag"),
    "PostLabel::{ text: \"x\", done: true }",
  )
  assert_eq(
    lit(n, "{ \"f\": { \"tag\": { \"text\": \"x\" } } }", "tag"),
    "PostLabel::{ text: \"x\", done: false }",
  )
}

// -- the rejections ---------------------------------------------------------

///|
test "a block that is not JSON, or not an object of named states" {
  let s = scalars()
  assert_true(init_err(s, "{ nope }").contains("init block: not valid JSON"))
  assert_eq(
    init_err(s, "[1, 2]"),
    "init block: expected an object of named states, e.g. { \"fresh\": { \"count\": 0 } }",
  )
  // Straight to `parse_init`: this is about the BLOCK's shape, so wrapping it
  // in an envelope would be the test hiding what it is asking about.
  assert_eq(
    raw_err(s, "{ \"fresh\": 3 }"),
    "init block: state `fresh` is not an object of fields",
  )
}

///|
/// The envelope's own rules. Everything above is about a fixture's VALUE; a
/// fixture is that value plus what a gallery needs to know about it, and the
/// keys that carry the second half are checked too — a misspelt `doc` silently
/// dropped is a sentence nobody sees missing.
test "a fixture is an envelope, and its keys are checked" {
  let s = scalars()
  // The whole shape, read back.
  let out = @statedef.parse_init(
    (
      #|{ "fresh": {
      #|    "value": { "label": "Counter" },
      #|    "doc": "A counter nobody has pressed yet.",
      #|    "view": "row",
      #|    "tags": ["empty"],
      #|    "default": true,
      #|    "drive": [ { "click": "button.inc" } ],
      #|    "intents": { "rows": "pass" }
      #|} }
    ),
    def_of(s),
  )
  assert_eq(out.length(), 1)
  inspect(out[0].doc, content="A counter nobody has pressed yet.")
  inspect(out[0].view, content="row")
  @debug.assert_eq(out[0].tags, ["empty"])
  assert_true(out[0].default_)
  inspect(out[0].drive.stringify(), content="[{\"click\":\"button.inc\"}]")
  inspect(out[0].intents.stringify(), content="{\"rows\":\"pass\"}")
  // …and the value is still checked against the schema, which is the half the
  // envelope is wrapped around rather than a replacement for.
  @debug.assert_eq(out[0].fields, [("label", "\"Counter\"")])
}

///|
test "a fixture without a value, or with a key that is not one" {
  let s = scalars()
  assert_eq(
    raw_err(s, "{ \"fresh\": { \"label\": \"x\" } }"),
    "init block: state `fresh` has no key `label`; a fixture takes `value`, `doc`, `view`, `drive`, `intents`, `tags` and `default`",
  )
  assert_eq(
    raw_err(s, "{ \"fresh\": { \"doc\": \"x\" } }"),
    "init block: state `fresh` has no `value` — a fixture is { \"value\": { …fields… } }, with `doc`, `view`, `drive`, `intents`, `tags` and `default` beside it",
  )
  // A near miss is guessed at, the way a misspelt FIELD already is.
  assert_eq(
    raw_err(s, "{ \"fresh\": { \"value\": {}, \"dco\": \"x\" } }"),
    "init block: state `fresh` has no key `dco` — did you mean `doc`?",
  )
  assert_eq(
    raw_err(s, "{ \"fresh\": { \"value\": {}, \"tags\": \"one\" } }"),
    "init block: state `fresh`'s `tags` should be a list of strings",
  )
  // A `drive` is the scene vocabulary, so it is the scene reader that says
  // what is wrong with one — checked HERE rather than when something runs it.
  assert_true(
    raw_err(
      s, "{ \"fresh\": { \"value\": {}, \"drive\": [ { \"clik\": \"b\" } ] } }",
    ).contains("names no verb"),
  )
}

///|
test "a field the schema does not declare fails, and the message guesses" {
  let s = scalars()
  assert_eq(
    init_err(s, "{ \"fresh\": { \"labl\": \"x\" } }"),
    "init block: state `fresh` sets `labl`, which the schema does not declare — did you mean `label`?",
  )
  // Nothing close enough to suggest: the message stops rather than pointing
  // somewhere arbitrary.
  assert_eq(
    init_err(s, "{ \"fresh\": { \"wildlyDifferent\": 1 } }"),
    "init block: state `fresh` sets `wildlyDifferent`, which the schema does not declare",
  )
}

///|
test "a fractional number in an integer field is refused, not truncated" {
  assert_eq(
    init_err(scalars(), "{ \"fresh\": { \"count\": 2.5 } }"),
    "init block: state `fresh` sets `count` to 2.5, which is not a whole number, but the schema declares it Int",
  )
}

///|
test "a value of the wrong shape names both halves" {
  let s = scalars()
  assert_eq(
    init_err(s, "{ \"fresh\": { \"count\": \"3\" } }"),
    "init block: state `fresh` sets `count` to a string, but the schema declares it Int",
  )
  assert_eq(
    init_err(s, "{ \"fresh\": { \"label\": 3 } }"),
    "init block: state `fresh` sets `label` to a number, but the schema declares it String",
  )
  assert_eq(
    init_err(s, "{ \"fresh\": { \"history\": 3 } }"),
    "init block: state `fresh` sets `history` to a number, but the schema declares it Array[Int]",
  )
  assert_eq(
    init_err(named(), "{ \"fresh\": { \"pri\": \"nope\" } }"),
    "init block: state `fresh` sets `pri` to \"nope\", which is not one of its cases, but the schema declares it Priority",
  )
}

///|
test "a nested value is blamed on the field the author wrote" {
  // The blame is the STATE field, not the element: that is the name the
  // author can find in the block they are looking at.
  assert_eq(
    init_err(scalars(), "{ \"fresh\": { \"history\": [1, \"two\"] } }"),
    "init block: state `fresh` sets `history` to a string, but the schema declares it Int",
  )
}
