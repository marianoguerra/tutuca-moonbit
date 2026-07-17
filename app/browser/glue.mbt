// Browser event glue (the listener half of JS App.subscribeToEvents +
// _dispatchEvent): one listener per event name on the app's root node,
// each translating the raw event into a DomEvent and dispatching from its
// target, plus drag/touch synthesis (a touch on a [draggable] becomes
// dragstart/dragover/drop once it moves).

///|
extern "js" fn add_listener_ffi(
  node : @core.Any,
  name : String,
  cb : (@core.Any) -> Unit,
) -> Unit =
  #|(n, name, cb) => n.addEventListener(name, cb)

///|
extern "js" fn event_type_ffi(e : @core.Any) -> String =
  #|(e) => e.type ?? ""

///|
extern "js" fn event_key_ffi(e : @core.Any) -> String =
  #|(e) => e.key ?? ""

///|
extern "js" fn event_key_code_ffi(e : @core.Any) -> Int =
  #|(e) => e.keyCode ?? 0

///|
extern "js" fn event_bool_ffi(e : @core.Any, name : String) -> Bool =
  #|(e, n) => !!e[n]

///|
extern "js" fn event_ctrl_or_cmd_ffi(e : @core.Any) -> Bool =
  #|(e) => {
  #|  const mac = (globalThis.navigator?.platform ?? "").includes("Mac");
  #|  return !!((mac && e.metaKey) || e.ctrlKey);
  #|}

///|
extern "js" fn event_target_ffi(e : @core.Any) -> @core.Any =
  #|(e) => e.target ?? null

///|
/// JS getValue(e): checkbox -> checked, file input -> the first file's
/// metadata (File objects can't be read synchronously, but name/size/type/
/// lastModified are available immediately), elements with a value -> value,
/// else CustomEvent detail.
extern "js" fn event_value_ffi(e : @core.Any) -> @core.Any =
  #|(e) => {
  #|  const t = e.target;
  #|  if (t && t.type === "checkbox") return t.checked;
  #|  if (t && t.type === "file") {
  #|    const f = t.files && t.files[0];
  #|    return f
  #|      ? { name: f.name, size: f.size, type: f.type, lastModified: f.lastModified }
  #|      : null;
  #|  }
  #|  if (t && t.value !== undefined) return t.value;
  #|  return e.detail ?? null;
  #|}

///|
extern "js" fn any_kind_ffi(v : @core.Any) -> String =
  #|(v) => (v === null || v === undefined) ? "null" : typeof v

///|
extern "js" fn is_null_ffi(v : @core.Any) -> Bool =
  #|(v) => v == null

///|
/// "" when the value has no JSON form (cycles, functions).
extern "js" fn json_stringify_ffi(v : @core.Any) -> String =
  #|(v) => { try { return JSON.stringify(v) ?? "" } catch { return "" } }

///|
fn js_value(v : @core.Any) -> @tutuca.Value {
  match any_kind_ffi(v) {
    "boolean" => Bool(v.cast())
    "number" => Num(v.cast())
    "string" => Str(v.cast())
    // structured payloads (CustomEvent detail objects, file metadata) ride
    // through as Value::Map/List via the JSON bridge
    "object" => {
      let s = json_stringify_ffi(v)
      if s == "" {
        return Null
      }
      let j = @json.parse(s) catch { _ => return Null }
      @tutuca.Value::from_json(j)
    }
    _ => Null
  }
}

///|
/// Translate a raw browser event into the backend-agnostic DomEvent.
fn dom_event_of(ev : @core.Any) -> @render.DomEvent {
  @render.DomEvent::new(
    name=event_type_ffi(ev),
    value=js_value(event_value_ffi(ev)),
    key=event_key_ffi(ev),
    key_code=event_key_code_ffi(ev),
    alt=event_bool_ffi(ev, "altKey"),
    shift=event_bool_ffi(ev, "shiftKey"),
    ctrl_or_cmd=event_ctrl_or_cmd_ffi(ev),
    meta=event_bool_ffi(ev, "metaKey"),
  )
}

///|
extern "js" fn prevent_default_ffi(e : @core.Any) -> Unit =
  #|(e) => e.preventDefault && e.preventDefault()

