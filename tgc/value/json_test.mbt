///|
/// The spellings. `to_json` is what a person and an agent read, so what it
/// writes is part of the contract and not an implementation detail.
test "JSON writes the tagged spellings" {
  let rows : Array[(@value.TVal, String)] = [
    (TNull, "null"),
    (TBool(true), "true"),
    (TNum(1.5), "1.5"),
    (TStr("hi"), "\"hi\""),
    (TInt(9_007_199_254_740_993L), "{\"$\":\"int\",\"v\":\"9007199254740993\"}"),
    (TBin(b"Hello"), "{\"$\":\"bin\",\"v\":\"SGVsbG8=\"}"),
    (
      TInstant(secs=1_756_915_200L, nanos=123_000_000),
      "{\"$\":\"instant\",\"v\":\"2025-09-03T16:00:00.123Z\"}",
    ),
    (TList([TInt(1L)]), "[{\"$\":\"int\",\"v\":\"1\"}]"),
    (TMap([("a", TNum(1.0))]), "{\"a\":1}"),
    (
      TComp({ module_: "m", component: "C", state: b"\x07", }),
      "{\"$\":\"comp\",\"v\":{\"module\":\"m\",\"component\":\"C\",\"state\":\"Bw==\"}}",
    ),
    (
      TExt(ext_tag=99, payload=TStr("x")),
      "{\"$\":\"ext\",\"tag\":99,\"v\":\"x\"}",
    ),
  ]
  for row in rows {
    let (v, want) = row
    assert_eq(@value.to_json(v).stringify(), want, msg="encoding \{v}")
  }
}

///|
/// The escape, in both directions. Without it `{"$":"bin"}` as DATA and the same
/// six bytes as a TAG are indistinguishable, and a decoder has to guess.
test "a map carrying the discriminator is escaped, and reads back as data" {
  let colliding : @value.TVal = TMap([
    ("$", TStr("bin")),
    ("v", TStr("SGVsbG8=")),
  ])
  let written = @value.to_json(colliding)
  assert_eq(
    written.stringify(),
    "{\"$\":\"map\",\"v\":{\"$\":\"bin\",\"v\":\"SGVsbG8=\"}}",
  )
  // The point: it comes back as the MAP it was, not as the binary it looks like.
  assert_eq(@value.of_json(written), colliding)
  // And the unescaped six bytes still read as the tag they are.
  assert_eq(
    @value.of_json(@json.parse("{\"$\":\"bin\",\"v\":\"SGVsbG8=\"}")),
    TBin(b"Hello"),
  )
}

///|
/// Everything JSON can carry round-trips. `TNum` and `TInt` are the two the
/// asymmetry is about and both survive `to_json` -> `of_json`, because
/// `to_json` always tags an integer.
test "JSON round-trips every encodable arm" {
  let v : @value.TVal = TMap([
    ("n", TNull),
    ("b", TBool(false)),
    ("num", TNum(0.5)),
    ("int", TInt(-9_007_199_254_740_993L)),
    ("s", TStr("héllo ☃")),
    ("bin", TBin(b"\x00\xff\xfe")),
    ("t", TInstant(secs=1_756_915_200L, nanos=123_456_789)),
    ("list", TList([TInt(1L), TStr("x"), TNull])),
    ("nested", TMap([("$", TNum(1.0))])),
    ("comp", TComp({ module_: "m", component: "C", state: b"\x07", })),
    ("ext", TExt(ext_tag=99, payload=TList([TInt(1L)]))),
  ])
  assert_eq(@value.of_json(@value.to_json(v)), v)
}

///|
/// The documented asymmetry, asserted rather than described: a plain JSON number
/// is a double on the way in, whatever it was on the way out.
test "a plain JSON number decodes to a double" {
  assert_eq(@value.of_json(@json.parse("42")), TNum(42.0))
  // Which is why to_json never writes one for a TInt.
  assert_eq(@value.of_json(@value.to_json(TInt(42L))), TInt(42L))
}

///|
/// A tag nobody defines is named, because the tag is the one thing a reader
/// cannot guess.
test "an unknown tagged type says which" {
  let got = try {
    let _ = @value.of_json(@json.parse("{\"$\":\"quaternion\",\"v\":1}"))
    "accepted"
  } catch {
    e => "\{e}"
  }
  assert_true(got.contains("quaternion"), msg=got)
}

///|
/// A `$` that is not a string is a collision nobody escaped: say so, and say
/// what the escape looks like.
test "an unescaped collision is refused with the fix in the message" {
  let got = try {
    let _ = @value.of_json(@json.parse("{\"$\":1}"))
    "accepted"
  } catch {
    e => "\{e}"
  }
  assert_true(got.contains("\"$\":\"map\""), msg=got)
}

///|
/// A function is refused here for the same reason it is refused in CBOR.
test "a function has no JSON either" {
  let got = try {
    let _ = @value.to_json(TFunc)
    "encoded"
  } catch {
    e => "\{e}"
  }
  assert_true(got.contains("cannot encode a function"), msg=got)
}

///|
/// Bad base64 says which character, at which pointer.
test "bad base64 names the character" {
  let got = try {
    let _ = @value.of_json(@json.parse("{\"$\":\"bin\",\"v\":\"!!!!\"}"))
    "accepted"
  } catch {
    e => "\{e}"
  }
  assert_true(got.contains("not base64"), msg=got)
}
