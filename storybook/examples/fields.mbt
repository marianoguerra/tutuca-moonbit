///|
fn contains_text_filter(query : String, item : @tutuca.Value) -> Bool {
  match item.field("contains_text") {
    Fn(_) => item.call_field("contains_text", [Str(query)]).is_truthy()
    _ => true
  }
}
