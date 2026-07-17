// Event glue for the wasm-gc backend. Because MoonBit closures can't cross into
// JS on wasm-gc, the flow is inverted vs app/browser: JS installs one delegated
// listener per event name (tdom.add_listener) that calls the exported
// `on_event`, and we hold the live App here so `on_event` can dispatch into it.
// Includes the drag/touch synthesis that app/browser has, so dnd examples work.

///|
extern "wasm" fn tdom_has_prop(obj : @core.Any, name : String) -> Bool = "tdom" "has_prop"

///|
extern "wasm" fn tdom_get_int(obj : @core.Any, name : String) -> Int = "tdom" "get_int"

///|
extern "wasm" fn tdom_get_bool(obj : @core.Any, name : String) -> Bool = "tdom" "get_bool"

///|
extern "wasm" fn tdom_get_num(obj : @core.Any, name : String) -> Double = "tdom" "get_num"

///|
extern "wasm" fn tdom_add_listener(root : @core.Any, name : String) -> Unit = "tdom" "add_listener"

///|
/// JSON.stringify (returns "" for values with no JSON form).
extern "wasm" fn tdom_json_stringify(v : @core.Any) -> @core.Any = "tdom" "json_stringify"

///|
/// First selected file's {name,size,type,lastModified} as JSON text; "" when
/// no file is selected.
extern "wasm" fn tdom_file_meta(input : @core.Any) -> @core.Any = "tdom" "file_meta"

///|
extern "wasm" fn tdom_inject_css(
  doc : @core.Any,
  id : String,
  css : String,
) -> Unit = "tdom" "inject_css"

///|
/// The mounted app. Set by `install`; read by the exported `on_event`. Only one
/// app is live per wasm instance, which is exactly the demo's shape.
let current_app : Ref[@app.App[@wdom.WasmNode]?] = Ref(None)

///|
/// The live app's touch -> drag machine (see app/touchdrag), mirroring the
/// closure-captured value in app/browser's install. Global here since
/// `on_event` is a top-level export with no closure to hold it.
let touch_state : Ref[@touchdrag.TouchDrag?] = Ref(None)

///|
fn to_str(v : @core.Any) -> String {
  if @core.is_nullish(v) {
    ""
  } else {
    v.to_string()
  }
}

///|
fn prevent_default(ev : @core.Any) -> Unit {
  if tdom_has_prop(ev, "preventDefault") {
    let _ = ev._call("preventDefault", [])
  }
}

///|
/// getValue(e): checkbox -> checked, file input -> the first file's metadata,
/// elements with a value -> value, else CustomEvent detail (structured
/// payloads ride through the JSON bridge as Value::Map/List).
fn event_value(ev : @core.Any) -> @tutuca.Value {
  let target = ev._get("target")
  if !@core.is_nullish(target) {
    if tdom_has_prop(target, "type") {
      match to_str(target._get("type")) {
        "checkbox" => return Bool(tdom_get_bool(target, "checked"))
        "file" => return json_value(tdom_file_meta(target))
        _ => ()
      }
    }
    let v = target._get("value")
    if !@core.is_nullish(v) {
      return Str(v.to_string())
    }
  }
  let detail = ev._get("detail")
  if !@core.is_nullish(detail) {
    let s = to_str(tdom_json_stringify(detail))
    if s != "" {
      return json_value_str(s)
    }
  }
  Null
}

///|
fn json_value(s : @core.Any) -> @tutuca.Value {
  json_value_str(to_str(s))
}

///|
fn json_value_str(s : String) -> @tutuca.Value {
  if s == "" {
    return Null
  }
  let j = @json.parse(s) catch { _ => return Null }
  @tutuca.Value::from_json(j)
}

///|
/// Mirrors app/browser's event_ctrl_or_cmd_ffi: the "primary modifier" is
/// cmd on a Mac and ctrl elsewhere, so the same keypress means the same
/// thing on both backends.
fn event_ctrl_or_cmd(ev : @core.Any) -> Bool {
  let nav = @core.global_this()._get("navigator")
  let mac = !@core.is_nullish(nav) &&
    to_str(nav._get("platform")).contains("Mac")
  (mac && tdom_get_bool(ev, "metaKey")) || tdom_get_bool(ev, "ctrlKey")
}

///|
/// Translate a raw browser event into the backend-agnostic DomEvent.
fn dom_event_of(ev : @core.Any) -> @render.DomEvent {
  @render.DomEvent::new(
    name=to_str(ev._get("type")),
    value=event_value(ev),
    key=to_str(ev._get("key")),
    key_code=tdom_get_int(ev, "keyCode"),
    alt=tdom_get_bool(ev, "altKey"),
    shift=tdom_get_bool(ev, "shiftKey"),
    ctrl_or_cmd=event_ctrl_or_cmd(ev),
    meta=tdom_get_bool(ev, "metaKey"),
  )
}

// --- touch -> drag synthesis (shared machine in app/touchdrag) ---

