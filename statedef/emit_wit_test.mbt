// The two outputs aimed outside MoonBit: the lowered WIT document and the
// guest accessors.
//
// The load-bearing assertion for `to_wit` is that it ROUND-TRIPS — a
// document that `wit-bindgen` would reject is worse than none, and the only
// honest way to check that here is to feed it back through the parser.

///|
fn defs_of(src : String) -> Array[@statedef.StateDef] raise {
  @statedef.parse_state(src)
}

///|
test "the emitted WIT parses back, with every marker lowered" {
  let defs = defs_of(
    (
      #|interface board {
      #|  enum mode { view, edit }
      #|  record card { title: string, done: bool }
      #|  flags vis { active, archived }
      #|  variant receive { tick, set-mode(mode) }
      #|  record state {
      #|    m: mode,
      #|    cards: list<card>,
      #|    v: vis,
      #|    tags: text-set,
      #|    order: value-omap,
      #|    detail: any,
      #|    pick: option<string>,
      #|  }
      #|}
    ),
  )
  let wit = @statedef.to_wit(defs, pkg="tutuca:demo")
  // Lowered: nothing outside tutuca knows what these markers mean.
  assert_true(wit.contains("tags: list<string>,"))
  assert_true(wit.contains("order: list<tuple<string, string>>,"))
  assert_true(wit.contains("detail: string,"))
  assert_false(wit.contains("text-set"))
  assert_false(wit.contains("value-omap"))
  // Structural forms survive as themselves.
  assert_true(wit.contains("cards: list<card>,"))
  assert_true(wit.contains("pick: option<string>,"))
  assert_true(wit.contains("enum mode { view, edit }"))
  assert_true(wit.contains("flags vis { active, archived }"))
  assert_true(wit.contains("set-mode(mode),"))
  // THE check: a real WIT parser accepts it.
  assert_true(@wit.parse(wit) is Ok(_))
}

///|
test "a schema with no markers round-trips to an equivalent schema" {
  let src =
    #|interface counter {
    #|  record state { label: string, count: s32, history: list<s32> }
    #|}
  let once = defs_of(src)
  let wit = @statedef.to_wit(once)
  // Reparsed after stripping the package line, which parse_state supplies.
  let body = wit.split("package tutuca:state;").collect()
  let again = defs_of(body[body.length() - 1].to_owned())
  assert_eq(again[0].component, once[0].component)
  assert_eq(again[0].fields.map(f => f.name), once[0].fields.map(f => f.name))
  // ...and the fingerprint agrees, which is the property that makes it
  // usable as a compatibility check at all.
  assert_eq(@statedef.fingerprint(again), @statedef.fingerprint(once))
}

///|
test "the fingerprint tracks shape, not formatting" {
  let a = defs_of("interface c { record state { n: s32, s: string } }")
  let spaced = defs_of(
    "interface c {\n\n  record state {\n    n: s32,\n    s: string,\n  }\n}",
  )
  assert_eq(@statedef.fingerprint(a), @statedef.fingerprint(spaced))
  // A retyped field is a different shape...
  let retyped = defs_of("interface c { record state { n: f64, s: string } }")
  assert_not_eq(@statedef.fingerprint(a), @statedef.fingerprint(retyped))
  // ...as is a renamed one, an added one, and a new message case.
  assert_not_eq(
    @statedef.fingerprint(a),
    @statedef.fingerprint(
      defs_of("interface c { record state { m: s32, s: string } }"),
    ),
  )
  assert_not_eq(
    @statedef.fingerprint(a),
    @statedef.fingerprint(
      defs_of("interface c { record state { n: s32, s: string, x: bool } }"),
    ),
  )
  assert_not_eq(
    @statedef.fingerprint(a),
    @statedef.fingerprint(
      defs_of(
        "interface c { variant receive { tick } record state { n: s32, s: string } }",
      ),
    ),
  )
}

///|
test "a guest gets its struct and the four shape-derived accessors" {
  let defs = defs_of(
    "interface counter { record state { count: s32, label: string } }",
  )
  let src = @statedef.to_guest(defs[0])
  assert_true(src.contains("priv struct Counter {"))
  assert_true(src.contains("  count : Int"))
  assert_true(src.contains("  label : String"))
  // Lazy read, one field at a time — the host never marshals the whole state.
  assert_true(src.contains("impl DynComponent for Counter with fn get_field"))
  assert_true(
    src.contains(
      "\"count\" => Some(@values.Value::Number(self.count.to_double()))",
    ),
  )
  // COW write-through.
  assert_true(src.contains("impl DynComponent for Counter with fn with_field"))
  assert_true(src.contains("(\"label\", @values.Value::Text(s)) =>"))
  assert_true(src.contains("Some({ ..self, label: s } as &DynComponent)"))
  // The JSON projection the host uses for inspection and hot-swap migration.
  assert_true(src.contains("impl DynComponent for Counter with fn to_json"))
  assert_true(src.contains("\\\"count\\\": "))
  // Behaviour is NOT generated: that is what a guest is for.
  assert_false(src.contains("fn handle("))
  assert_false(src.contains("fn call_method"))
  // The fingerprint rides along, so a guest built against an older shape is
  // identifiable rather than merely broken.
  assert_true(src.contains("schema fingerprint: "))
}

///|
test "a guest's list field builds an arena handle, not a MoonBit array" {
  let defs = defs_of("interface c { record state { history: list<s32> } }")
  let src = @statedef.to_guest(defs[0])
  assert_true(src.contains("@values.list_new()"))
  assert_true(
    src.contains("@values.list_push(h, @values.Value::Number(x.to_double()))"),
  )
  assert_true(src.contains("@values.Value::List(h)"))
  // A single-list state is iterable as itself, so `@each` over the instance
  // works on the host side.
  assert_true(src.contains("fn seq_entries"))
}

///|
test "a field with no total decode is left unwritable rather than lossy" {
  let defs = defs_of("interface c { record state { n: s32, blob: any } }")
  let src = @statedef.to_guest(defs[0])
  // `n` can be written back...
  assert_true(src.contains("(\"n\", @values.Value::Number(n)) =>"))
  // ...`blob` cannot, and falls to the `_ => None` the host understands as
  // "not supported". A guessed decode would be a wrong write instead.
  assert_false(src.contains("(\"blob\","))
  assert_true(src.contains("    _ => None"))
}
