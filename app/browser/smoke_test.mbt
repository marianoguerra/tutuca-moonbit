// Browser-app smoke test (happy-dom): a real App[BrowserNode] with installed
// listeners, driven by REAL dispatched events — the full loop on the js
// backend. Run with `moon test --target js app/browser`.

///|
extern "js" fn query_ffi(node : @core.Any, sel : String) -> @core.Any =
  #|(n, s) => n.querySelector(s) ?? null

///|
extern "js" fn real_click_ffi(node : @core.Any) -> Unit =
  #|(n) => {
  #|  const win = n.ownerDocument.defaultView;
  #|  n.dispatchEvent(new win.Event("click", { bubbles: true }));
  #|}

///|
extern "js" fn real_input_ffi(node : @core.Any, value : String) -> Unit =
  #|(n, v) => {
  #|  const win = n.ownerDocument.defaultView;
  #|  n.value = v;
  #|  n.dispatchEvent(new win.Event("input", { bubbles: true }));
  #|}

///|
extern "js" fn inner_html_ffi(node : @core.Any) -> String =
  #|(n) => n.innerHTML

///|
priv struct SmokeCounterState {
  n : Int
  label : String
}

///|
fn counter_comp() -> @component.Component {
  @component.component(
    views={
      "main": @anode.View::new(
        "main",
        raw_view="<div><button @on.click=\"bump\">+</button><span><x text=\".n\"></x></span><input :value=\".label\" @on.input=\".label = e.value\"></div>",
      ),
    },
    name="Counter",
    init=SmokeCounterState::{ n: 0, label: "start", },
    update=(s : SmokeCounterState, msg, _ctx) => {
      match msg {
        Receive("bump", _) => Next({ ..s, n: s.n + 1, })
        _ => Unhandled
      }
    },
  )
}

///|
fn field_v(a : @app.App[@bdom.BrowserNode], name : String) -> @tutuca.Value {
  match @tutuca.Path::new(steps=[FieldStep(name)]).lookup(a.transactor.root) {
    Some(n) => n
    None => Null
  }
}

///|
test "browser: real events drive the app through installed listeners" {
  let window = @test_utils.create_happy_window()
  let doc = window.document()
  let container = @bdom.BrowserNode::from_element(doc.createElement("div"))
  let scope = @component.ComponentStack::new()
  scope.register_components([counter_comp()])
  guard scope.lookup_component("Counter") is Some(c) else { fail("no Counter") }
  let a = @app.App::new(scope, c.make(Map([])), container, @bdom.opts_for(doc))
  a.start()
  @browser.install(a)
  assert_true(inner_html_ffi(container.as_any()).contains("<span>0</span>"))
  // a REAL click bubbles from the button to the installed root listener
  let btn = query_ffi(container.as_any(), "button")
  real_click_ffi(btn)
  real_click_ffi(btn)
  assert_true(field_v(a, "n") == Num(2))
  assert_true(inner_html_ffi(container.as_any()).contains("2"))
  // a REAL input event carries its target's value into the handler args
  let input = query_ffi(container.as_any(), "input")
  real_input_ffi(input, "typed")
  assert_true(field_v(a, "label") == Str("typed"))
}

///|
extern "js" fn style_text_ffi(doc : @core.Any) -> String =
  #|(doc) => doc.getElementById("tutuca-app")?.textContent ?? ""

///|
test "browser: styles are compiled into a head style element" {
  let window = @test_utils.create_happy_window()
  let doc = window.document()
  let container = @bdom.BrowserNode::from_element(doc.createElement("div"))
  let scope = @component.ComponentStack::new()
  let styled = @component.component(
    views={
      "main": @anode.View::new(
        "main",
        raw_view="<div>x</div>",
        style="color: red",
      ),
    },
    name="Styled",
    init=SmokeEmptyState::{ },
  )
  scope.register_components([styled])
  let a = @app.App::new(
    scope,
    styled.make(Map([])),
    container,
    @bdom.opts_for(doc),
  )
  let doc_node = @bdom.BrowserNode::from_document(doc)
  @browser.install_styles(a, doc_node)
  let css = style_text_ffi(doc_node.as_any())
  assert_true(
    css.contains("[data-cid=\"\{styled.id}\"][data-vid=\"main\"]{color: red}"),
  )
  // idempotent re-injection replaces, not duplicates
  @browser.install_styles(a, doc_node)
  assert_eq(style_text_ffi(doc_node.as_any()), css)
}

