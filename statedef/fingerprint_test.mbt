// The schema's structural fingerprint.
//
// What it is for is noticing that a stored state changed SHAPE rather than
// merely moved: a hot swap or a stored state that crosses a change in this
// value has to migrate rather than reinterpret. So the assertions are a pair —
// reformatting must not move it, renaming a field must.

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
      defs_of("receive C { Tick }\nstate C { n: Int, s: String }"),
    ),
  )
}
