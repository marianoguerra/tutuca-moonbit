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
// hash the same. A name a field REFERS to is not — a `@tutuca.Ty` carries the
// spelling the reference was written in, and recasing a type renames something
// the state itself mentions.
//
// RULES ARE NOT HASHED, and that is a decision rather than an oversight. What
// this digest is for is noticing that a stored state can no longer be READ
// BACK; adding, changing or removing a `pred` or an `invariant` leaves every
// stored instance exactly as readable as it was. Hashing one would force a
// migration for a change that needs none — and it would make tightening a rule,
// the thing an author should be able to do freely, the most expensive edit in
// the block.
//
// A `where` IS NOT HASHED either, by that same argument rather than by
// analogy. A domain narrows which values are legal; it does not change how a
// stored one is READ. A state that violates a newly added `where` decodes
// exactly as it always did — what changes is that the next write to that field
// is refused, which is the clause working, not a state that can no longer be
// understood. Tightening a domain should cost what tightening a rule costs.
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
    for p in def.properties {
      let visibility = if p.public_ { "pub" } else { "priv" }
      let access = if p.writable { "w" } else { "r" }
      sb.write_string(
        "a:\{p.name}:\{p.ty.show_source()}:\{visibility}:\{access};",
      )
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
  @tutuca.fnv1a_hex(sb.to_string())
}
