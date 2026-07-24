///|
/// Publish the margaui compiler on `globalThis.__tutucaMargaui`. Input is the
/// JSON array of class names the preview module exposes via `__tutuca.classes()`;
/// output is the compiled CSS. Runs on load (moonc emits an IIFE).
extern "js" fn publish_margaui(f : (String) -> String) -> Unit =
  #|(f) => { globalThis.__tutucaMargaui = f; }

///|
fn main {
  publish_margaui(compile_from_json)
}

///|
/// Compile the classes in a JSON string array to CSS. Never raises — a parse or
/// compile failure returns "" so the preview just renders unstyled rather than
/// breaking the page.
fn compile_from_json(classes_json : String) -> String {
  @margaui.compile_classes(parse_classes(classes_json)) catch {
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
