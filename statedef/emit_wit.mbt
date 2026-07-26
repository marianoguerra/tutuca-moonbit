// The schema back out as WIT, and its fingerprint.
//
// Two consumers, both outside MoonBit. `to_wit` writes a self-contained
// document for `wit-bindgen`, so a polyglot guest (guests/rust-counter)
// consumes the same contract the MoonBit side generated from. `fingerprint`
// is the structural identity of that contract, which is what lets a hot swap
// or a CI run notice that a schema changed shape rather than merely moved.
//
// `to_wit` LOWERS the markers. `any`, `text-set` and a component slot are
// tutuca's readings of shapes WIT does have; external tooling knows nothing
// about them, so they go out in their structural form. The prelude is an
// input convenience, never part of the shipped contract.

///|
/// The schema as a self-contained WIT document.
///
/// `pkg` names the package — the module supplies it, since a view file's
/// block deliberately carries no package of its own.
pub fn to_wit(defs : Array[StateDef], pkg? : String = "tutuca:state") -> String {
  let out = StringBuilder::new()
  out.write_string(
    "// GENERATED from the tutuca/state block — DO NOT EDIT.\n",
  )
  out.write_string("//\n")
  out.write_string(
    "// Markers are LOWERED here: `any` and a component slot become the host's\n" +
    "// dynamic value, an open set becomes list<string>, an ordered map becomes\n" +
    "// list<tuple<string, _>>. External tooling cannot know tutuca's readings.\n",
  )
  out.write_string("package \{pkg};\n")
  for def in defs {
    out.write_string("\ninterface \{def.wit_name} {\n")
    for ty in def.types {
      emit_wit_type(def, ty, out)
    }
    emit_wit_bucket(def, "receive", def.receive, out)
    emit_wit_bucket(def, "bubble", def.bubble, out)
    emit_wit_bucket(def, "response", def.response, out)
    out.write_string("  record state {\n")
    for f in def.fields {
      out.write_string("    \{f.wit_name}: \{lowered(def, f.ty)},\n")
    }
    out.write_string("  }\n}\n")
  }
  out.to_string()
}

///|
fn emit_wit_type(def : StateDef, ty : UserTy, out : StringBuilder) -> Unit {
  match ty.kind {
    URecord(fs) => {
      if fs.is_empty() {
        return // a transparent alias; it named a marker and nothing more
      }
      out.write_string("  record \{ty.wit_name} {\n")
      for f in fs {
        out.write_string("    \{f.wit_name}: \{lowered(def, f.ty)},\n")
      }
      out.write_string("  }\n")
    }
    UEnum(cs) =>
      out.write_string(
        "  enum \{ty.wit_name} { " + cs.map(c => c.0).join(", ") + " }\n",
      )
    UFlags(fs) =>
      out.write_string(
        "  flags \{ty.wit_name} { " + fs.map(f => f.0).join(", ") + " }\n",
      )
    UVariant(cs) => {
      out.write_string("  variant \{ty.wit_name} {\n")
      for c in cs {
        out.write_string("    \{c.wit_name}\{payload_wit(def, c.payload)},\n")
      }
      out.write_string("  }\n")
    }
  }
}

///|
fn emit_wit_bucket(
  def : StateDef,
  name : String,
  msgs : Array[MsgDef],
  out : StringBuilder,
) -> Unit {
  if msgs.is_empty() {
    return
  }
  out.write_string("  variant \{name} {\n")
  for m in msgs {
    out.write_string("    \{m.wit_name}\{payload_wit(def, m.payload)},\n")
  }
  out.write_string("  }\n")
}

///|
fn payload_wit(def : StateDef, payload : Array[StateTy]) -> String {
  if payload.is_empty() {
    ""
  } else if payload.length() == 1 {
    "(" + lowered(def, payload[0]) + ")"
  } else {
    "(tuple<" + payload.map(p => lowered(def, p)).join(", ") + ">)"
  }
}

///|
/// A type in its structural WIT form, with every marker lowered.
fn lowered(def : StateDef, ty : StateTy) -> String {
  match ty {
    TBool => "bool"
    TInt(width~, signed~) =>
      (if signed { "s" } else { "u" }) + width.to_string()
    TFloat => "f64"
    TText => "string"
    TList(e) => "list<" + lowered(def, e) + ">"
    TTuple(ts) => "tuple<" + ts.map(t => lowered(def, t)).join(", ") + ">"
    TOption(e) => "option<" + lowered(def, e) + ">"
    TRecord(n) | TEnum(n) | TVariant(n) | TFlags(n) => n
    // An open set is a list of its members; WIT `flags` covers only the
    // closed case, and this one is open by definition.
    TSet => "list<string>"
    // Ordered, which is why it is not `map` — and `map` is what a consumer
    // would otherwise have to guess the ordering of.
    TOMap(v) => "list<tuple<string, " + lowered(def, v) + ">>"
    // The dyncomp boundary carries an instance as a host-assigned token, and
    // a dynamic value as its JSON text.
    TComp(_) => "u64"
    TAny => "string"
  }
}

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
