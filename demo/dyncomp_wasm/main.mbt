///| Dynamic-wasm-component demo shell. The page starts with only this shell
/// compiled in; clicking "load" fetches the counter bundle (a jco-transpiled
/// `tutuca:component` guest) and mounts a guest instance into `.slot` — all
/// through the stock render/dispatch pipeline (see dyncomp/DESIGN.md).

///|
fn main {

}

///|
/// Where the bundle's transpiled ESM lives relative to the served page.
/// The dist task copies guests/counter/dist/js there.
let bundle_url : String = "./counter/counter.component.js"

///|
fn build() -> @component.ModuleDef {
  let shell = @component.component(
    name="Shell",
    view=(
      #|<div class="dyncomp-demo">
      #|  <h1>dynamic wasm components</h1>
      #|  <button class="load" @on.click="load">load counter bundle</button>
      #|  <p class="status" @text=".status"></p>
      #|  <div class="slot-box"><x render=".slot"></div>
      #|  <div class="pair-box"><x render=".pair"></div>
      #|</div>
    ),
    style=(
      #|.dyncomp-demo { font-family: sans-serif; max-width: 30rem; margin: 2rem auto; }
      #|.dyncomp-demo .status { color: #666; min-height: 1.2em; }
      #|.dyncomp-demo .slot-box { margin-top: 1rem; }
    ),
    fields={
      "status": @component.FieldSpec::of_default(Str("no bundle loaded")),
      "slot": @component.FieldSpec::of_default(Null),
      "pair": @component.FieldSpec::of_default(Null),
    },
    input={
      "load": (inst, _args, _ctx) => {
        let _ = @dhw.load(bundle_url)
        Some(inst.set("status", Str("loading \{bundle_url} ...")))
      },
    },
    receive={
      "dyncompLoaded": (inst, args, _ctx) => {
        let module_name = match args {
          [Str(s)] => s
          _ => return Some(inst.set("status", Str("loaded: bad args")))
        }
        let counter = @dhw.make_instance(module_name, "Counter", args={
          "count": Num(5),
        })
        let pair = @dhw.make_instance(module_name, "Pair")
        match (counter, pair) {
          (Some(c), Some(p)) =>
            Some(
              inst
              .set("slot", c)
              .set("pair", p)
              .set(
                "status",
                Str("loaded \{module_name}: Counter + Pair mounted"),
              ),
            )
          _ =>
            Some(inst.set("status", Str("\{module_name}: missing components")))
        }
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
  @component.ModuleDef::new(name="dyncompdemo", components=[shell])
}

///|
pub fn mount() -> Unit {
  let doc = @wdom.WasmNode::of_any(@core.global_this()._get("document"))
  let root_el = doc.as_any()._call("getElementById", [@core.any("app")])
  let root = @wdom.WasmNode::of_any(root_el)
  let opts = @vdom.RenderOpts::new(doc)
  let app = try! @app.App::from_module(build(), "Shell", root, opts)
  // host-side request handlers guests can call via control.request
  app.scope.register_request_handlers({
    "double": @component.RequestFn((args, respond) => {
      match args {
        [Num(n)] => respond(Ok(Num(n * 2.0)))
        _ => respond(Err(Str("double: expected one number")))
      }
    }),
  })
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
