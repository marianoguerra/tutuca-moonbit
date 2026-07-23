// Publishes the view generator to the playground page.
//
// One JS entry point, `globalThis.__tutucaViewgen(html, name)`, returning a
// JSON string so the boundary carries no MoonBit types:
//
//   { "ok": true,  "module": "<the types module>", "ir": "<the tree module>" }
//   { "ok": false, "error": "<one-line message>" }
//
// `ir` is absent when the views use a macro (macros are registered from
// MoonBit at runtime, so they cannot be expanded ahead of time) — the page
// then falls back to building the views at runtime with
// `@anode.View::new(name, raw_view~)`.

///|
extern "js" fn publish_viewgen(gen : (String, String) -> String) -> Unit =
  #|(gen) => { globalThis.__tutucaViewgen = gen }

///|
/// Generate both modules from one .html file's text. Never raises: a bad view
/// comes back as `ok: false` so the page can show it like a compile error.
fn generate_json(html : String, name : String) -> String {
  let obj : Map[String, Json] = try {
    let views = @viewgen.split_file(html)
    let m : Map[String, Json] = {
      "ok": true.to_json(),
      // No moon.pkg in the playground package to import
      // moonbitlang/core/debug from, so the enums derive Eq alone.
      "module": @viewgen.emit_module(
        name,
        "view.html",
        views,
        debug_derive=false,
      ).to_json(),
    }
    if @viewgen.ir_supported(views) {
      m["ir"] = @viewgen.emit_ir_module(name, "view.html", views).to_json()
    }
    m
  } catch {
    e =>
      {
        "ok": false.to_json(),
        "error": @viewgen.GenError::message(e).to_json(),
      }
  }
  Json::object(obj).stringify()
}

///|
fn main {
  publish_viewgen(generate_json)
}
