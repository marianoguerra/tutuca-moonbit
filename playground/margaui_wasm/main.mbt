///|
fn main {

}

///|
/// Compile the classes in a JSON array string to CSS. Exported to JS; with
/// use-js-builtin-string the `String` argument and result marshal directly as
/// JS strings. Never raises — a parse or compile failure returns "" so the
/// preview renders unstyled rather than throwing.
pub fn compile(classes_json : String) -> String {
  @css.compile_margaui(parse_classes(classes_json)) catch {
    _ => ""
  }
}

///|
/// Best-effort parse of a JSON array of strings; anything unexpected is skipped.
fn parse_classes(classes_json : String) -> Array[String] {
  let parsed = @json.parse(classes_json) catch { _ => return [] }
  guard parsed is Array(items) else { return [] }
  let out = []
  for item in items {
    if item is String(class_name) {
      out.push(class_name)
    }
  }
  out
}
