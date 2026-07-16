///|
/// Value of a virtual-node attribute.
///
/// `Html` carries the markup of `dangerouslySetInnerHTML` (the JS `{ __html }`
/// object); it never reaches `setAttribute` — `set_prop` routes it to
/// `set_inner_html` first. There is deliberately no `Int` variant: mixing
/// `Num(0.0)` and a hypothetical `Int(0)` would break `Eq`-based diffing.
///
/// `Data` carries a structured (JSON-shaped) value for object/array-valued
/// custom-element properties (the JS `h(tag, { items: [1, 2, 3] })` case).
/// It ALWAYS takes the property path — a structured value is a property by
/// definition, never an attribute. Diffing is by VALUE (Json's Eq), a
/// deliberate divergence from JS, which compares object props by reference
/// and re-invokes the setter for an equal-content new object.
pub(all) enum AttrValue {
  Str(String)
  Num(Double)
  Bool(Bool)
  Html(String)
  Data(Json)
} derive(Eq, Debug)

///|
/// Convenience constructor wrapping an `Int` as `Num`.
pub fn AttrValue::int(i : Int) -> AttrValue {
  Num(i.to_double())
}

///|
/// Serialized form written by `set_attribute`, mirroring JS string coercion:
/// numbers drop the trailing `.0` for integral values, booleans become
/// `"true"` / `"false"`.
pub fn AttrValue::to_attr_string(self : AttrValue) -> String {
  match self {
    Str(s) => s
    Num(d) => d.to_string()
    Bool(b) => b.to_string()
    Html(s) => s
    // Fallback only (Data normally never reaches setAttribute); JSON text is
    // strictly more useful than JS's "[object Object]" coercion.
    Data(j) => j.stringify()
  }
}
