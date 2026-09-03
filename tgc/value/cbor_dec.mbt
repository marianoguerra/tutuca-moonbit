// CBOR decoding.
//
// It reads what `to_cbor` writes, and it reads what anything else writing this
// profile writes — a decoder that only accepts its own encoder's output is a
// checksum, not a format. So non-shortest integer heads are ACCEPTED on the way
// in (they mean the same number) while only shortest is ever written, which is
// the usual liberal/conservative split and the one place it belongs.
//
// Trailing bytes are refused. A decoder that stops at the end of the first
// value has read a different message from the one that was sent, and saying so
// is cheaper than the bug that follows from not saying so.

///|
pub fn of_cbor(b : Bytes) -> TVal raise CodecError {
  let st = { bytes: b, pos: 0, }
  let v = dec(st, "")
  if st.pos != b.length() {
    raise Trailing(at=st.pos)
  }
  v
}

///|
priv struct Cursor {
  bytes : Bytes
  mut pos : Int
}

///|
fn Cursor::byte(self : Cursor, want : String) -> Int raise CodecError {
  if self.pos >= self.bytes.length() {
    raise Truncated(want~, at=self.pos)
  }
  let b = self.bytes[self.pos].to_int()
  self.pos = self.pos + 1
  b
}

///|
fn dec(st : Cursor, at : String) -> TVal raise CodecError {
  let start = st.pos
  let initial = st.byte("a value")
  let major = initial / 32
  let minor = initial % 32
  match major {
    0 => TInt(arg_as_int64(st, minor, start))
    1 => TInt(-1L - arg_as_int64(st, minor, start))
    2 => TBin(read_bytes(st, minor, start))
    3 => TStr(read_text(st, minor, start))
    4 => {
      let n = arg_len(st, minor, start)
      let items = []
      for i in 0..<n {
        items.push(dec(st, "\{at}/\{i}"))
      }
      TList(items)
    }
    5 => {
      let n = arg_len(st, minor, start)
      let entries = []
      let seen = @set.Set([])
      for _ in 0..<n {
        let kpos = st.pos
        let k = match dec(st, at) {
          TStr(s) => s
          other =>
            // A non-string key is legal CBOR and has no place in this format:
            // tutuca's maps are keyed by name, and a reader that met an integer
            // key would have to invent a spelling for it.
            raise BadCbor(
              why="a map key here must be text, and this is a \{kind_word(other)}",
              at=kpos,
            )
        }
        if seen.contains(k) {
          raise DuplicateKey(key=k, at="byte \{kpos}")
        }
        seen.add(k)
        entries.push((k, dec(st, "\{at}/\{k}")))
      }
      TMap(entries)
    }
    6 => dec_tagged(st, arg_as_int64(st, minor, start), start, at)
    7 =>
      match minor {
        20 => TBool(false)
        21 => TBool(true)
        22 => TNull
        // 23 is `undefined`. It is not null and this format has no third
        // absence, so it is refused rather than folded into one.
        23 =>
          raise BadCbor(
            why="`undefined` is not `null` and this format has only one absence",
            at=start,
          )
        25 =>
          raise BadCbor(
            why="a half-precision float; this format's number is a double",
            at=start,
          )
        26 =>
          raise BadCbor(
            why="a single-precision float; this format's number is a double",
            at=start,
          )
        27 => TNum(read_be64(st, start).reinterpret_as_double())
        _ => raise BadCbor(why="simple value \{minor}", at=start)
      }
    _ => raise BadCbor(why="major type \{major}", at=start)
  }
}

///|
fn dec_tagged(
  st : Cursor,
  tag : Int64,
  start : Int,
  at : String,
) -> TVal raise CodecError {
  if tag == TAG_EPOCH.to_int64() {
    let inner_at = st.pos
    return match dec(st, at) {
      TInt(secs) => TInstant(secs~, nanos=0)
      TExt(ext_tag~, payload~) if ext_tag == TAG_DECIMAL =>
        // The decimal-fraction pair, already unpacked by the tag-4 arm below.
        decimal_instant(payload, inner_at)
      other =>
        raise BadCbor(
          why="tag 1 must wrap an integer or a decimal fraction, not a \{kind_word(other)}",
          at=inner_at,
        )
    }
  }
  if tag == TAG_DECIMAL.to_int64() {
    // Carried as an Ext so that the tag-1 arm above can recognise it, and so
    // that a bare tag 4 outside a timestamp still round-trips rather than being
    // dropped.
    let inner = dec(st, at)
    return TExt(ext_tag=TAG_DECIMAL, payload=inner)
  }
  if tag == TAG_COMP.to_int64() {
    let inner_at = st.pos
    return match dec(st, at) {
      TList([TStr(module_), TStr(component), TBin(state)]) =>
        TComp({ module_, component, state, })
      _ =>
        raise BadCbor(
          why="tag \{TAG_COMP} must wrap [module, component, state]",
          at=inner_at,
        )
    }
  }
  if tag == TAG_EXT.to_int64() {
    let inner_at = st.pos
    return match dec(st, at) {
      TList([TInt(ext_tag), payload]) =>
        TExt(ext_tag=ext_tag.to_int(), payload~)
      _ =>
        raise BadCbor(
          why="tag \{TAG_EXT} must wrap [tag, payload]",
          at=inner_at,
        )
    }
  }
  raise BadCbor(
    why="tag \{tag}; this profile defines \{TAG_EPOCH}, \{TAG_DECIMAL}, \{TAG_COMP} and \{TAG_EXT}",
    at=start,
  )
}

