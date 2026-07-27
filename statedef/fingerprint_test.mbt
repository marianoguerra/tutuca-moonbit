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
