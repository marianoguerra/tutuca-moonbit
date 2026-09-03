///|
/// The wire, byte for byte, for the cases where the standard says what the
/// bytes must be. A round-trip test alone would pass for an encoder that agreed
/// only with itself.
test "CBOR writes the standard's bytes" {
  let rows : Array[(@tutuca.Value, String)] = [
    (Null, "f6"),
    (Bool(false), "f4"),
    (Bool(true), "f5"),
    (Int(0L), "00"),
    (Int(23L), "17"),
    (Int(24L), "1818"),
    (Int(-1L), "20"),
    (Int(-1000L), "3903e7"),
    (Num(1.5), "fb3ff8000000000000"),
    (Str("a"), "6161"),
    // Non-ASCII goes out as UTF-8, which is the wire encoding and the GC type.
    (Str("é"), "62c3a9"),
    (Bin(b"\x01\x02"), "420102"),
    (List([Int(1L), Int(2L)]), "820102"),
    (Map({ "a": Int(1L) }), "a1616101"),
    // tag 1 + an integer: RFC 8949's own epoch time.
    (Instant(secs=1L, nanos=0), "c101"),
    // tag 1 + tag 4 decimal fraction [-9, 1_500_000_000].
    (Instant(secs=1L, nanos=500_000_000), "c1c482281a59682f00"),
  ]
  for row in rows {
    let (v, want) = row
    assert_eq(
      hex(@value.to_cbor(v)),
      want,
      msg="encoding \{v.to_display_string()}",
    )
    assert_eq(
      @value.of_cbor(@value.to_cbor(v)),
      v,
      msg="round trip of \{v.to_display_string()}",
    )
  }
}

///|
/// Every arm survives, including the three that have no JSON shape at all. This
/// is what "CBOR is the faithful encoding" has to mean.
test "CBOR round-trips every arm" {
  let nested : @tutuca.Value = Map({
    "n": Null,
    "b": Bool(true),
    "num": Num(0.1),
    // 2^53 + 1: exactly the value a double cannot hold, and exactly the reason
    // `Int` exists.
    "int": Int(9_007_199_254_740_993L),
    "s": Str("héllo ☃"),
    "bin": Bin(b"\x00\xff\xfe"),
    "t": Instant(secs=1_756_915_200L, nanos=123_456_789),
    "before": Instant(secs=-1L, nanos=500_000_000),
    "list": List([Int(1L), Str("x"), Null]),
    "empty_list": List([]),
    "empty_map": Map({}),
  })
  assert_eq(@value.of_cbor(@value.to_cbor(nested)), nested)
}

///|
/// A function has no encoding, and saying so beats writing a null that a reader
/// would take for a value.
test "a function is refused, with a reason" {
  let got = try {
    let _ = @value.to_cbor(Map({ "f": Fn(_ => Null) }))
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
/// A duplicate key cannot be BUILT — a MoonBit `Map` holds each key once — so
/// the check that matters is the one on the way in, where the bytes decide.
test "duplicate keys are refused" {
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
  assert_eq(@value.of_cbor(b"\x18\x17"), Int(23L))
  assert_eq(hex(@value.to_cbor(Int(23L))), "17")
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

///|
/// A component instance cannot be encoded BY VALUE, and the reason names what
/// would be needed: the module that made it and the bytes it persists, which a
/// value codec has neither of.
test "an instance is refused, and says what would carry one" {
  let got = try {
    let _ = @value.to_cbor(Map({ "child": Obj(FakeObj::{ }) }))
    "encoded"
  } catch {
    e => e.message()
  }
  assert_true(got.contains("component instance"), msg=got)
  assert_true(got.contains("tgc/persist"), msg=got)
}

///|
/// The two wire cases `core.Value` has no arm for LAND rather than vanish. A
/// reader that has the module can rebuild the instance; one that does not still
/// knows what it was looking at.
test "a foreign instance and an extension value land as maps" {
  // tag 40001 wrapping ["m", "C", h'07'].
  let comp = @value.of_cbor(b"\xd9\x9c\x41\x83\x61\x6d\x61\x43\x41\x07")
  assert_eq(comp.key(@value.comp_module_key), Str("m"))
  assert_eq(comp.key(@value.comp_component_key), Str("C"))
  // tag 40002 wrapping [99, "x"].
  let ext = @value.of_cbor(b"\xd9\x9c\x42\x82\x18\x63\x61\x78")
  assert_eq(ext.key(@value.ext_tag_key), Int(99L))
  assert_eq(ext.key("v"), Str("x"))
}

///|
/// An `Obj` with nothing in it. Every method of the trait is defaulted, so a
/// test that only needs the ARM needs no implementation.
priv struct FakeObj {}

///|
impl @tutuca.Obj for FakeObj with fn debug(_) {
  "a component"
}
