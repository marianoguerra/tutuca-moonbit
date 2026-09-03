// READONLY by convention: the public data types plus `declare` stubs. The
// implementations are in `cbor_enc.mbt`, `cbor_dec.mbt`, `json_enc.mbt`,
// `json_dec.mbt` and `instant.mbt`.

///|
/// The canonical value, host side — one arm per `Tag` in `tgc/abi`, in the same
/// order, because a mirror that has drifted is worse than no mirror.
///
/// Three arms are new against `core.Value`, and each earns its place:
///
///   - `TInt` because CBOR and the GC types both have a 64-bit integer and the
///     current WIT concedes what its absence costs ("a 64-bit id is a `str`").
///   - `TBin` because a component that holds bytes should not have to spell them
///     as base64 in a string field and hope everyone agrees.
///   - `TInstant` because "when" is the one fact a sandboxed guest cannot
///     compute and therefore always receives from somewhere else — a wire type
///     it can be received AS is the difference between one representation and
///     an argument per host.
pub(all) enum TVal {
  TNull
  TBool(Bool)
  TNum(Double)
  TInt(Int64)
  TStr(String)
  TBin(Bytes)
  /// Nanoseconds since the Unix epoch, split so that neither half rounds:
  /// `secs` is whole seconds (negative before 1970) and `nanos` is always in
  /// `0 ..< 1_000_000_000`, so a time before the epoch has a NEGATIVE `secs`
  /// and a positive `nanos`, the way `timespec` does it. One canonical spelling
  /// per instant, which is what lets two of them be compared as a pair.
  TInstant(secs~ : Int64, nanos~ : Int)
  TList(Array[TVal])
  /// Insertion-ordered, and that is semantic rather than incidental:
  /// `core.Value::Map` is MoonBit's `Map` and the renderer's `@each` walks a
  /// map field in insertion order, so an encoding that sorted keys would
  /// re-order a view.
  TMap(Array[(String, TVal)])
  /// A function reference. It has no host-side payload because there is nothing
  /// to mirror — the arm exists so that encoding one is a REFUSAL with a reason
  /// rather than an arm the codec silently does not have.
  TFunc
  TComp(CompRef)
  /// The one extension point. A reader that does not know `ext_tag` still
  /// carries the value intact, which is the whole point of having it.
  TExt(ext_tag~ : Int, payload~ : TVal)
} derive(Eq, Debug)

///|
/// A component instance as it travels by VALUE — in bytes, between processes,
/// into storage — rather than by reference.
///
/// By reference it is a `(ref tg_inst)` and nothing here applies. This is what
/// is left when the reference cannot come along: who made it, what it was, and
/// the bytes that module answered from `persist`. Reconstituting one needs the
/// module; without it, a reader still knows what it is looking at, which is more
/// than a null would have told it.
pub(all) struct CompRef {
  module_ : String
  component : String
  state : Bytes
} derive(Eq, Debug)

///|
/// What went wrong, and where.
///
/// Every arm carries a position — a byte offset for CBOR, a JSON Pointer for
/// JSON — because "malformed" without a position is a bug report nobody can
/// act on, and both codecs are read by machines that wrote the input.
pub suberror CodecError {
  /// This value has no encoding in this format, and never will.
  NotEncodable(kind~ : String, why~ : String, at~ : String)
  /// The input ended inside a value.
  Truncated(want~ : String, at~ : Int)
  /// A CBOR major type or tag this profile does not define.
  BadCbor(why~ : String, at~ : Int)
  /// Bytes after a complete value. Not ignored: a decoder that stops early is
  /// a decoder that read a different message from the one that was sent.
  Trailing(at~ : Int)
  /// A `$`-tagged object whose type nobody defines.
  UnknownTagged(got~ : String, at~ : String)
  /// A `$`-tagged object whose payload is the wrong shape for its type.
  BadTagged(want~ : String, at~ : String)
  /// Base64 that is not base64.
  BadBase64(why~ : String, at~ : String)
  /// A timestamp that is not RFC 3339, or is but names an instant this format
  /// cannot hold.
  BadInstant(text~ : String, at~ : String)
  /// One key twice in one map. Refused rather than resolved: both "first wins"
  /// and "last wins" are guesses about what the writer meant.
  DuplicateKey(key~ : String, at~ : String)
}

///|
declare pub fn CodecError::message(self : CodecError) -> String

///|
/// `Show` is the message. An error that prints as its own explanation is one
/// nobody has to remember to call a method on.
pub impl Show for CodecError

///|
/// The tag this value carries on the wire.
declare pub fn TVal::tag(self : TVal) -> @abi.Tag

///|
/// A value prints as its own JSON — the spelling a person reading a failure
/// already knows. One that has no JSON says what it is instead.
pub impl Show for TVal

///|
pub impl Show for CompRef

///|
/// Encode to CBOR (RFC 8949).
///
/// The **ordered-CBOR** profile: canonical in every respect the standard names
/// except key ordering, which follows insertion rather than byte order. See
/// `TMap` for why. Raises `NotEncodable` for a `TFunc`.
declare pub fn to_cbor(v : TVal) -> Bytes raise CodecError

///|
/// Decode CBOR written by `to_cbor`, or by anything else that writes this
/// profile. Raises on trailing bytes.
declare pub fn of_cbor(b : Bytes) -> TVal raise CodecError

///|
/// Encode to JSON, `$`-tagged.
///
/// `null`, booleans, numbers, strings, arrays and objects are themselves. The
/// five arms JSON has no shape for become one-key-plus-payload objects under a
/// `"$"` discriminator, and an object whose OWN keys include `"$"` is escaped
/// the same way — without that rule the tagging is ambiguous, which is the
/// classic way this shape goes wrong.
///
/// Raises `NotEncodable` for a `TFunc`, the same as CBOR.
declare pub fn to_json(v : TVal) -> Json raise CodecError

///|
/// Decode `$`-tagged JSON.
///
/// **Not the inverse of `to_json` on numbers**, and deliberately so: a plain
/// JSON number decodes to `TNum`, because a JSON number is a double and
/// pretending otherwise past 2^53 would invent precision. A producer that needs
/// a `TInt` back writes `{"$":"int","v":"…"}`. CBOR is the encoding that does
/// not have this asymmetry; this one is for interchange.
declare pub fn of_json(j : Json) -> TVal raise CodecError

///|
/// An instant as RFC 3339, always UTC, always `Z`.
///
/// Sub-second digits are written in groups of three — milliseconds,
/// microseconds, nanoseconds — and trailing groups of zeros are dropped, so a
/// whole second has no fraction at all. That is a spelling rule rather than a
/// precision one: the value round-trips exactly either way.
declare pub fn instant_to_rfc3339(secs : Int64, nanos : Int) -> String

///|
/// Read an RFC 3339 timestamp. `Z` and a numeric offset are both accepted; the
/// result is the instant, so the offset is applied and not kept.
declare pub fn instant_of_rfc3339(
  text : String,
) -> (Int64, Int) raise CodecError
