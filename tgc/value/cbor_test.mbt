///|
/// The wire, byte for byte, for the cases where the standard says what the
/// bytes must be. A round-trip test alone would pass for an encoder that agreed
/// only with itself.
test "CBOR writes the standard's bytes" {
  let rows : Array[(@value.TVal, String)] = [
    (TNull, "f6"),
    (TBool(false), "f4"),
    (TBool(true), "f5"),
    (TInt(0L), "00"),
    (TInt(23L), "17"),
    (TInt(24L), "1818"),
    (TInt(-1L), "20"),
    (TInt(-1000L), "3903e7"),
    (TNum(1.5), "fb3ff8000000000000"),
    (TStr("a"), "6161"),
    // Non-ASCII goes out as UTF-8, which is the wire encoding and the GC type.
    (TStr("é"), "62c3a9"),
    (TBin(b"\x01\x02"), "420102"),
    (TList([TInt(1L), TInt(2L)]), "820102"),
    (TMap([("a", TInt(1L))]), "a1616101"),
    // tag 1 + an integer: RFC 8949's own epoch time.
    (TInstant(secs=1L, nanos=0), "c101"),
    // tag 1 + tag 4 decimal fraction [-9, 1_500_000_000].
    (TInstant(secs=1L, nanos=500_000_000), "c1c482281a59682f00"),
  ]
  for row in rows {
    let (v, want) = row
    assert_eq(hex(@value.to_cbor(v)), want, msg="encoding \{v}")
    assert_eq(@value.of_cbor(@value.to_cbor(v)), v, msg="round trip of \{v}")
  }
}

///|
/// Every arm survives, including the three that have no JSON shape at all. This
/// is what "CBOR is the faithful encoding" has to mean.
test "CBOR round-trips every arm" {
  let nested : @value.TVal = TMap([
    ("n", TNull),
    ("b", TBool(true)),
    ("num", TNum(0.1)),
    // 2^53 + 1: exactly the value a double cannot hold, and exactly the reason
    // TInt exists.
    ("int", TInt(9_007_199_254_740_993L)),
    ("s", TStr("héllo ☃")),
    ("bin", TBin(b"\x00\xff\xfe")),
    ("t", TInstant(secs=1_756_915_200L, nanos=123_456_789)),
    ("before", TInstant(secs=-1L, nanos=500_000_000)),
    ("list", TList([TInt(1L), TStr("x"), TNull])),
    ("comp", TComp({ module_: "m", component: "C", state: b"\x07", })),
    ("ext", TExt(ext_tag=99, payload=TStr("whatever"))),
    ("empty_list", TList([])),
    ("empty_map", TMap([])),
  ])
  assert_eq(@value.of_cbor(@value.to_cbor(nested)), nested)
}

///|
/// A function has no encoding, and saying so beats writing a null that a reader
/// would take for a value.
test "a function is refused, with a reason" {
  let got = try {
    let _ = @value.to_cbor(TMap([("f", TFunc)]))
    "encoded"
  } catch {
    e => e.message()
  }
  assert_true(got.contains("cannot encode a function"), msg=got)
}

///|
/// Trailing bytes are a different message from the one that was sent.
test "trailing bytes are refused" {
  let got = try {
    let _ = @value.of_cbor(b"\xf6\xf6")
    "accepted"
  } catch {
    Trailing(..) => "refused"
    e => "wrong error: \{e}"
  }
  assert_eq(got, "refused")
}

///|
/// A truncated input names where it ran out and what it was in the middle of.
test "a truncated input says where" {
  // A double's header with one of its eight bytes.
  let got = try {
    let _ = @value.of_cbor(b"\xfb\x00")
    "accepted"
  } catch {
    e => e.message()
  }
  assert_true(got.contains("byte 2"), msg=got)
  assert_true(got.contains("a double"), msg=got)
}

///|
/// A length larger than the input left is refused AT THE HEAD, before anything
/// is allocated for it. A five-byte message must not be able to ask for four
/// gigabytes.
test "an impossible length is refused before it is believed" {
  let got = try {
    let _ = @value.of_cbor(b"\x9a\xff\xff\xff\xff")
    "accepted"
  } catch {
    e => e.message()
  }
  assert_true(got.contains("bytes left"), msg=got)
}

///|
/// One key twice is refused rather than resolved, in both directions.
test "duplicate keys are refused" {
  let enc = try {
    let _ = @value.to_cbor(TMap([("a", TInt(1L)), ("a", TInt(2L))]))
    "encoded"
  } catch {
    DuplicateKey(..) => "refused"
    e => "wrong: \{e}"
  }
  assert_eq(enc, "refused")
  let dec = try {
    let _ = @value.of_cbor(b"\xa2\x61\x61\x01\x61\x61\x02")
    "accepted"
  } catch {
    DuplicateKey(..) => "refused"
    e => "wrong: \{e}"
  }
  assert_eq(dec, "refused")
}

///|
/// Non-shortest heads mean the same number and are accepted; the encoder still
/// only ever writes the short one.
test "a non-shortest head reads as the number it denotes" {
  assert_eq(@value.of_cbor(b"\x18\x17"), TInt(23L))
  assert_eq(hex(@value.to_cbor(TInt(23L))), "17")
}

///|
fn hex(b : Bytes) -> String {
  let digits = "0123456789abcdef"
  let out = StringBuilder()
  for i in 0..<b.length() {
    let v = b[i].to_int()
    out.write_string(digits[v / 16:v / 16 + 1].to_owned())
    out.write_string(digits[v % 16:v % 16 + 1].to_owned())
  }
  out.to_string()
}
