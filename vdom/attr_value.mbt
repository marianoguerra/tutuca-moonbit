///|
/// Value of a virtual-node attribute.
///
/// `Html` carries the markup of `dangerouslySetInnerHTML` (the `{ __html }`
/// object); it never reaches `setAttribute` — `set_prop` routes it to
/// `set_inner_html` first. There is deliberately no `Int` variant: mixing
/// `Num(0.0)` and a hypothetical `Int(0)` would break `Eq`-based diffing.
///
/// `Md` carries the markdown SOURCE of `@setinnermd`. It is a distinct variant
/// from `Html` rather than the same string under a different attribute name so
/// that no code path can confuse the two: markdown text handed to
/// `set_inner_html` would be inert-looking garbage on the page, and HTML handed
/// to the markdown builder would be re-interpreted. Like `Html` it never
/// reaches `setAttribute` — but unlike `Html`, reaching `set_prop` at all means
/// something went wrong, because the filter that understands it removes it
/// first. See the fail-closed branch in `to_dom.mbt`.
///
/// `SafeHtml` and `Svg` carry the HTML and SVG SOURCE of `@setinnerhtml` and
/// `@setinnersvg`, and stand to `Html` exactly as `Md` does. `SafeHtml` is not
/// `Html` under a different attribute name because the two route to opposite
/// branches of `set_prop` — `Html` to `set_inner_html`, `SafeHtml` to the
/// fail-closed one — and a single variant would make that a property of which
/// name it happened to be filed under rather than of the value itself. `Svg` is
/// not `SafeHtml` because the two are parsed in different insertion modes and
/// the namespace that results decides which half of a namespace-qualified
/// config applies.
///
/// `Data` carries a structured (JSON-shaped) value for object/array-valued
/// custom-element properties (the `h(tag, { items: [1, 2, 3] })` case).
/// It ALWAYS takes the property path — a structured value is a property by
/// definition, never an attribute. Diffing is by VALUE (Json's Eq), a
/// deliberate divergence from upstream, which compares object props by reference
/// and re-invokes the setter for an equal-content new object.
pub(all) enum AttrValue {
  Str(String)
  Num(Double)
  Bool(Bool)
  Html(String)
  Md(String)
  SafeHtml(String)
  Svg(String)
  Data(Json)
} derive(Eq, Debug)

///|
/// Convenience constructor wrapping an `Int` as `Num`.
pub fn AttrValue::int(i : Int) -> AttrValue {
  Num(i.to_double())
}

///|
/// Serialized form written by `set_attribute`, mirroring string coercion:
/// numbers drop the trailing `.0` for integral values, booleans become
/// `"true"` / `"false"`.
pub fn AttrValue::to_attr_string(self : AttrValue) -> String {
  match self {
    Str(s) => s
    Num(d) => d.to_string()
    Bool(b) => b.to_string()
    Html(s) | Md(s) | SafeHtml(s) | Svg(s) => s
    // Fallback only (Data normally never reaches setAttribute); JSON text is
    // strictly more useful than JS's "[object Object]" coercion.
    Data(j) => j.stringify()
  }
}
