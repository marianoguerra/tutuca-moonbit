///|
/// The spellings. `to_json` is what a person and an agent read, so what it
/// writes is part of the contract rather than an implementation detail.
test "the $-tagged spellings" {
  let rows : Array[(@core.Value, String)] = [
    (Null, "null"),
    (Bool(true), "true"),
    (Num(1.5), "1.5"),
    (Str("hi"), "\"hi\""),
    (Int(9_007_199_254_740_993L), "{\"$\":\"int\",\"v\":\"9007199254740993\"}"),
    (Bin(b"Hello"), "{\"$\":\"bin\",\"v\":\"SGVsbG8=\"}"),
    (
      Instant(secs=1_756_915_200L, nanos=123_000_000),
      "{\"$\":\"instant\",\"v\":\"2025-09-03T16:00:00.123Z\"}",
    ),
    (List([Int(1L)]), "[{\"$\":\"int\",\"v\":\"1\"}]"),
    (Map({ "a": Num(1.0) }), "{\"a\":1}"),
  ]
  for row in rows {
    let (v, want) = row
    assert_eq(v.to_json().stringify(), want)
  }
}

///|
/// The escape, in both directions. Without it `{"$":"bin"}` as DATA and the
/// same six bytes as a TAG are indistinguishable, and a decoder has to guess.
test "a map carrying the discriminator is escaped, and reads back as data" {
  let colliding : @core.Value = Map({ "$": Str("bin"), "v": Str("SGVsbG8=") })
  let written = colliding.to_json()
  assert_eq(
    written.stringify(),
    "{\"$\":\"map\",\"v\":{\"$\":\"bin\",\"v\":\"SGVsbG8=\"}}",
  )
  // The point: it comes back as the MAP it was, not as the binary it looks like.
  assert_eq(@core.Value::from_json(written), colliding)
  // And the unescaped six bytes still read as the tag they are.
  assert_eq(
    @core.Value::from_json(@json.parse("{\"$\":\"bin\",\"v\":\"SGVsbG8=\"}")),
    Bin(b"Hello"),
  )
}

///|
/// Everything JSON can carry round-trips, including the three arms it has no
/// shape of its own for.
test "JSON round-trips every encodable arm" {
  let v : @core.Value = Map({
    "n": Null,
    "b": Bool(false),
    "num": Num(0.5),
    "int": Int(-9_007_199_254_740_993L),
    "s": Str("héllo ☃"),
    "bin": Bin(b"\x00\xff\xfe"),
    "t": Instant(secs=1_756_915_200L, nanos=123_456_789),
    "list": List([Int(1L), Str("x"), Null]),
    "nested": Map({ "$": Num(1.0) }),
  })
  assert_eq(@core.Value::from_json(v.to_json()), v)
}

///|
/// The documented asymmetry, asserted rather than described: a plain JSON
/// number is a double on the way in, whatever it was on the way out. That is
/// why `to_json` never writes one for an `Int`.
test "a plain JSON number decodes to a double" {
  assert_eq(@core.Value::from_json(@json.parse("42")), Num(42.0))
  assert_eq(@core.Value::from_json(@core.Value::Int(42L).to_json()), Int(42L))
}

///|
/// A tag nobody defines, or a payload of the wrong shape, reads as the object
/// it is. `from_json` is total, and a map is what one looks like.
test "an unknown tag reads as the object it is" {
  let j = @json.parse("{\"$\":\"quaternion\",\"v\":1}")
  assert_eq(
    @core.Value::from_json(j),
    Map({ "$": Str("quaternion"), "v": Num(1.0) }),
  )
}

///|
/// `Int(1)` and `Num(1.0)` are the same number. The language has one, and a
/// card comparing a count to a literal must not care which arm carried it.
test "an integer and a double of the same number compare equal" {
  assert_true(@core.Value::Int(1L) == Num(1.0))
  assert_true(@core.Value::Num(1.0) == Int(1L))
  // Past 2^53 they do not, because rounding one side to meet the other is how
  // two values that differ come to compare equal.
  assert_false(
    @core.Value::Int(9_007_199_254_740_993L) == Num(9007199254740992.0),
  )
}
