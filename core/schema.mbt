// The declared-description constructors and queries (see schema_spec.mbt).

///|
pub fn FieldInfo::new(name : String, ty : TyInfo) -> FieldInfo {
  { name, ty }
}

///|
/// The runtime kind this field carries — a projection of its type, never a
/// second statement about it.
pub fn FieldInfo::kind(self : FieldInfo) -> FieldKind {
  self.ty.kind()
}

///|
pub fn FieldInfo::default(self : FieldInfo) -> Value {
  self.ty.zero()
}

///|
pub fn SchemaInfo::new(
  name? : String = "",
  fingerprint~ : String,
  fields? : Array[FieldInfo] = [],
  view_handlers? : Array[String] = [],
  receives? : Array[String] = [],
  intents? : Array[String] = [],
  methods? : Array[String] = [],
  ids? : Array[String] = [],
  view_names? : Array[String] = [],
  init_names? : Array[String] = [],
) -> SchemaInfo {
  {
    name,
    fingerprint,
    fields,
    view_handlers,
    receives,
    intents,
    methods,
    ids,
    view_names,
    init_names,
  }
}

///|
/// Linear over `fields`, which is the right shape at these sizes: a component
/// has a handful of them and the array preserves declaration order, which the
/// callers below read as much as they read the entries themselves.
pub fn SchemaInfo::field(self : SchemaInfo, name : String) -> FieldInfo? {
  for f in self.fields {
    if f.name == name {
      return Some(f)
    }
  }
  None
}

///|
pub fn SchemaInfo::field_names(self : SchemaInfo) -> Array[String] {
  self.fields.map(f => f.name)
}

///|
/// A structural fingerprint of a schema that arrives at RUNTIME, for a caller
/// with no generated one to carry: the dynamic-component host, which receives a
/// guest's declared shape over the `tutuca:component` boundary and needs the
/// same thing `<v>_schema_fingerprint` gives a compiled component — a value
/// that changes when the shape does, and not otherwise (it seeds the render
/// cache's bucket, and says when stored state can no longer be read back).
///
/// The twin of `@statedef.fingerprint`, which hashes the same shape one step
/// earlier — from the SOURCE schema, where a variant's payload types and the
/// user types are still visible. The two hash different inputs and do not
/// produce the same string for the same component; neither is compared against
/// the other, and each is stable for its own producer, which is all either one
/// is for.
pub fn SchemaInfo::shape_fingerprint(self : SchemaInfo) -> String {
  let sb = StringBuilder::new()
  sb.write_string("i:\{self.name};")
  for f in self.fields {
    sb.write_string("f:\{f.name}:\{f.ty.show_source()};")
    for m in f.ty.members() {
      sb.write_string("m:\{m},")
    }
  }
  for
    pair in [
      ("r", self.receives),
      ("i", self.intents),
      ("c", self.methods),
      ("v", self.view_names),
    ] {
    for n in pair.1 {
      sb.write_string("\{pair.0}:\{n};")
    }
  }
  // FNV-1a, hex — not cryptographic and does not need to be: it distinguishes
  // schemas a human wrote, not ones an attacker did.
  let mut h : UInt64 = 0xcbf29ce484222325UL
  for c in sb.to_string().to_array() {
    h = (h ^ c.to_int().reinterpret_as_uint().to_uint64()) * 0x100000001b3UL
  }
  let digits = "0123456789abcdef".to_array()
  let out = StringBuilder::new()
  for i in 0..<16 {
    out.write_char(digits[((h >> ((15 - i) * 4)) & 0xfUL).to_int()])
  }
  out.to_string()
}

///|
/// The name of a field's generated mutator: `count` + `set` -> `setCount`.
///
/// The convention lives HERE, in one function, because two places have to agree
/// on it and neither can see the other. `component()` builds the mutators by
/// concatenating it, and the state editor — which holds a bare `Value` and calls
/// them by name through `Obj::obj_field` — reconstructed the same string from
/// its own copy. Two spellings of one convention, either of which could have
/// been changed alone.
pub fn mutator_name(verb : String, field : String) -> String {
  if field.is_empty() {
    return verb
  }
  verb + field[0:1].to_owned().to_upper() + field[1:].to_owned()
}
