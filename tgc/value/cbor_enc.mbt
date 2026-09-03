// CBOR encoding — RFC 8949, the "ordered" profile.
//
// Canonical in every respect the standard names except one: map keys keep
// INSERTION order rather than being sorted by their encoding. That is not
// laziness about determinism, it is the type: tutuca's maps are ordered and a
// view iterating one renders in that order, so sorting here would silently
// re-order a page. Everything else — shortest-form integer heads, definite
// lengths, no indefinite-length strings — follows the canonical rules, so two
// encoders that agree on a value produce the same bytes.
//
// Tags are STANDARD wherever a standard one exists (1 for an epoch time, 4 for
// a decimal fraction). The two that have none are in the first-come-first-served
// range and are documented here as what they are.

///|
/// The CBOR tag for an instant: RFC 8949 tag 1, "epoch-based date/time".
const TAG_EPOCH : Int = 1

///|
/// RFC 8949 tag 4, "decimal fraction": `[exponent, mantissa]`. Sub-second
/// instants are written as tag 1 wrapping one of these, which is exactly the
/// composition the standard describes rather than a convention invented here.
const TAG_DECIMAL : Int = 4

///|
/// A component instance carried BY VALUE: `[module, component, state]`.
/// First-come-first-served range; it means nothing to a reader that has not
/// been told, which is honest — a reader that has not been told cannot
/// reconstitute one either.
const TAG_COMP : Int = 40001

///|
/// An extension value: `[ext_tag, payload]`.
const TAG_EXT : Int = 40002

///|
pub fn to_cbor(v : @tutuca.Value) -> Bytes raise CodecError {
  let out = []
  enc(out, v, "")
  Bytes::from_array(out)
}

///|
fn enc(
  out : Array[Byte],
  v : @tutuca.Value,
  at : String,
) -> Unit raise CodecError {
  match v {
    Null => out.push(0xf6)
    Bool(false) => out.push(0xf4)
    Bool(true) => out.push(0xf5)
    // Major 7 / 27: a double, always. Not narrowed to a float: tutuca's number
    // IS a double, and an encoder that sometimes narrows makes the byte length
    // depend on the value, which is a difference two encoders can disagree on.
    Num(n) => {
      out.push(0xfb)
      be64(out, n.reinterpret_as_int64())
    }
    Int(i) =>
      if i >= 0L {
        head(out, 0, i.reinterpret_as_uint64())
      } else {
        // Major 1 encodes -1-n, so the argument is the magnitude minus one.
        head(out, 1, (-1L - i).reinterpret_as_uint64())
      }
    Str(s) => {
      let bytes = utf8(s)
      head(out, 3, bytes.length().to_int64().reinterpret_as_uint64())
      for b in bytes {
        out.push(b)
      }
    }
    Bin(b) => {
      head(out, 2, b.length().to_int64().reinterpret_as_uint64())
      for i in 0..<b.length() {
        out.push(b[i])
      }
    }
    Instant(secs~, nanos~) => {
      head(out, 6, TAG_EPOCH.to_int64().reinterpret_as_uint64())
      if nanos == 0 {
        enc(out, Int(secs), at)
      } else {
        // tag(4) [ -9, secs*1e9 + nanos ]. Exact: an integer of nanoseconds
        // rather than a double of seconds, which past 2^53 nanoseconds — about
        // fourteen weeks — would start losing the low digits.
        head(out, 6, TAG_DECIMAL.to_int64().reinterpret_as_uint64())
        head(out, 4, 2UL)
        enc(out, Int(-9L), at)
        enc(out, Int(secs * 1_000_000_000L + nanos.to_int64()), at)
      }
    }
    List(items) => {
      head(out, 4, items.length().to_int64().reinterpret_as_uint64())
      for i, item in items {
        enc(out, item, "\{at}/\{i}")
      }
    }
    // A MoonBit `Map` cannot hold one key twice, so the duplicate check that
    // belongs on the DECODE side has nothing to do here.
    Map(m) => {
      head(out, 5, m.length().to_int64().reinterpret_as_uint64())
      for k, val in m {
        enc(out, Str(k), at)
        enc(out, val, "\{at}/\{k}")
      }
    }
    Fn(_) =>
      raise NotEncodable(
        kind="function",
        why="a function is code in one module's address space; " +
          "there is nothing to write down that another process could call",
        at~,
      )
    // The wire HAS a case for an instance by value (tag 40001, carrying
    // `[module, component, state]`). What it needs is the module that made it
    // and the bytes it persists, which is a registry's answer rather than a
    // codec's — so this refuses rather than writing a null a reader would take
    // for "there was nothing there".
    Obj(_) =>
      raise NotEncodable(
        kind="component instance",
        why="an instance by value needs the module that made it and the bytes " +
          "it persists; a value codec has neither. Project it through the host " +
          "first (tgc/persist writes exactly those three things)",
        at~,
      )
  }
}

///|
/// A major type and its argument, in the SHORTEST form that holds it. Shortest
/// is what makes the encoding canonical: with a choice of widths, two encoders
/// that agree on the value can still disagree on the bytes.
fn head(out : Array[Byte], major : Int, arg : UInt64) -> Unit {
  let m = (major * 32).to_byte()
  if arg < 24UL {
    out.push(m | arg.to_byte())
  } else if arg <= 0xffUL {
    out.push(m | b'\x18')
    out.push(arg.to_byte())
  } else if arg <= 0xffffUL {
    out.push(m | b'\x19')
    be(out, arg, 2)
  } else if arg <= 0xffff_ffffUL {
    out.push(m | b'\x1a')
    be(out, arg, 4)
  } else {
    out.push(m | b'\x1b')
    be(out, arg, 8)
  }
}

///|
fn be(out : Array[Byte], v : UInt64, width : Int) -> Unit {
  for i in 0..<width {
    let shift = (width - 1 - i) * 8
    out.push(((v >> shift) & 0xffUL).to_byte())
  }
}

///|
fn be64(out : Array[Byte], v : Int64) -> Unit {
  be(out, v.reinterpret_as_uint64(), 8)
}

///|
/// UTF-8 bytes of a MoonBit string.
///
/// This is where the format's encoding choice meets the host: the wire and the
/// GC types are UTF-8, MoonBit strings are UTF-16, and the conversion happens
/// at the boundary rather than at every field.
fn utf8(s : String) -> Array[Byte] {
  let bytes = @encoding.encode(UTF8, s)
  let out = []
  for i in 0..<bytes.length() {
    out.push(bytes[i])
  }
  out
}