///|
extern "js" fn has_prop_ffi(o : @core.Any, name : String) -> Bool =
  #|(o, n) => n in o

///|
extern "js" fn get_int_ffi(o : @core.Any, name : String) -> Int =
  #|(o, n) => o[n] | 0

///|
extern "js" fn get_num_ffi(o : @core.Any, name : String) -> Double =
  #|(o, n) => +(o[n] ?? 0)

///|
/// Hit-test under the finger, descending shadow roots (the wasm twin's
/// injected version is a plain document.elementFromPoint).
extern "js" fn element_from_point_ffi(
  root : @core.Any,
  x : Double,
  y : Double,
) -> @core.Any =
  #|(root, x, y) => {
  #|  const doc = root.getRootNode ? root.getRootNode() : root.ownerDocument;
  #|  let el = doc.elementFromPoint?.(x, y) ?? null;
  #|  while (el?.shadowRoot) {
  #|    const next = el.shadowRoot.elementFromPoint(x, y);
  #|    if (next === null || next === el) break;
  #|    el = next;
  #|  }
  #|  return el ?? root;
  #|}

///|
/// The shared touch -> drag machine (@touchdrag) wired to this backend's
/// typed reads, hit-testing and dispatch.
fn touch_drag_for(app : @app.App[@browser.BrowserNode]) -> @touchdrag.TouchDrag {
  @touchdrag.TouchDrag::new({
    has_prop: has_prop_ffi,
    get_int: get_int_ffi,
    get_num: get_num_ffi,
    element_from_point: element_from_point_ffi,
    fire: (kind, target) => {
      let _ = app.dispatch(
        @browser.BrowserNode::of_any(target),
        @render.DomEvent::new(name=kind),
      )
    },
  })
}

///|
/// Install one delegated listener per event name any registered view uses
/// (JS subscribeToEvents) plus the fixed drag/touch set, dispatching into
/// the app from the event target. dragover/drop are preventDefault-ed so
/// drops are allowed (simplification: JS prevents only over droptargets).
pub fn install(app : @app.App[@browser.BrowserNode]) -> Unit {
  let root_any = app.root_node.as_any()
  let names = app.event_names()
  for extra in @touchdrag.drag_touch_events() {
    if !names.contains(extra) {
      names.push(extra)
    }
  }
  let touch = touch_drag_for(app)
  for name in names {
    add_listener_ffi(root_any, name, ev => {
      if name.has_prefix("touch") {
        touch.handle(ev, name, app.root_node.as_any())
      } else {
        if name == "dragover" || name == "drop" {
          prevent_default_ffi(ev)
        }
        let target = event_target_ffi(ev)
        if !is_null_ffi(target) {
          let _ = app.dispatch(
            @browser.BrowserNode::of_any(target),
            dom_event_of(ev),
          )
        }
      }
    })
  }
}

///|
extern "js" fn inject_css_ffi(
  doc : @core.Any,
  id : String,
  css : String,
) -> Unit =
  #|(doc, id, css) => {
  #|  let el = doc.getElementById(id);
  #|  if (!el) {
  #|    el = doc.createElement("style");
  #|    el.id = id;
  #|    doc.head.appendChild(el);
  #|  }
  #|  el.textContent = css;
  #|}

///|
/// Compile every registered component's style into one <style id="tutuca-app">
/// element in the document head (JS App.recompileStyles/injectCss). Idempotent:
/// re-running replaces the element's contents.
pub fn install_styles(
  app : @app.App[@browser.BrowserNode],
  doc : @browser.BrowserNode,
) -> Unit {
  inject_css_ffi(doc.as_any(), "tutuca-app", app.scope.comps.compile_styles())
}

///|
/// Upsert a <style id=…> element in the document head (JS extra.js
/// injectCss). The margaui half of compileClassesToStyle: hand
/// `app.scope.comps.collect_classes()` to the class compiler on the JS side,
/// then inject the resulting CSS here (id "margaui-css" by convention).
pub fn inject_style(
  doc : @browser.BrowserNode,
  id : String,
  css : String,
) -> Unit {
  inject_css_ffi(doc.as_any(), id, css)
}
