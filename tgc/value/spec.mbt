// READONLY by convention: the public types plus `declare` stubs. The
// implementations are in `cbor_enc.mbt`, `cbor_dec.mbt` and `error.mbt`.

///|
/// What went wrong, and where.
///
/// Every arm carries a position, because "malformed" without one is a bug
/// report nobody can act on and the thing that wrote the input is usually a
/// machine that could write it again.
pub suberror CodecError {
  /// This value has no encoding in this format, and never will.
  NotEncodable(kind~ : String, why~ : String, at~ : String)
  /// The input ended inside a value.
  Truncated(want~ : String, at~ : Int)
  /// A CBOR major type or tag this profile does not define.
  BadCbor(why~ : String, at~ : Int)
  /// Bytes after a complete value. Not ignored: a decoder that stops early is a
  /// decoder that read a different message from the one that was sent.
  Trailing(at~ : Int)
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
/// Encode a `Value` to CBOR (RFC 8949).
///
/// The **ordered-CBOR** profile: canonical in every respect the standard names
/// except key ordering, which follows insertion rather than byte order.
/// `Value::Map` is MoonBit's `Map` and the renderer's `@each` walks a map field
/// in insertion order, so an encoding that sorted keys would re-order a view.
///
/// Raises `NotEncodable` for a `Fn` and for an `Obj`. Neither is a gap: a
/// function is code in one module's address space, and a component instance by
/// VALUE needs the module that made it — which is a registry's answer, not a
/// codec's. The wire has a case for one (tag 40001) so a producer holding those
/// three things can write it; this cannot produce them.
declare pub fn to_cbor(v : @tutuca.Value) -> Bytes raise CodecError

///|
/// Decode CBOR written by `to_cbor`, or by anything else writing this profile.
/// Raises on trailing bytes.
declare pub fn of_cbor(b : Bytes) -> @tutuca.Value raise CodecError

///|
/// The key a decoded component instance lands under.
///
/// Tag 40001 carries `[module, component, state]` and `core.Value` has no arm
/// for a foreign instance, so it lands as a `Map` under these three keys rather
/// than as a null. A reader that has the module can rebuild it; one that does
/// not still knows what it was looking at, which is more than a null would have
/// said.
pub let comp_module_key : String = "$module"

///|
pub let comp_component_key : String = "$component"

///|
pub let comp_state_key : String = "$state"

///|
/// The key an extension value lands under, for the same reason.
///
/// `tg_ext` is the format's ONE extension point; `core.Value` has no arm for it
/// because a host that does not know a tag has nothing to do with it but carry
/// it. This is that carrying.
pub let ext_tag_key : String = "$ext"
