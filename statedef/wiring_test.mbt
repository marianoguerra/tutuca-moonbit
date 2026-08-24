// The `provide { … }` / `lookup { … }` sections of a `state` body.
//
// Wiring, in the schema block, because a card has no other place to put it:
// the manifest a host reads is a projection of the file rather than a second
// thing to author, and `provide` is the one thing that projection was missing.
//
// The expressions are the VALUE language and this package does not read one.
// It finds where each ends and hands the slice on; whether `.sheets[.selId]`
// is addressable, and whether `self` is legal under an uppercase name, are the
// component layer's questions.

///|
fn wiring_of(src : String) -> @statedef.StateDef raise {
  @statedef.parse_state(src)[0]
}

///|
fn wiring_fails(src : String) -> String {
  try {
    @statedef.parse_state(src) |> ignore
    ""
  } catch {
    e => e.message()
  }
}

///|
test "a provide section carries names and their source text" {
  let d = wiring_of(
    (
      #|state Board {
      #|  theme: String
      #|  sheets: Map[String, String]
      #|  selId: String
      #|  provide { theme = .theme, sel = .sheets[.selId], Cell = self }
      #|}
    ),
  )
  assert_eq(d.provide.map(p => p.name), ["theme", "sel", "Cell"])
  // Untouched, brackets and all: the `,` inside `[.selId]` does not end the
  // entry, because the scan tracks nesting.
  assert_eq(d.provide.map(p => p.source), [".theme", ".sheets[.selId]", "self"])
}

///|
test "a lookup section names what it wants, and may say what to fall back on" {
  let d = wiring_of(
    (
      #|state Slot {
      #|  made: String
      #|  lookup { theme, color = 'gray', Cell }
      #|}
    ),
  )
  assert_eq(d.lookup.map(l => l.name), ["theme", "color", "Cell"])
  assert_eq(d.lookup.map(l => l.default), [None, Some("'gray'"), None])
}

///|
test "a quoted default may contain a comma" {
  // The scan is quote-aware for the same reason it is nesting-aware: a comma
  // ends an ENTRY, and one inside a string ends nothing.
  let d = wiring_of(
    (
      #|state Slot {
      #|  made: String
      #|  lookup { label = 'a, b' }
      #|}
    ),
  )
  assert_eq(d.lookup[0].default, Some("'a, b'"))
}

///|
test "provide and lookup are not reserved field names" {
  // The section opens on the word plus a BRACE, so nothing was taken away from
  // an author to add this: a field may still be called either.
  let d = wiring_of(
    (
      #|state Board {
      #|  provide: String
      #|  lookup: Int
      #|}
    ),
  )
  assert_eq(d.fields.map(f => f.name), ["provide", "lookup"])
  assert_eq(d.provide.length(), 0)
  assert_eq(d.lookup.length(), 0)
}

///|
test "a provide with nothing to produce it is refused" {
  // There is no shorthand for "the field of the same name": a provide is read
  // as a PATH, and one that has to be inferred is one an author cannot see.
  let msg = wiring_fails(
    (
      #|state Board {
      #|  theme: String
      #|  provide { theme }
      #|}
    ),
  )
  assert_true(msg.contains("provided with nothing"))
  assert_true(msg.contains("theme = .theme"))
}

///|
test "the same name twice in one section is refused" {
  for
    src in [
      "state B { x: String\n provide { x = .x, x = .x } }", "state B { x: String\n lookup { x, x } }",
    ] {
    assert_true(wiring_fails(src).contains("twice"))
  }
}

///|
test "only a state may carry wiring" {
  // A struct describes a VALUE, and a value publishes nothing to a subtree.
  let msg = wiring_fails(
    (
      #|struct Row { label: String
      #|  provide { label = .label }
      #|}
      #|state Board { rows: Array[Row] }
    ),
  )
  assert_true(msg.contains("only a component can say"))
}

///|
test "an equals with no expression after it is refused" {
  assert_true(
    wiring_fails("state B { x: String\n provide { x = } }").contains(
      "no expression",
    ),
  )
}

///|
test "a card that declares no wiring has none" {
  let d = wiring_of("state Board { theme: String }")
  assert_eq(d.provide.length(), 0)
  assert_eq(d.lookup.length(), 0)
}
