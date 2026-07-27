// Shared Value extraction for items flowing through loops and handler args.
//
// The per-example `obj_str`/`obj_int`/`obj_bool` aliases are gone: they wrapped
// `@tutuca.Value::field` + a coercer, and `v.field("name").str()` says the same
// thing in the same space without a second name to learn. What is left here is
// the one helper two examples genuinely SHARE.

///|
/// The shared `filterItem` @when: keep items whose `containsText` method
/// matches `query` (used by the rendering and request examples' filtered
/// lists). Typed form: pass the component's query string.
///
/// `call_field` fills the Fn convention's `this` slot; an item without the
/// method answers Null, which is falsy — so the `true` here is a deliberate
/// "no filter to apply", not a swallowed miss.
fn contains_text_filter(query : String, item : @tutuca.Value) -> Bool {
  match item.field("containsText") {
    Fn(_) => item.call_field("containsText", [Str(query)]).is_truthy()
    _ => true
  }
}
