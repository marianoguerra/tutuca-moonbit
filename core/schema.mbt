// The declared-description constructors and queries (see schema_spec.mbt).

///|
pub fn FieldInfo::new(
  name : String,
  ty : String,
  kind : FieldKind,
  elem? : String,
  slot? : String,
  members? : Array[String] = [],
) -> FieldInfo {
  { name, ty, kind, elem, slot, members }
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
