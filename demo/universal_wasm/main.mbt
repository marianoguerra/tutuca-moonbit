///| Universal wasm-component host: the wasm counterpart of the JS "universal"
/// app (../../docs/src/universal.js). That page drops a JS module and mounts
/// its components; this one drops a single `.tutuca.tar.gz` (a gzipped tar of
/// a guest's jco-transpiled `tutuca:component` bundle), the loader unpacks it
/// with the native DecompressionStream + a tiny tar reader, instantiates the
/// guest, and this shell mounts EVERY component the manifest declares.
///
/// The drop is handled in JS (loader.mjs): reading File bytes is a JS concern,
/// and a JS-initiated load notifies the root (@dhw.notify with no path), so
/// the shell — mounted as root — receives "dyncompLoaded" as a plain state
/// change and seeds one instance of each declared component.

///|
fn main {

}

///|
/// A generic drop shell: a drop zone, a status line, and a mount region that
/// renders every component of the loaded bundle (`<x render-each=".slots">`).
/// Unlike @dhw.shell_module it hard-codes neither a bundle URL nor component
/// names — the names come from the manifest via @dhw.bundle_component_names.
fn universal_shell_module() -> @component.ModuleDef {
  let shell = @component.component(
    name="UniversalWasm",
    view=(
      #|<section class="universal" data-droptarget="tutuca-wasm-component">
      #|  <div class="dropzone">Drop a <code>.tutuca.tar.gz</code> bundle here</div>
      #|  <p class="status" @text=".status"></p>
      #|  <div class="slots"><x render-each=".slots"></x></div>
      #|</section>
    ),
    style=(
      #|.universal { font-family: sans-serif; max-width: 40rem; margin: 1rem auto; }
      #|.universal .dropzone { border: 2px dashed #99a; border-radius: 0.5rem; padding: 2rem; text-align: center; color: #667; }
      #|.universal .status { color: #666; min-height: 1.2em; }
      #|.universal .slots { display: flex; flex-direction: column; gap: 1rem; margin-top: 1rem; }
    ),
    fields={
      "status": @component.FieldSpec::of_default(
        Str("drop a .tutuca.tar.gz bundle to load a wasm component"),
      ),
      "slots": @component.FieldSpec::of_default(List([])),
    },
    receive={
      // Fired by @dhw.on_loaded after a bundle registers. Mount one instance
      // of every declared component with default args (the manifest has no
      // "top-level" flag; guest constructors default their own fields).
      "dyncompLoaded": (inst, args, _ctx) => {
        let module_name = match args {
          [Str(s)] => s
          _ => return Some(inst.set("status", Str("loaded: bad args")))
        }
        let slots : Array[@tutuca.Value] = []
        for name in @dhw.bundle_component_names(module_name) {
          match @dhw.make_instance(module_name, name) {
            Some(v) => slots.push(v)
            None => ()
          }
        }
        let status = "loaded \{module_name}: \{slots.length()} component(s) mounted"
        Some(inst.set("slots", List(slots)).set("status", Str(status)))
      },
      "dyncompError": (inst, args, _ctx) => {
        let msg = match args {
          [Str(s)] => s
          _ => "unknown error"
        }
        Some(inst.set("status", Str("load failed: \{msg}")))
      },
    },
  )
  @component.ModuleDef::new(name="universalwasm", components=[shell])
}

///|
pub fn mount() -> Unit {
  let doc = @wdom.WasmNode::of_any(@core.global_this()._get("document"))
  let root_el = doc.as_any()._call("getElementById", [@core.any("app")])
  let root = @wdom.WasmNode::of_any(root_el)
  let opts = @vdom.RenderOpts::new(doc)
  let app = try! @app.App::from_module(
    universal_shell_module(),
    "UniversalWasm",
    root,
    opts,
  )
  // Host-provided request services a dropped guest may call. Reuses the
  // dyncomp demo's set (e.g. "double", used by the sample counter's double
  // button); a real deployment would register whatever services its guests
  // expect.
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
pub fn state_json() -> String {
  guard @dhw.app_root_value() is Some(v) else { return "null" }
  v.to_display_string()
}
