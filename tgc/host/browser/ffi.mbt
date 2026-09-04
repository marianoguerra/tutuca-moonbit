///| The primitives a `tg_val` is read and built through.
///
/// Everything else in this package is written in terms of these, and there are
/// deliberately few: each one is a place where the JS and MoonBit type systems
/// have to agree about a scalar, and a place is a chance to disagree.
///
/// `@core.Any` is an opaque JS value. A wasm-GC struct handed to JS is exactly
/// that, which is the whole reason this package can exist — the seam was never
/// the target, it was `&Guest` having been written with `handle : Int` in every
/// signature.

///|
extern "js" fn is_absent(v : @core.Any) -> Bool =
  #|(v) => v === null || v === undefined

///|
extern "js" fn as_int(v : @core.Any) -> Int =
  #|(v) => v

///|
extern "js" fn as_double(v : @core.Any) -> Double =
  #|(v) => v

///|
extern "js" fn of_int(v : Int) -> @core.Any =
  #|(v) => v

///|
extern "js" fn of_double(v : Double) -> @core.Any =
  #|(v) => v

///|
extern "js" fn null_any() -> @core.Any =
  #|() => null

///|
/// A `tg_bytes` as a MoonBit string.
///
/// The runtime keeps text as bytes, so this is one `TextDecoder` and a loop.
/// It is an extern rather than a loop over `bytes_at` in MoonBit because that
/// loop is per CHARACTER across the boundary, and text is the most common thing
/// that crosses.
extern "js" fn text_of(rt : @core.Any, b : @core.Any) -> String =
  #|(rt, b) => {
  #|  const n = rt.bytes_len(b);
  #|  const u8 = new Uint8Array(n);
  #|  for (let i = 0; i < n; i++) u8[i] = rt.bytes_at(b, i);
  #|  return new TextDecoder().decode(u8);
  #|}

///|
extern "js" fn bytes_of_text(rt : @core.Any, s : String) -> @core.Any =
  #|(rt, s) => {
  #|  const u8 = new TextEncoder().encode(s);
  #|  const b = rt.bytes_new(u8.length);
  #|  for (let i = 0; i < u8.length; i++) rt.bytes_set(b, i, u8[i]);
  #|  return b;
  #|}

///|
/// A `tg_bytes` as MoonBit `Bytes`, and back.
///
/// NO BASE64 either way. It was there because JSON has no shape for a byte
/// string; there is no JSON here, so a byte is a byte.
extern "js" fn blob_of(rt : @core.Any, b : @core.Any) -> Bytes =
  #|(rt, b) => {
  #|  const n = rt.bytes_len(b);
  #|  const u8 = new Uint8Array(n);
  #|  for (let i = 0; i < n; i++) u8[i] = rt.bytes_at(b, i);
  #|  return u8;
  #|}

///|
extern "js" fn bytes_of_blob(rt : @core.Any, v : Bytes) -> @core.Any =
  #|(rt, v) => {
  #|  const u8 = new Uint8Array(v);
  #|  const b = rt.bytes_new(u8.length);
  #|  for (let i = 0; i < u8.length; i++) rt.bytes_set(b, i, u8[i]);
  #|  return b;
  #|}

///|
/// An `i64` as text, and back.
///
/// Through a STRING on purpose. A wasm `i64` surfaces in JS as a `BigInt`, and
/// a `BigInt` is not a number MoonBit's js target will take — so the two ends
/// agree on the one spelling both can read exactly. It is what JSON did here
/// too, and it is the one place this codec keeps a text form.
extern "js" fn i64_text(v : @core.Any) -> String =
  #|(v) => String(v)

///|
extern "js" fn of_i64_text(
  rt : @core.Any,
  name : String,
  s : String,
) -> @core.Any =
  #|(rt, name, s) => rt[name](BigInt(s))

///|
/// A one-argument runtime call, and its two- and three-argument siblings.
///
/// `@core.Any::_call` would do all of these, and does them by name lookup plus
/// apply per call. These are the same thing written once, and a value codec is
/// the hot path of every render.
extern "js" fn rt1(rt : @core.Any, name : String, a : @core.Any) -> @core.Any =
  #|(rt, name, a) => rt[name](a)

///|
extern "js" fn rt2(
  rt : @core.Any,
  name : String,
  a : @core.Any,
  b : @core.Any,
) -> @core.Any =
  #|(rt, name, a, b) => rt[name](a, b)

///|
extern "js" fn rt3(
  rt : @core.Any,
  name : String,
  a : @core.Any,
  b : @core.Any,
  c : @core.Any,
) -> @core.Any =
  #|(rt, name, a, b, c) => rt[name](a, b, c)

///|
extern "js" fn rt4(
  rt : @core.Any,
  name : String,
  a : @core.Any,
  b : @core.Any,
  c : @core.Any,
  d : @core.Any,
) -> @core.Any =
  #|(rt, name, a, b, c, d) => rt[name](a, b, c, d)

///|
/// `mk_instant`, whose seconds are an `i64` and therefore a `BigInt`.
extern "js" fn mk_instant(
  rt : @core.Any,
  secs : String,
  nanos : Int,
) -> @core.Any =
  #|(rt, secs, nanos) => rt.mk_instant(BigInt(secs), nanos)

///|
extern "js" fn rt5(
  rt : @core.Any,
  name : String,
  a : @core.Any,
  b : @core.Any,
  c : @core.Any,
  d : @core.Any,
  e : @core.Any,
) -> @core.Any =
  #|(rt, name, a, b, c, d, e) => rt[name](a, b, c, d, e)

///|
extern "js" fn rt0(rt : @core.Any, name : String) -> @core.Any =
  #|(rt, name) => rt[name]()

///|
extern "js" fn arr_len(a : @core.Any) -> Int =
  #|(a) => a.length

///|
extern "js" fn arr_at(a : @core.Any, i : Int) -> @core.Any =
  #|(a, i) => a[i]
