// wasm-gc host for the ported docs examples. The SAME ModuleDef values the
// headless tests drive (examples/) are mounted here as live apps compiled to
// wasm. JS calls `mount()` after load, then `on_event` on each DOM event.
// margaui's CDN class compilation (the js host's extra polish) is skipped so
// the page stays self-contained; the examples' baseline styles still apply.

///|
fn main {

}

///|
/// Read a URL query parameter via URLSearchParams, reached through @core.
fn query_param(name : String) -> String {
  let g = @core.global_this()
  let search = g._get("location")._get("search")
  let params = @core.new(g._get("URLSearchParams"), [search])
  let v = params._call("get", [@core.any(name)])
  if @core.is_nullish(v) {
    ""
  } else {
    v.to_string()
  }
}

///|
/// Mount the example named by ?name= (defaulting to "counter") on #app, and
/// fill #index / #title. Called from JS once the DOM is ready.
pub fn mount() -> Unit {
  let g = @core.global_this()
  let doc = g._get("document")
  let root_el = doc._call("getElementById", [@core.any("app")])
  if @core.is_nullish(root_el) {
    println("no #app element")
    return
  }
  // index of every ported example, so the page is navigable
  let nav = doc._call("getElementById", [@core.any("index")])
  if !@core.is_nullish(nav) {
    let sb = StringBuilder::new()
    for e in @ex.all_examples() {
      sb.write_string("<a href=\"?name=\{e.name}\">\{e.name}</a>")
    }
    nav._set("innerHTML", @core.any(sb.to_string()))
  }
  let name = match query_param("name") {
    "" => "counter"
    n => n
  }
  guard @ex.find_example(name) is Some(e) else {
    root_el._set(
      "innerHTML",
      @core.any(
        "<p>unknown example: <code>\{name}</code> — pick one from the index above.</p>",
      ),
    )
    return
  }
  let title = doc._call("getElementById", [@core.any("title")])
  if !@core.is_nullish(title) {
    title._set("innerHTML", @core.any(e.name))
  }
  let root = @wdom.WasmNode::of_any(root_el)
  let opts = @vdom.RenderOpts::new(@wdom.WasmNode::of_any(doc))
  let app = try! @app.App::from_module(
    e.module_,
    e.root,
    root,
    opts,
    args=e.root_args(),
  )
  @wglue.install(app)
  @wglue.install_styles(app, @wdom.WasmNode::of_any(doc))
  // margaui: collect every class the compiled views can show and publish the
  // set (globalThis.__tutuca_classes) for index.html's margaui compile step —
  // the wasm-gc equivalent of the js host's publish_classes_ffi.
  publish_classes(app.scope.comps.collect_classes())
  // tutuca has no lifecycle: the HOST dispatches `init` (JS: app.sendAtRoot)
  if e.init {
    app.send_at_root("init")
  }
}

///|
/// Publish the collected margaui class set as a JS array on globalThis so the
/// page's margaui compile step can turn it into CSS.
fn publish_classes(classes : Array[String]) -> Unit {
  let arr = @core.new_array()
  for c in classes {
    let _ = arr._call("push", [@core.any(c)])
  }
  @core.global_this()._set("__tutuca_classes", arr)
}

///|
/// The delegated DOM event entry point JS calls (via tdom.add_listener).
pub fn on_event(ev : @core.Any) -> Unit {
  @wglue.on_event(ev)
}
