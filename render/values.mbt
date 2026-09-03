// Vdom-facing value helpers. JS truthiness and `${v}` display live on
// @tutuca.Value itself (Value::is_truthy / Value::to_display_string).

///|
/// Attribute-position value: None means the attribute is omitted (null,
/// undefined and false attrs are dropped at patch time).
fn value_to_attr(v : @tutuca.Value) -> @vdom.AttrValue? {
  match v {
    Null => None
    Bool(false) => None
    Bool(true) => Some(Bool(true))
    Num(n) => Some(Num(n))
    Str(s) => Some(Str(s))
    // An attribute is text in the DOM whatever it was here, so these take the
    // display spelling rather than a structured one: `Num` would lose an
    // integer past 2^53, and there is no attribute shape for bytes.
    Int(_) | Instant(..) => Some(Str(v.to_display_string()))
    // Bytes are dropped rather than spelled. A `Bin` in an attribute position
    // is a mistake with several plausible readings — base64? hex? text? — and
    // the view should say which by converting it.
    Bin(_) => None
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
/// Call a handler value under the Fn convention (`@tutuca.Value::call`): the
/// `this` slot the callee ignores, then the arguments.
fn call_handler(
  handler : @tutuca.Value,
  this_val : @tutuca.Value,
  args : Array[@tutuca.Value],
) -> @tutuca.Value {
  handler.call(args, this=this_val)
}