///|
extern "js" fn real_event_ffi(node : @core.Any, name : String) -> Unit =
  #|(n, name) => {
  #|  const win = n.ownerDocument.defaultView;
  #|  n.dispatchEvent(new win.Event(name, { bubbles: true, cancelable: true }));
  #|}

///|
test "browser: real drag events run the drag lifecycle" {
  let window = @test_utils.create_happy_window()
  let doc = window.document()
  let container = @bdom.BrowserNode::from_element(doc.createElement("div"))
  let scope = @component.ComponentStack::new()
  let board = @component.component(
    views={
      "main": @anode.View::new(
        "main",
        raw_view="<div><span draggable=\"true\" data-dragtype=\"chip\">drag me</span><div data-droptarget=\"\" @on.drop=\"landed e.dragInfo\">zone</div></div>",
      ),
    },
    name="DropBoard",
    init=DropBoardState::{ landed_kind: "", },
    update=(_s : DropBoardState, msg, _ctx) => {
      match msg {
        Receive("landed", [Map(info), ..]) =>
          match info.get("type") {
            Some(Str(kind)) => Next({ landed_kind: kind, })
            _ => Unhandled
          }
        _ => Unhandled
      }
    },
  )
  scope.register_components([board])
  guard scope.lookup_component("DropBoard") is Some(c) else {
    fail("no DropBoard")
  }
  let a = @app.App::new(scope, c.make(Map([])), container, @bdom.opts_for(doc))
  a.start()
  @browser.install(a)
  let chip = query_ffi(container.as_any(), "span")
  let zone = query_ffi(container.as_any(), "[data-droptarget]")
  real_event_ffi(chip, "dragstart")
  real_event_ffi(zone, "dragover")
  real_event_ffi(zone, "drop")
  real_event_ffi(chip, "dragend")
  assert_true(field_v(a, "landed_kind") == Str("chip"))
}

///|
priv struct SmokeEmptyState {} derive(Default)

///|
priv struct DropBoardState {
  landed_kind : String
}

///|
/// A real CANCELABLE click, answering whether the browser recorded a
/// preventDefault against it.
extern "js" fn click_default_prevented_ffi(node : @core.Any) -> Bool =
  #|(n) => {
  #|  const win = n.ownerDocument.defaultView;
  #|  const ev = new win.Event("click", { bubbles: true, cancelable: true });
  #|  n.dispatchEvent(ev);
  #|  return !!ev.defaultPrevented;
  #|}

///|
extern "js" fn attach_to_body_ffi(node : @core.Any, doc : @core.Any) -> Unit =
  #|(n, d) => d.body.appendChild(n)

///|
/// Put a PLAIN DOM listener above the app's mount, so a test can tell whether
/// an event left it.
extern "js" fn watch_document_clicks_ffi(doc : @core.Any) -> Unit =
  #|(d) => {
  #|  d.defaultView.__outerSeen = false;
  #|  d.addEventListener("click", () => {
  #|    d.defaultView.__outerSeen = true;
  #|  });
  #|}

///|
extern "js" fn outer_seen_ffi(doc : @core.Any) -> Bool =
  #|(d) => !!d.defaultView.__outerSeen

///|
priv struct EffectsState {
  n : Int
}

///|
fn effects_comp() -> @component.Component {
  @component.component(
    views={
      "main": @anode.View::new(
        "main",
        raw_view="<div><button class=\"plain\" @on.click=\"bump\">+</button><button class=\"prevented\" @on.click+prevent=\"bump\">p</button><button class=\"stopped\" @on.click+stop=\"bump\">s</button><button class=\"gated\" @on.click+ctrl+prevent=\"bump\">g</button></div>",
      ),
    },
    name="Effects",
    init=EffectsState::{ n: 0, },
    update=(s : EffectsState, msg, _ctx) => {
      match msg {
        Receive("bump", _) => Next({ n: s.n + 1, })
        _ => Unhandled
      }
    },
  )
}

///|
impl @component.Fields for EffectsState with fn encode(s) {
  { "n": Num(s.n.to_double()) }
}

///|
impl @component.Fields for EffectsState with fn decode(f) {
  guard f.get("n") is Some(Num(v)) else { return None }
  Some({ n: v.to_int(), })
}

///|
impl @component.Fields for EffectsState with fn schema() {
  @component.SchemaInfo::new(fingerprint="smoke_effects_state", fields=[
    @component.FieldInfo::new("n", TyInt(width=32, signed=true)),
  ])
}