///|
/// `[-9, n]` — nanoseconds since the epoch as one exact integer, split back into
/// the `secs` / `nanos` pair with `nanos` always non-negative.
fn decimal_instant(payload : TVal, at : Int) -> TVal raise CodecError {
  guard payload is TList([TInt(exponent), TInt(mantissa)]) && exponent == -9L else {
    raise BadCbor(
      why="a timestamp's decimal fraction is [-9, nanoseconds]",
      at~,
    )
  }
  let billion = 1_000_000_000L
  let mut secs = mantissa / billion
  let mut nanos = mantissa % billion
  if nanos < 0L {
    // Truncating division rounds toward zero, so a negative instant lands one
    // second late with a negative remainder. `nanos` is defined non-negative.
    secs = secs - 1L
    nanos = nanos + billion
  }
  TInstant(secs~, nanos=nanos.to_int())
}

///|
/// The head's argument. Non-shortest forms are accepted: they denote the same
/// number, and refusing them would reject valid CBOR nobody wrote wrong.
fn arg_as_int64(
  st : Cursor,
  minor : Int,
  start : Int,
) -> Int64 raise CodecError {
  if minor < 24 {
    return minor.to_int64()
  }
  let width = match minor {
    24 => 1
    25 => 2
    26 => 4
    27 => 8
    31 =>
      raise BadCbor(
        why="an indefinite length; this profile is definite-length throughout",
        at=start,
      )
    _ => raise BadCbor(why="reserved additional information \{minor}", at=start)
  }
  let mut acc = 0L
  for _ in 0..<width {
    acc = (acc << 8) | st.byte("a length or value").to_int64()
  }
  acc
}

///|
fn arg_len(st : Cursor, minor : Int, start : Int) -> Int raise CodecError {
  let n = arg_as_int64(st, minor, start)
  // A length is a count of items still to come, so one that cannot fit in the
  // input cannot be right; saying so here turns a would-be allocation of
  // gigabytes into a message.
  guard n >= 0L && n <= (st.bytes.length() - st.pos).to_int64() else {
    raise BadCbor(
      why="a length of \{n} with \{st.bytes.length() - st.pos} bytes left",
      at=start,
    )
  }
  n.to_int()
}

///|
fn read_bytes(st : Cursor, minor : Int, start : Int) -> Bytes raise CodecError {
  let n = arg_len(st, minor, start)
  let out = Array::make(n, b'\x00')
  for i in 0..<n {
    out[i] = st.byte("a byte string").to_byte()
  }
  Bytes::from_array(out)
}

///|
fn read_text(st : Cursor, minor : Int, start : Int) -> String raise CodecError {
  let raw = read_bytes(st, minor, start)
  @encoding.decoder(UTF8).decode(raw[:]) catch {
    _ => raise BadCbor(why="a text string that is not valid UTF-8", at=start)
  }
}

///|
fn read_be64(st : Cursor, start : Int) -> Int64 raise CodecError {
  let mut acc = 0L
  for _ in 0..<8 {
    acc = (acc << 8) | st.byte("a double").to_int64()
  }
  ignore(start)
  acc
}

///|
/// What a value IS, for a message about what it should have been.
fn kind_word(v : TVal) -> String {
  match v {
    TNull => "null"
    TBool(_) => "boolean"
    TNum(_) => "number"
    TInt(_) => "integer"
    TStr(_) => "text"
    TBin(_) => "byte string"
    TInstant(..) => "timestamp"
    TList(_) => "list"
    TMap(_) => "map"
    TFunc => "function"
    TComp(_) => "component"
    TExt(..) => "extension value"
  }
}
