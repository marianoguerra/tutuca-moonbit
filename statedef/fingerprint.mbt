// The schema's structural fingerprint.
//
// Over SHAPE, not over source text: renaming the state declaration changes it,
// reindenting the block does not. What it is for is noticing that a stored
// state can no longer be read back — a hot swap across a fingerprint change
// has to migrate rather than reinterpret.
//
// A DECLARED name is hashed normalized, because its spelling is not part of
// the shape: `Nudge` and `nudge` declare one message with one runtime name and
// one variant (`names.mbt`), so a schema that only restyled its case names must
// hash the same. A name a field REFERS to is not — a `StateTy` carries the
// spelling the reference was written in, and recasing a type renames something
// the state itself mentions.
//

///|
/// A stable structural fingerprint of the whole schema.
///
/// Over SHAPE, not over source text: renaming the state declaration changes it,
/// reindenting the block does not. What it is for is noticing that a stored
/// state can no longer be read back — a hot swap across a fingerprint change
/// has to migrate rather than reinterpret.
///
/// Declared names go in normalized, not as written: recasing `Nudge` to
/// `nudge` leaves one message with the same runtime name and the same variant,
/// so it is not a shape change. A type name a FIELD refers to is not
/// normalized — see the header.
pub fn fingerprint(defs : Array[StateDef]) -> String {
  let sb = StringBuilder()
  for def in defs {
    sb.write_string("i:\{upper_name(def.source_name)};")
    for f in def.fields {
      sb.write_string("f:\{f.name}:\{f.ty.show_source()};")
    }
    for t in def.types {
      sb.write_string("t:\{upper_name(t.source_name)}:")
      match t.kind {
        URecord(fs) =>
          for f in fs {
            sb.write_string("\{f.name}=\{f.ty.show_source()},")
          }
        UEnum(cs) =>
          for c in cs {
            sb.write_string("\{c.1},")
          }
        UVariant(cs) =>
          for c in cs {
            sb.write_string(
              "\{c.name}(\{c.payload.map(p => p.show_source()).join("|")}),",
            )
          }
      }
      sb.write_string(";")
    }
    // `n` for the intents rather than `i`, which the state name above already
    // spends. The bucket a name sits in IS part of the shape — a name that
    // moved from `receive` to `intent` answers a different channel — so the
    // two are hashed under distinct letters.
    for
      pair in [
        ("r", def.receive),
        ("n", def.intent),
        ("x", def.express_message),
        ("y", def.express_intent),
      ] {
      for m in pair.1 {
        sb.write_string(
          "\{pair.0}:\{m.name}(\{m.payload.map(p => p.show_source()).join("|")});",
        )
      }
    }
    for id in def.implements {
      sb.write_string("p:\{id};")
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
  let sb = StringBuilder()
  for i in 0..<16 {
    let shift = (15 - i) * 4
    sb.write_char(digits[((v >> shift) & 0xfUL).to_int()])
  }
  sb.to_string()
}
