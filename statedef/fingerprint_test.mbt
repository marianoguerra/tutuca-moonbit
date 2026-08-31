// The schema's structural fingerprint.
//
// What it is for is noticing that a stored state changed SHAPE rather than
// merely moved: a hot swap or a stored state that crosses a change in this
// value has to migrate rather than reinterpret. So the assertions are a pair —
// reformatting must not move it, renaming a field must.
//
// Recasing is reformatting, not renaming: the parser derives one runtime name
// and one variant from whichever spelling was written, so `Tick` and `tick`
// declare the same message and must hash the same.

///|
fn defs_of(src : String) -> Array[@statedef.StateDef] raise {
  @statedef.parse_state(src)
}

///|
test "the fingerprint tracks shape, not formatting" {
  let a = defs_of("state C { n: Int, s: String }")
  let spaced = defs_of("state C {\n\n  n : Int\n\n  s : String\n}")
  assert_eq(@statedef.fingerprint(a), @statedef.fingerprint(spaced))
  // A retyped field is a different shape...
  let retyped = defs_of("state C { n: Double, s: String }")
  assert_not_eq(@statedef.fingerprint(a), @statedef.fingerprint(retyped))
  // ...as is a renamed one, an added one, and a new message case.
  assert_not_eq(
    @statedef.fingerprint(a),
    @statedef.fingerprint(defs_of("state C { m: Int, s: String }")),
  )
  assert_not_eq(
    @statedef.fingerprint(a),
    @statedef.fingerprint(defs_of("state C { n: Int, s: String, x: Bool }")),
  )
  assert_not_eq(
    @statedef.fingerprint(a),
    @statedef.fingerprint(
      defs_of("handle C { message { tick } }\nstate C { n: Int, s: String }"),
    ),
  )
}

///|
test "the fingerprint reads a name, not its spelling" {
  // Every one of these declares the same schema: the parser lowercases a case
  // name's first character to make the runtime name and uppercases it to make
  // the variant, so the written spelling reaches nothing downstream. A
  // fingerprint that moved here would report a restyled block as a shape the
  // stored state can no longer be read back into.
  let written = defs_of(
    "state Board { rows: Array[Any] }\nhandle Board { message { Reset, FocusRow(Int) } intent { RowPicked(Int) } }",
  )
  let used = defs_of(
    "state Board { rows: Array[Any] }\nhandle Board { message { reset, focusRow(Int) } intent { rowPicked(Int) } }",
  )
  assert_eq(@statedef.fingerprint(written), @statedef.fingerprint(used))
  // A named type's cases answer the same way. Its NAME is a separate matter:
  // a `StateTy` carries the spelling a field referred to it by, so `m: Mode`
  // and `m: mode` still hash apart — recasing a type is a rename of something
  // the state itself mentions, not a restyle of a case list.
  assert_eq(
    @statedef.fingerprint(
      defs_of("enum Mode { Live, Draft }\nstate C { m: Mode }"),
    ),
    @statedef.fingerprint(
      defs_of("enum Mode { live, draft }\nstate C { m: Mode }"),
    ),
  )
  // The bucket a name sits in is NOT spelling: the same name answering a
  // different channel is a different schema, which is why all four are hashed
  // under four distinct letters.
  assert_not_eq(
    @statedef.fingerprint(
      defs_of("state C { n: Int }\nhandle C { message { tick } }"),
    ),
    @statedef.fingerprint(
      defs_of("state C { n: Int }\nhandle C { intent { tick } }"),
    ),
  )
}

///|
test "property visibility and access are part of the interface shape" {
  let private_read = defs_of(
    "state C { n: Int property { value: Int { get .n } } }",
  )
  let public_read = defs_of(
    "state C { n: Int property { pub value: Int { get .n } } }",
  )
  let public_write = defs_of(
    "state C { n: Int property { pub value: Int { get .n set .n } } }",
  )
  assert_not_eq(
    @statedef.fingerprint(private_read),
    @statedef.fingerprint(public_read),
  )
  assert_not_eq(
    @statedef.fingerprint(public_read),
    @statedef.fingerprint(public_write),
  )
}
