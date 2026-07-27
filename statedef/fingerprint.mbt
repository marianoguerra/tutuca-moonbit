// The schema's structural fingerprint.
//
// Over SHAPE, not over source text: renaming the WIT interface changes it,
// reindenting the block does not. What it is for is noticing that a stored
// state can no longer be read back — a hot swap across a fingerprint change
// has to migrate rather than reinterpret.
//
// `to_wit` used to live here, writing the schema back out as a self-contained
// WIT document with the markers lowered. Nothing consumed it: no `.wit` from
// statedef was ever checked in, `--wit` was passed by no build, and the guest
// trees under guests/ are hand-written against the dyncomp boundary contract
// rather than generated from one of these. It went, and `to_guest` with it.
// The fingerprint hashes `show_wit()` rather than the document, so it is
// unaffected.

///|
/// A stable structural fingerprint of the whole schema.
///
/// Over SHAPE, not over source text: renaming the WIT interface changes it,
/// reindenting the block does not. What it is for is noticing that a stored
/// state can no longer be read back — a hot swap across a fingerprint change
/// has to migrate rather than reinterpret.
pub fn fingerprint(defs : Array[StateDef]) -> String {
  let sb = StringBuilder::new()
  for def in defs {
    sb.write_string("i:\{def.wit_name};")
    for f in def.fields {
      sb.write_string("f:\{f.wit_name}:\{f.ty.show_wit()};")
    }
    for t in def.types {
      sb.write_string("t:\{t.wit_name}:")
      match t.kind {
        URecord(fs) =>
          for f in fs {
            sb.write_string("\{f.wit_name}=\{f.ty.show_wit()},")
          }
        UEnum(cs) | UFlags(cs) =>
          for c in cs {
            sb.write_string("\{c.0},")
          }
        UVariant(cs) =>
          for c in cs {
            sb.write_string(
              "\{c.wit_name}(\{c.payload.map(p => p.show_wit()).join("|")}),",
            )
          }
      }
      sb.write_string(";")
    }
    for pair in [("r", def.receive), ("b", def.bubble), ("p", def.response)] {
      for m in pair.1 {
        sb.write_string(
          "\{pair.0}:\{m.wit_name}(\{m.payload.map(p => p.show_wit()).join("|")});",
        )
      }
    }
  }
  hex64(fnv1a(sb.to_string()))
}

///|
/// FNV-1a over the shape string. Not cryptographic and does not need to be:
/// it distinguishes schemas that a human wrote, not ones an attacker did.
fn fnv1a(s : String) -> UInt64 {
  let mut h : UInt64 = 0xcbf29ce484222325UL
  for c in s.to_array() {
    h = (h ^ c.to_int().reinterpret_as_uint().to_uint64()) * 0x100000001b3UL
  }
  h
}

///|
fn hex64(v : UInt64) -> String {
  let digits = "0123456789abcdef".to_array()
  let sb = StringBuilder::new()
  for i in 0..<16 {
    let shift = (15 - i) * 4
    sb.write_char(digits[((v >> shift) & 0xfUL).to_int()])
  }
  sb.to_string()
}
