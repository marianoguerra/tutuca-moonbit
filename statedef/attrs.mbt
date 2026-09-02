// `#[…]` field attributes, resolved.
//
// The attribute list is parsed and kept as written (`FieldDef.attrs`), and for
// a long time it stayed there: `statedef` knew a field carried `min = 0` and
// had no opinion about what a minimum MEANT, and the layer that did have one
// spoke a second vocabulary — `@jsonschema.Constraint`, eight optional members
// that said seven of the same things a `where` clause already said.
//
// There is one vocabulary now, `@tutuca.Domain`, so an attribute has somewhere
// to resolve TO. This is that resolution and the only one: what `#[max = 10]`
// means is the same thing `where n <= 10` means, and a reader — a JSON Schema,
// a generated form, the runtime's own door check — asks the domain rather than
// the spelling.
//
// `#[required]` and `#[default = …]` stay out of it, and for the reason the
// merge made visible: a domain says which values are ADMITTED. Requiring a
// field is a statement about the CONSTRUCTOR, and a default admits nothing —
// it picks one.

///|
/// The domains a field's `#[…]` attributes state.
///
/// An attribute this does not know is ignored rather than refused. The list is
/// open by design — it is where a schema says things `statedef` has no model
/// for — and a reader that cannot use one has not been lied to.
pub fn FieldDef::attr_domains(self : FieldDef) -> Array[@tutuca.Domain] {
  let out : Array[@tutuca.Domain] = []
  for a in self.attrs {
    let (name, v) = a
    match (name, v) {
      ("min", ANum(n)) => out.push(DCompare(op=DGe, rhs=DLit(n)))
      ("max", ANum(n)) => out.push(DCompare(op=DLe, rhs=DLit(n)))
      // Both spellings, because a schema block is written by hand and the
      // hyphen is what the rest of the language uses.
      ("min-len" | "minLen", ANum(n)) =>
        out.push(DLen(DCompare(op=DGe, rhs=DLit(n))))
      ("max-len" | "maxLen", ANum(n)) =>
        out.push(DLen(DCompare(op=DLe, rhs=DLit(n))))
      ("nonempty", AFlag) => out.push(DNonEmpty)
      ("pattern", AStr(re)) => out.push(DPattern(re))
      ("format", AStr(f)) => out.push(DFormat(f))
      _ => ()
    }
  }
  out
}

///|
/// Whether a constructor must be given this field — `#[required]`.
pub fn FieldDef::attr_required(self : FieldDef) -> Bool {
  self.attrs.iter().any(a => a.0 == "required")
}

///|
/// What a form pre-fills — `#[default = …]`. Not the type's zero, which every
/// reader already knows (`Ty::zero`).
pub fn FieldDef::attr_default(self : FieldDef) -> @tutuca.Value? {
  for a in self.attrs {
    if a.0 != "default" {
      continue
    }
    return match a.1 {
      ANum(n) => Some(Num(n))
      AStr(s) => Some(Str(s))
      // `#[default]` with nothing after it says a field defaults to being
      // there, which is the boolean `true`.
      AFlag => Some(Bool(true))
    }
  }
  None
}