///|
test "browser: +prevent calls preventDefault when the handler runs" {
  let window = @test_utils.create_happy_window()
  let doc = window.document()
  let container = @bdom.BrowserNode::from_element(doc.createElement("div"))
  let scope = @component.ComponentStack::new()
  scope.register_components([effects_comp()])
  guard scope.lookup_component("Effects") is Some(c) else { fail("no Effects") }
  let a = @app.App::new(scope, c.make(Map([])), container, @bdom.opts_for(doc))
  a.start()
  @browser.install(a)
  // The guarded one: plain click, ctrl missing — the handler never runs, so
  // neither does its effect. The browser default survives.
  let gated = query_ffi(container.as_any(), ".gated")
  assert_false(click_default_prevented_ffi(gated))
  assert_true(field_v(a, "n") == Num(0))
  // The prevented one: the handler ran AND the default was prevented.
  let prevented = query_ffi(container.as_any(), ".prevented")
  assert_true(click_default_prevented_ffi(prevented))
  assert_true(field_v(a, "n") == Num(1))
  // The plain one: no modifier, no prevention.
  assert_false(
    click_default_prevented_ffi(query_ffi(container.as_any(), ".plain")),
  )
}

///|
test "browser: +stop keeps the event from leaving the app's mount" {
  // One delegated listener per app sits on the mount, so by the time a
  // handler runs the event has ALREADY bubbled to it — +stop cannot un-ring
  // that bell, and the component's own handler still fires. What it stops is
  // everything ABOVE the mount: a host page's document listener, an outer
  // shell's delegated dispatch. That is what this pins.
  let window = @test_utils.create_happy_window()
  let doc = window.document()
  let container = @bdom.BrowserNode::from_element(doc.createElement("div"))
  attach_to_body_ffi(container.as_any(), doc.as_any())
  watch_document_clicks_ffi(doc.as_any())
  let scope = @component.ComponentStack::new()
  scope.register_components([effects_comp()])
  guard scope.lookup_component("Effects") is Some(c) else { fail("no Effects") }
  let a = @app.App::new(scope, c.make(Map([])), container, @bdom.opts_for(doc))
  a.start()
  @browser.install(a)
  // The stopped one: the component's own handler ran, the outside saw nothing.
  let stopped = query_ffi(container.as_any(), ".stopped")
  real_click_ffi(stopped)
  assert_true(field_v(a, "n") == Num(1))
  assert_false(outer_seen_ffi(doc.as_any()))
  // The plain one: the outside sees it.
  real_click_ffi(query_ffi(container.as_any(), ".plain"))
  assert_true(field_v(a, "n") == Num(2))
  assert_true(outer_seen_ffi(doc.as_any()))
}

///|
impl @component.Fields for SmokeCounterState with fn encode(s) {
  { "n": Num(s.n.to_double()), "label": Str(s.label) }
}

///|
impl @component.Fields for SmokeCounterState with fn decode(f) {
  guard f.get("n") is Some(Num(n_n)) else { return None }
  let v_n = n_n.to_int()
  guard f.get("label") is Some(Str(v_label)) else { return None }
  Some({ n: v_n, label: v_label, })
}

///|
impl @component.Fields for SmokeEmptyState with fn encode(_s) {
  Map([])
}

///|
impl @component.Fields for SmokeEmptyState with fn decode(_f) {
  Some(Default::default())
}

///|
impl @component.Fields for DropBoardState with fn encode(s) {
  { "landed_kind": Str(s.landed_kind) }
}

///|
impl @component.Fields for DropBoardState with fn decode(f) {
  guard f.get("landed_kind") is Some(Str(v_landed_kind)) else { return None }
  Some({ landed_kind: v_landed_kind, })
}

///|
impl @component.Fields for SmokeCounterState with fn schema() {
  @component.SchemaInfo::new(fingerprint="smoke_counter_state", fields=[
    @component.FieldInfo::new("n", TyInt(width=32, signed=true)),
    @component.FieldInfo::new("label", TyText),
  ])
}

///|
impl @component.Fields for SmokeEmptyState with fn schema() {
  @component.SchemaInfo::new(fingerprint="smoke_empty_state", fields=[])
}

///|
impl @component.Fields for DropBoardState with fn schema() {
  @component.SchemaInfo::new(fingerprint="drop_board_state", fields=[
    @component.FieldInfo::new("landed_kind", TyText),
  ])
}
