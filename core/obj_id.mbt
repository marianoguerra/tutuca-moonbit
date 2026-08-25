// The instance fingerprint (see `ObjId` in spec.mbt): a structural hash of
// what an instance was created with, plus a revision the successors bump.
//
// It exists to key the render cache. That is why it does not need to be
// unique, and why it is not a counter: a bucket collision costs a miss, and
// the cache validates the value it stored by physical identity anyway. Nothing
// central has to be consulted to mint one, so a component loaded at runtime
// brings everything it needs to make its own.
//
// The FNV-1a here is a second copy of `statedef/fingerprint.mbt`'s. They hash
// different things — that one hashes a schema's SHAPE at generation time, this
// one hashes a value at runtime — and `core` is the runtime package, so an
// import edge to a build-time one is not worth eight lines.

///|
const FNV_OFFSET : UInt64 = 0xcbf29ce484222325UL

///|
const FNV_PRIME : UInt64 = 0x100000001b3UL

///|
fn mix_byte(h : UInt64, b : Int) -> UInt64 {
  (h ^ b.reinterpret_as_uint().to_uint64()) * FNV_PRIME
}

///|
fn mix_u64(h : UInt64, v : UInt64) -> UInt64 {
  let mut h = h
  for i in 0..<8 {
    h = mix_byte(h, ((v >> (i * 8)) & 0xffUL).to_int())
  }
  h
}

///|
fn mix_str(h : UInt64, s : String) -> UInt64 {
  let mut h = h
  for c in s {
    h = mix_byte(h, c.to_int())
  }
  h
}

///|
/// Mix one value into the running hash.
///
/// The rule that keeps this cheap: an `Obj` contributes its OWN origin and
/// never its contents. A parent's fingerprint therefore costs a pass over the
/// parent's own fields — where each nested instance is one `UInt64` — instead
/// of a walk of the whole subtree below it. Break that rule and creating the
/// root of a deep tree becomes quadratic in the tree.
///
/// Each shape mixes a distinct tag first, so `Str("1")` and `Num(1)` cannot
/// collide by mixing the same bytes.
fn mix_value(h : UInt64, v : Value) -> UInt64 {
  match v {
    Null => mix_byte(h, 0)
    Bool(b) => mix_byte(mix_byte(h, 1), if b { 1 } else { 0 })
    Num(n) => mix_u64(mix_byte(h, 2), n.reinterpret_as_uint64())
    Str(s) => mix_str(mix_byte(h, 3), s)
    List(a) => {
      let mut h = mix_byte(h, 4)
      for x in a {
        h = mix_value(h, x)
      }
      h
    }
    Map(m) => mix_named(mix_byte(h, 5), m)
    // A closure has no structure to look at, so every Fn mixes the same. Two
    // components differing only in a handler get the same fingerprint, which
    // is a shared bucket and nothing worse.
    Fn(_) => mix_byte(h, 6)
    Obj(o) =>
      match o.obj_identity() {
        Some(id) => mix_u64(mix_byte(h, 7), id.origin)
        None => mix_byte(h, 8)
      }
  }
}

///|
/// Mix a name -> value map ORDER-INDEPENDENTLY: each entry is hashed from a
/// fresh seed over its own name and value, and the results are folded with
/// xor. Two instances with the same fields must get the same fingerprint
/// whatever order their maps happen to iterate in, and the name is inside each
/// entry's hash so two fields cannot cancel by swapping values.
fn mix_named(h : UInt64, m : Map[String, Value]) -> UInt64 {
  let mut acc = h
  for name, v in m {
    acc = acc ^ mix_value(mix_str(FNV_OFFSET, name), v)
  }
  acc
}

///|
pub fn ObjId::of(fingerprint : String, fields : Map[String, Value]) -> ObjId {
  { origin: mix_named(mix_str(FNV_OFFSET, fingerprint), fields), rev: 0 }
}

///|
pub fn ObjId::next(self : ObjId) -> ObjId {
  { ..self, rev: self.rev + 1 }
}

///|
pub fn ObjId::to_hex(self : ObjId) -> String {
  let digits = "0123456789abcdef".to_array()
  let sb = StringBuilder()
  for i in 0..<16 {
    sb.write_char(digits[((self.origin >> ((15 - i) * 4)) & 0xfUL).to_int()])
  }
  sb.to_string()
}
