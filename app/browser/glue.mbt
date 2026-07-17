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
extern "js" fn touches_len_ffi(e : @core.Any) -> Int =
  #|(e) => e.touches?.length ?? 0

///|
extern "js" fn first_touch_ffi(e : @core.Any) -> @core.Any =
  #|(e) => e.touches?.[0] ?? null

///|
extern "js" fn touch_num_ffi(t : @core.Any, name : String) -> Double =
  #|(t, n) => t[n] ?? 0

///|
extern "js" fn touch_target_ffi(t : @core.Any) -> @core.Any =
  #|(t) => t.target ?? null

///|
extern "js" fn closest_draggable_ffi(target : @core.Any) -> @core.Any =
  #|(t) => (t && t.closest && t.closest('[draggable="true"]')) ?? null

///|
extern "js" fn find_touch_ffi(e : @core.Any, id : Double) -> @core.Any =
  #|(e, id) => {
  #|  for (const list of [e.touches, e.changedTouches]) {
  #|    if (!list) continue;
  #|    for (const t of list) if (t.identifier === id) return t;
  #|  }
  #|  return null;
  #|}

///|
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
priv struct TouchState {
  id : Double
  start_x : Double
  start_y : Double
  target : @core.Any
  mut active : Bool
}

///|
/// Touch → drag synthesis (JS App._handleTouchEvent): a single touch on a
/// [draggable] element becomes dragstart once it moves >10px, dragover while
/// moving (hit-testing under the finger), drop + dragend on release.
fn handle_touch(
  app : @app.App[@browser.BrowserNode],
  touch : Ref[TouchState?],
  ev : @core.Any,
  name : String,
) -> Unit {
  fn fire(kind : String, target : @core.Any) {
    if !is_null_ffi(target) {
      let _ = app.dispatch(
        @browser.BrowserNode::of_any(target),
        @render.DomEvent::new(name=kind),
      )
    }
  }

  if name == "touchstart" {
    if touch.val is Some(_) || touches_len_ffi(ev) != 1 {
      return
    }
    let t = first_touch_ffi(ev)
    if is_null_ffi(t) {
      return
    }
    let draggable = closest_draggable_ffi(touch_target_ffi(t))
    if is_null_ffi(draggable) {
      return
    }
    touch.val = Some({
      id: touch_num_ffi(t, "identifier"),
      start_x: touch_num_ffi(t, "clientX"),
      start_y: touch_num_ffi(t, "clientY"),
      target: draggable,
      active: false,
    })
    return
  }
  guard touch.val is Some(ts) else { return }
  let t = find_touch_ffi(ev, ts.id)
  if is_null_ffi(t) {
    return
  }
  let x = touch_num_ffi(t, "clientX")
  let y = touch_num_ffi(t, "clientY")
  let root_any = app.root_node.as_any()
  if name == "touchmove" {
    if !ts.active {
      let dx = x - ts.start_x
      let dy = y - ts.start_y
      if dx * dx + dy * dy < 100.0 {
        return
      }
      ts.active = true
      prevent_default_ffi(ev)
      fire("dragstart", ts.target)
    } else {
      prevent_default_ffi(ev)
      fire("dragover", element_from_point_ffi(root_any, x, y))
    }
  } else if name == "touchend" || name == "touchcancel" {
    if ts.active {
      if name == "touchend" {
        fire("drop", element_from_point_ffi(root_any, x, y))
      }
      fire("dragend", ts.target)
    }
    touch.val = None
  }
}

///|
/// Install one delegated listener per event name any registered view uses
/// (JS subscribeToEvents) plus the fixed drag/touch set, dispatching into
/// the app from the event target. dragover/drop are preventDefault-ed so
/// drops are allowed (simplification: JS prevents only over droptargets).
pub fn install(app : @app.App[@browser.BrowserNode]) -> Unit {
  let root_any = app.root_node.as_any()
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
  let touch : Ref[TouchState?] = { val: None }
  for name in names {
    add_listener_ffi(root_any, name, ev => {
      if name.has_prefix("touch") {
        handle_touch(app, touch, ev, name)
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
