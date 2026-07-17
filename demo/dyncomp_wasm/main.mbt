///| Dynamic-wasm-component demo host. The page starts with only the shared
/// shell (@dhw.shell_module) compiled in; clicking "load" fetches the
/// counter bundle (a jco-transpiled `tutuca:component` guest) at runtime
/// and mounts its components into the tree — reloading hot-swaps the bundle
/// with state migration (see dyncomp/DESIGN.md).

///|
fn main {

}

///|
/// Where the bundle's transpiled ESM lives relative to the served page.
/// The dyncomp dist task copies guests/counter/dist/js there.
let bundle_url : String = "./counter/counter.component.js"

///|
pub fn mount() -> Unit {
  let doc = @wdom.WasmNode::of_any(@core.global_this()._get("document"))
  let root_el = doc.as_any()._call("getElementById", [@core.any("app")])
  let root = @wdom.WasmNode::of_any(root_el)
  let opts = @vdom.RenderOpts::new(doc)
  let app = try! @app.App::from_module(
    @dhw.shell_module(bundle_url~),
    "DynShell",
    root,
    opts,
  )
  app.scope.register_request_handlers(@dhw.shell_request_handlers())
  @wglue.install(app)
  @wglue.install_styles(app, doc)
  @dhw.set_app(app, doc)
}

///|
pub fn on_event(ev : @core.Any) -> Unit {
  @wglue.on_event(ev)
}

///|
pub fn dyncomp_on_loaded(
  load_id : Int,
  bundle_id : Int,
  manifest_json : String,
) -> Unit {
  @dhw.on_loaded(load_id, bundle_id, manifest_json)
}

///|
pub fn dyncomp_on_load_error(load_id : Int, msg : String) -> Unit {
  @dhw.on_load_error(load_id, msg)
}

///|
/// Root state as display text, for inspection/automated verification.
/// Guest subtrees render via obj_debug = the guest's to-json projection.
pub fn state_json() -> String {
  guard @dhw.app_root_value() is Some(v) else { return "null" }
  v.to_display_string()
}
