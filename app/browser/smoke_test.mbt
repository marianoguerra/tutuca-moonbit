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
} derive(ToJson, FromJson)

///|
fn counter_comp() -> @component.Component {
  @component.component(
    views={
      "main": @anode.View::new(
        "main",
        raw_view="<div><button @on.click=\"bump\">+</button><span><x text=\".n\"></x></span><input :value=\".label\" @on.input=\"setLabel value\"></div>",
      ),
    },
    name="Counter",
    init=SmokeCounterState::{ n: 0, label: "start" },
    update=(s : SmokeCounterState, msg, _ctx) => {
      match msg {
        Input("bump", _) => Some({ ..s, n: s.n + 1 })
        _ => None
      }
    },
  )
}

///|
fn field_v(a : @app.App[@bdom.BrowserNode], name : String) -> @tutuca.Value {
  match @tutuca.Path::new(steps=[FieldStep(name)]).lookup(a.transactor.root) {
    Some(n) => n.as_value().unwrap_or(Null)
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
    init=SmokeEmptyState::{  },
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
        raw_view="<div><span draggable=\"true\" data-dragtype=\"chip\">drag me</span><div data-droptarget=\"\" @on.drop=\"landed dragInfo\">zone</div></div>",
      ),
    },
    name="DropBoard",
    init=DropBoardState::{ landed_kind: "" },
    update=(_s : DropBoardState, msg, _ctx) => {
      match msg {
        Input("landed", [Obj(info), ..]) =>
          match info.obj_field("type") {
            Some(Str(kind)) => Some({ landed_kind: kind })
            _ => None
          }
        _ => None
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
priv struct SmokeEmptyState {} derive(ToJson, FromJson)

///|
priv struct DropBoardState {
  landed_kind : String
} derive(ToJson, FromJson)
