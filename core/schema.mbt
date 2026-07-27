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
  inputs? : Array[String] = [],
  receives? : Array[String] = [],
  bubbles? : Array[String] = [],
  responses? : Array[String] = [],
  methods? : Array[String] = [],
  ids? : Array[String] = [],
  view_names? : Array[String] = [],
  init_names? : Array[String] = [],
) -> SchemaInfo {
  {
    name,
    fingerprint,
    fields,
    inputs,
    receives,
    bubbles,
    responses,
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
