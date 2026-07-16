// Shared typed-field extraction, used across the example modules. Two access
// shapes appear in handlers: `@component.Instance.get(name)` (the component's
// own state) and `Value::Obj.obj_field(name)` (an item flowing through a loop
// or handler args). Both yield a Value; these helpers coerce it with the
// same defaults the JS examples get from duck typing.

///|
/// Field off a Value::Obj; Null for non-objects and missing fields.
fn obj_get(v : @tutuca.Value, field : String) -> @tutuca.Value {
  match v {
    Obj(o) => o.obj_field(field).unwrap_or(Null)
    _ => Null
  }
}

///|
fn obj_str(v : @tutuca.Value, field : String) -> String {
  as_str(obj_get(v, field))
}

///|
fn obj_int(v : @tutuca.Value, field : String) -> Int {
  as_int(obj_get(v, field))
}

///|
fn obj_bool(v : @tutuca.Value, field : String) -> Bool {
  as_bool(obj_get(v, field))
}

///|
fn as_str(v : @tutuca.Value) -> String {
  match v {
    Str(s) => s
    _ => ""
  }
}

///|
fn as_int(v : @tutuca.Value) -> Int {
  match v {
    Num(n) => n.to_int()
    _ => 0
  }
}

///|
fn as_bool(v : @tutuca.Value) -> Bool {
  v is Bool(true)
}

///|
fn as_list(v : @tutuca.Value) -> Array[@tutuca.Value] {
  match v {
    List(a) => a
    _ => []
  }
}

///|
/// The shared `filterItem` alter: keep items whose `containsText` method
/// matches the component's `query` field (used by the rendering and request
/// examples' filtered lists).
fn filter_by_contains_text(
  inst : @component.Instance,
  args : Array[@tutuca.Value],
) -> @tutuca.Value {
  match (inst.get("query"), args) {
    (Str(q), [_key, item, ..]) =>
      match obj_get(item, "containsText") {
        Fn(f) => f([Null, Str(q)])
        _ => Bool(true)
      }
    _ => Bool(true)
  }
}

///|
/// Component-state variant: `inst.get(name)` coerced to Int.
fn int_field(inst : @component.Instance, name : String) -> Int {
  as_int(inst.get(name))
}
