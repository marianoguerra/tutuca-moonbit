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
/// Live single-touch drag capture (touchstart .. touchend), mirroring the
/// closure-captured Ref in app/browser. Global here since `on_event` is a
/// top-level export with no closure to hold it.
let touch_state : Ref[TouchState?] = Ref(None)

///|
priv struct TouchState {
  id : Double
  start_x : Double
  start_y : Double
  target : @core.Any
  mut active : Bool
}

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

// --- touch -> drag synthesis (app/browser App._handleTouchEvent) ---

///|
fn touches_len(ev : @core.Any) -> Int {
  let ts = ev._get("touches")
  if @core.is_nullish(ts) {
    0
  } else {
    tdom_get_int(ts, "length")
  }
}

///|
fn first_touch(ev : @core.Any) -> @core.Any {
  let ts = ev._get("touches")
  if @core.is_nullish(ts) {
    @core.null()
  } else {
    ts._get_by_index(0)
  }
}

///|
/// The nearest `[draggable="true"]` ancestor of a touch target, or null.
fn closest_draggable(target : @core.Any) -> @core.Any {
  if @core.is_nullish(target) || !tdom_has_prop(target, "closest") {
    @core.null()
  } else {
    target._call("closest", [@core.any("[draggable=\"true\"]")])
  }
}

///|
/// Find the touch with `id` across touches/changedTouches, or null.
fn find_touch(ev : @core.Any, id : Double) -> @core.Any {
  for key in ["touches", "changedTouches"] {
    let list = ev._get(key)
    if !@core.is_nullish(list) {
      let n = tdom_get_int(list, "length")
      for i in 0..<n {
        let t = list._get_by_index(i)
        if tdom_get_num(t, "identifier") == id {
          return t
        }
      }
    }
  }
  @core.null()
}

///|
/// Hit-test under the finger. Simplified vs app/browser: no shadow-DOM descent
/// (the examples mount in the light DOM), so a plain document.elementFromPoint.
fn element_from_point(x : Double, y : Double) -> @core.Any {
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
fn dispatch_synthetic(
  app : @app.App[@wdom.WasmNode],
  kind : String,
  target : @core.Any,
) -> Unit {
  if !@core.is_nullish(target) {
    let _ = app.dispatch(
      @wdom.WasmNode::of_any(target),
      @render.DomEvent::new(name=kind),
    )
  }
}

///|
/// A single touch on a [draggable] becomes dragstart once it moves >10px,
/// dragover while moving (hit-testing under the finger), drop + dragend on
/// release (app/browser App._handleTouchEvent).
fn handle_touch(
  app : @app.App[@wdom.WasmNode],
  ev : @core.Any,
  name : String,
) -> Unit {
  if name == "touchstart" {
    if touch_state.val is Some(_) || touches_len(ev) != 1 {
      return
    }
    let t = first_touch(ev)
    if @core.is_nullish(t) {
      return
    }
    let draggable = closest_draggable(t._get("target"))
    if @core.is_nullish(draggable) {
      return
    }
    touch_state.val = Some({
      id: tdom_get_num(t, "identifier"),
      start_x: tdom_get_num(t, "clientX"),
      start_y: tdom_get_num(t, "clientY"),
      target: draggable,
      active: false,
    })
    return
  }
  guard touch_state.val is Some(ts) else { return }
  let t = find_touch(ev, ts.id)
  if @core.is_nullish(t) {
    return
  }
  let x = tdom_get_num(t, "clientX")
  let y = tdom_get_num(t, "clientY")
  if name == "touchmove" {
    if !ts.active {
      let dx = x - ts.start_x
      let dy = y - ts.start_y
      if dx * dx + dy * dy < 100.0 {
        return
      }
      ts.active = true
      prevent_default(ev)
      dispatch_synthetic(app, "dragstart", ts.target)
    } else {
      prevent_default(ev)
      dispatch_synthetic(app, "dragover", element_from_point(x, y))
    }
  } else if name == "touchend" || name == "touchcancel" {
    if ts.active {
      if name == "touchend" {
        dispatch_synthetic(app, "drop", element_from_point(x, y))
      }
      dispatch_synthetic(app, "dragend", ts.target)
    }
    touch_state.val = None
  }
}

///|
/// Install one delegated listener per event name any registered view uses
/// (JS subscribeToEvents) plus the fixed drag/touch set, so dnd works. The
/// listeners are wired on the JS side and call back through `on_event`.
pub fn install(app : @app.App[@wdom.WasmNode]) -> Unit {
  current_app.val = Some(app)
  touch_state.val = None
  let root = app.root_node.as_any()
  let names = app.event_names()
  for
    extra in [
      "dragstart", "dragover", "dragend", "drop", "touchstart", "touchmove", "touchend",
      "touchcancel",
    ] {
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
    handle_touch(app, ev, name)
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
