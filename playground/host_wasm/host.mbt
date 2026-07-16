// The wasm-gc mount facade. The user's compiled module exports thin wrappers
// (`mount`, `on_event`, `state_json`, `classes_json`) that delegate here; the
// playground driver instantiates the wasm module, calls `mount`, and — because
// events are delegated through the exported `on_event` — the app is held here
// so `on_event` and the inspector getters can reach it.

///|
let current : Ref[@app.App[@wdom.WasmNode]?] = Ref(None)

///|
/// Mount a user-authored module on `#<root_id>`, driving the DOM from wasm.
pub fn mount(
  m : @component.ModuleDef,
  root_id : String,
  root? : String,
  args? : Map[String, @tutuca.Value],
) -> Unit {
  let doc_any = @core.global_this()._get("document")
  let root_el = doc_any._call("getElementById", [@core.any(root_id)])
  if @core.is_nullish(root_el) {
    println("playground(wasm): no #\{root_id} element")
    return
  }
  let doc = @wdom.WasmNode::of_any(doc_any)
  let root_node = @wdom.WasmNode::of_any(root_el)
  let opts = @vdom.RenderOpts::new(doc)
  let (root_name, root_args) = match root {
    Some(r) => (r, args.unwrap_or({}))
    None =>
      match m.examples {
        [ex, ..] => (ex.component, args.unwrap_or(ex.args))
        [] => (m.name, args.unwrap_or({}))
      }
  }
  let app = @app.App::from_module(m, root_name, root_node, opts, args=root_args) catch {
    e => {
      println("playground(wasm): mount failed: \{e}")
      return
    }
  }
  @wglue.install(app)
  @wglue.install_styles(app, doc)
  current.val = Some(app)
  app.send_at_root("init")
}

///|
/// The delegated DOM event entry point JS calls (via tdom.add_listener).
pub fn on_event(ev : @core.Any) -> Unit {
  @wglue.on_event(ev)
}

///|
/// Current root state in tutuca's readable value syntax (inspector "State").
pub fn state_json() -> String {
  match current.val {
    Some(app) =>
      match app.root_value() {
        Some(v) => v.to_display_string()
        None => "—"
      }
    None => "—"
  }
}

///|
/// The margaui class set the mounted views can show, as a JSON array string.
pub fn classes_json() -> String {
  match current.val {
    Some(app) => {
      let arr = app.scope.comps.collect_classes()
      Json::array(arr.map(c => Json::string(c))).stringify()
    }
    None => "[]"
  }
}
