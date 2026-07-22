// Shared Value extraction for items flowing through loops and handler args.
// Thin aliases over the core coercers (@tutuca.Value::int/str/bool/field) so
// the example bodies read like the JS originals; component STATE is typed
// now, so none of these touch instances.

///|
fn obj_str(v : @tutuca.Value, field : String) -> String {
  v.field(field).str()
}

///|
fn obj_int(v : @tutuca.Value, field : String) -> Int {
  v.field(field).int()
}

///|
fn obj_bool(v : @tutuca.Value, field : String) -> Bool {
  v.field(field).bool()
}

///|
/// The shared `filterItem` @when: keep items whose `containsText` method
/// matches `query` (used by the rendering and request examples' filtered
/// lists). Typed form: pass the component's query string.
fn contains_text_filter(query : String, item : @tutuca.Value) -> Bool {
  match item.field("containsText") {
    Fn(f) => f([Null, Str(query)]).is_truthy()
    _ => true
  }
}