///|
/// Hit-test under the finger. Simplified vs app/browser's injected version:
/// no shadow-DOM descent (the examples mount in the light DOM), so a plain
/// document.elementFromPoint; `_root` is unused here.
fn element_from_point(_root : @core.Any, x : Double, y : Double) -> @core.Any {
  let doc = @core.global_this()._get("document")
  if tdom_has_prop(doc, "elementFromPoint") {
    doc._call("elementFromPoint", [
      @core.ToAny::to_any(x),
      @core.ToAny::to_any(y),
    ])
  } else {
    @core.null()
  }
}

///|
/// The shared touch -> drag machine wired to this backend's typed reads,
/// hit-testing and dispatch.
fn touch_drag_for(app : @app.App[@wdom.WasmNode]) -> @touchdrag.TouchDrag {
  @touchdrag.TouchDrag::new({
    has_prop: tdom_has_prop,
    get_int: tdom_get_int,
    get_num: tdom_get_num,
    element_from_point,
    fire: (kind, target) => {
      let _ = app.dispatch(
        @wdom.WasmNode::of_any(target),
        @render.DomEvent::new(name=kind),
      )
    },
  })
}

///|
/// Install one delegated listener per event name any registered view uses
/// (JS subscribeToEvents) plus the fixed drag/touch set, so dnd works. The
/// listeners are wired on the JS side and call back through `on_event`.
pub fn install(app : @app.App[@wdom.WasmNode]) -> Unit {
  current_app.val = Some(app)
  touch_state.val = Some(touch_drag_for(app))
  let root = app.root_node.as_any()
  let names = app.event_names()
  for extra in @touchdrag.drag_touch_events() {
    if !names.contains(extra) {
      names.push(extra)
    }
  }
  for name in names {
    tdom_add_listener(root, name)
  }
}

///|
/// The wasm export JS calls on every delegated DOM event. Branches like the
/// app/browser listener: touch events feed the drag synthesizer, dragover/drop
/// are preventDefault-ed so drops are allowed, everything else dispatches from
/// the event target.
pub fn on_event(ev : @core.Any) -> Unit {
  guard current_app.val is Some(app) else { return }
  let name = to_str(ev._get("type"))
  if name.has_prefix("touch") {
    match touch_state.val {
      Some(touch) => touch.handle(ev, name, app.root_node.as_any())
      None => ()
    }
    return
  }
  if name == "dragover" || name == "drop" {
    prevent_default(ev)
  }
  let target = ev._get("target")
  if @core.is_nullish(target) {
    return
  }
  let _ = app.dispatch(@wdom.WasmNode::of_any(target), dom_event_of(ev))
}

///|
/// The browser document as a WasmNode.
pub fn document() -> @wdom.WasmNode {
  @wdom.WasmNode::of_any(@core.global_this()._get("document"))
}

///|
/// Look up `#id` in the document; None when the element is missing.
pub fn element_by_id(doc : @wdom.WasmNode, id : String) -> @wdom.WasmNode? {
  let el = doc.as_any()._call("getElementById", [@core.any(id)])
  if @core.is_nullish(el) {
    None
  } else {
    Some(@wdom.WasmNode::of_any(el))
  }
}

///|
/// Standard wasm host boot, shared by the demo hosts: mount `root_name` from
/// `m` on `#<id>` and install the event + style glue. Warns and returns None
/// when the element is missing or the mount fails.
pub fn mount_in(
  m : @component.ModuleDef,
  root_name : String,
  id? : String = "app",
  args? : Map[String, @tutuca.Value],
) -> @app.App[@wdom.WasmNode]? {
  let doc = document()
  guard element_by_id(doc, id) is Some(root) else {
    @tutuca.warn("tutuca(wasm): no #\{id} element")
    return None
  }
  let opts = @vdom.RenderOpts::new(doc)
  let app = @app.App::from_module(m, root_name, root, opts, args?) catch {
    e => {
      @tutuca.warn("tutuca(wasm): mount failed: \{e}")
      return None
    }
  }
  install(app)
  install_styles(app, doc)
  Some(app)
}

///|
/// Compile every registered component's style into one <style id="tutuca-app">
/// element in the document head (App.recompileStyles/injectCss). Idempotent.
pub fn install_styles(
  app : @app.App[@wdom.WasmNode],
  doc : @wdom.WasmNode,
) -> Unit {
  tdom_inject_css(doc.as_any(), "tutuca-app", app.scope.comps.compile_styles())
}

///|
/// Upsert a <style id=…> element in the document head (JS extra.js
/// injectCss). The margaui half of compileClassesToStyle: hand
/// `app.scope.comps.collect_classes()` to the class compiler on the JS side,
/// then inject the resulting CSS here (id "margaui-css" by convention).
pub fn inject_style(doc : @wdom.WasmNode, id : String, css : String) -> Unit {
  tdom_inject_css(doc.as_any(), id, css)
}
