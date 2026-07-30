// The wasm-gc mount facade. The user's compiled module exports thin wrappers
// (`mount`, `on_event`, `state_json`, `classes_json`) that delegate here; the
// playground driver instantiates the wasm module, calls `mount`, and — because
// events are delegated through the exported `on_event` — the app is held here
// so `on_event` and the inspector getters can reach it.

///|
let current : Ref[@app.App[@wdom.WasmNode]?] = Ref(None)

///|
/// How many dispatches the activity panel keeps (see the js host twin).
const ACTIVITY_CAP = 200

///|
/// The recent dispatches as JSON, newest last.
let activity : Array[Json] = []

///|
/// Mount a user-authored module on `#<root_id>`, driving the DOM from wasm.
pub fn mount(
  m : @component.ModuleDef,
  root_id : String,
  root? : String,
  args? : Map[String, @tutuca.Value],
) -> Unit {
  let doc = @wglue.document()
  guard @wglue.element_by_id(doc, root_id) is Some(root_node) else {
    @tutuca.warn("playground(wasm): no #\{root_id} element")
    return
  }
  let opts = @vdom.RenderOpts::new(doc)
  let (root_name, root_args) = match root {
    Some(r) => (r, args.unwrap_or(Map([])))
    None =>
      match m.examples {
        [ex, ..] => (ex.component, args.unwrap_or(ex.args))
        [] => (m.name, args.unwrap_or(Map([])))
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
  app.transactor.observe(record => {
    activity.push(record.to_json())
    if activity.length() > ACTIVITY_CAP {
      activity.remove(0) |> ignore
    }
  })
  |> ignore
  app.send_at_root("init") |> ignore
}

///|
/// The delegated DOM event entry point JS calls (via tdom.add_listener).
pub fn on_event(ev : @core.Any) -> Unit {
  @wglue.on_event(ev)
}

///|
/// Current root state as JSON, like the js host: an instance projects to its
/// declared fields rather than flattening to null.
pub fn state_json() -> String {
  match current.val {
    Some(app) => app.root_value().to_json().stringify()
    None => "—"
  }
}

///|
/// The dispatches since mount, as a JSON array.
pub fn activity_json() -> String {
  Json::array(activity).stringify()
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
