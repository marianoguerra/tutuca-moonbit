// Vdom-facing value helpers. JS truthiness and `${v}` display live on
// @tutuca.Value itself (Value::is_truthy / Value::to_display_string).

///|
/// Attribute-position value: None means the attribute is omitted (JS drops
/// null/undefined/false attrs at patch time).
fn value_to_attr(v : @tutuca.Value) -> @vdom.AttrValue? {
  match v {
    Null => None
    Bool(false) => None
    Bool(true) => Some(Bool(true))
    Num(n) => Some(Num(n))
    Str(s) => Some(Str(s))
    // Structured values ride through as Data: on a registered custom
    // element the vdom assigns the real object as a property (the JS
    // `:items=".products"` web-component case); on plain elements it
    // degrades to a JSON-text attribute.
    List(_) | Map(_) => Some(Data(v.to_json()))
    Fn(_) | Obj(_) => None
  }
}

///|
/// Same for parse-time constants (ConstAttrs map entries).
fn lit_to_attr(lit : @tutuca.Lit) -> @vdom.AttrValue? {
  match lit {
    LNull => None
    LBool(false) => None
    LBool(true) => Some(Bool(true))
    LNum(n) => Some(Num(n))
    LStr(s) => Some(Str(s))
  }
}

///|
/// Call a handler value under the Fn convention: element 0 is the `this`
/// value (JS handler.call(thisVal, ...args)), the rest are the arguments.
fn call_handler(
  handler : @tutuca.Value,
  this_val : @tutuca.Value,
  args : Array[@tutuca.Value],
) -> @tutuca.Value {
  match handler {
    Fn(f) => {
      let full = [this_val]
      full.append(args)
      f(full)
    }
    _ => Null
  }
}
