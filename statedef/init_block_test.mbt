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
// `s32` has said something it did not mean, and a checker that truncates it is
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
/// The fixtures an init block yields against a schema.
fn inits(schema : String, init : String) -> Array[@statedef.InitState] raise {
  @statedef.parse_init(init, def_of(schema))
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
    #|interface counter {
    #|  record state {
    #|    label: string,
    #|    count: s32,
    #|    ratio: f64,
    #|    is-open: bool,
    #|    note: option<string>,
    #|    history: list<s32>,
    #|  }
    #|}
  )
}

///|
/// The map-backed shapes, plus the dynamic escape hatch.
fn collections() -> String {
  (
    #|interface board {
    #|  flags visibility { done, active }
    #|  record state {
    #|    tags: text-set,
    #|    vis: visibility,
    #|    counts: text-omap,
    #|    blob: any,
    #|  }
    #|}
  )
}

///|
/// The two named-type shapes a fixture can name a case or a sub-field of.
fn named() -> String {
  (
    #|interface post {
    #|  enum priority { low, high-ish }
    #|  record label { text: string, done: bool }
    #|  record state { pri: priority, tag: label }
    #|}
  )
}

///|
test "a fixture names fields in schema order, under either spelling" {
  // Deliberately out of JSON order, and mixing the WIT spelling with the
  // runtime one: both are accepted, because both are names the author
  // legitimately has in hand.
  let out = inits(
    scalars(),
    "{ \"fresh\": { \"is-open\": true, \"count\": 3, \"label\": \"Counter\" } }",
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
  // A whole f64 still emits a float literal: `3` in MoonBit source would be
  // an Int, and the field is declared f64.
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
  // Open membership (`text-set`) and closed membership (`flags`) share one
  // runtime representation, so they share one literal.
  let c = collections()
  assert_eq(
    lit(c, "{ \"f\": { \"tags\": [\"a\", \"b\"] } }", "tags"),
    "Map([\"a\": true, \"b\": true])",
  )
  assert_eq(
    lit(c, "{ \"f\": { \"vis\": [\"done\"] } }", "vis"),
    "Map([\"done\": true])",
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
test "an enum case resolves under its WIT name or its runtime name" {
  // The MoonBit type carries the component prefix (`PostPriority`), because
  // generated types from two components share one module namespace. The
  // *messages* below use `show_wit`, which keeps the WIT name (`priority`) —
  // the author wrote that one, so that is the one to hand back.
  let n = named()
  assert_eq(
    lit(n, "{ \"f\": { \"pri\": \"low\" } }", "pri"),
    "PostPriority::Low",
  )
  assert_eq(
    lit(n, "{ \"f\": { \"pri\": \"high-ish\" } }", "pri"),
    "PostPriority::HighIsh",
  )
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
  assert_eq(
    init_err(s, "{ \"fresh\": 3 }"),
    "init block: state `fresh` is not an object of fields",
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
    "init block: state `fresh` sets `count` to 2.5, which is not a whole number, but the schema declares it s32",
  )
}

///|
test "a value of the wrong shape names both halves" {
  let s = scalars()
  assert_eq(
    init_err(s, "{ \"fresh\": { \"count\": \"3\" } }"),
    "init block: state `fresh` sets `count` to a string, but the schema declares it s32",
  )
  assert_eq(
    init_err(s, "{ \"fresh\": { \"label\": 3 } }"),
    "init block: state `fresh` sets `label` to a number, but the schema declares it string",
  )
  assert_eq(
    init_err(s, "{ \"fresh\": { \"history\": 3 } }"),
    "init block: state `fresh` sets `history` to a number, but the schema declares it list<s32>",
  )
  assert_eq(
    init_err(named(), "{ \"fresh\": { \"pri\": \"nope\" } }"),
    "init block: state `fresh` sets `pri` to \"nope\", which is not one of its cases, but the schema declares it priority",
  )
}

///|
test "a nested value is blamed on the field the author wrote" {
  // The blame is the STATE field, not the element: that is the name the
  // author can find in the block they are looking at.
  assert_eq(
    init_err(scalars(), "{ \"fresh\": { \"history\": [1, \"two\"] } }"),
    "init block: state `fresh` sets `history` to a string, but the schema declares it s32",
  )
}
