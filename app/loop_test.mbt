// App-loop tests: the full interactive cycle on the in-memory DOM — start,
// dispatch DomEvents (values, keys, modifiers), automatic re-render + morph.

///|
priv struct EditorState {
  text : String
  count : Int
} derive(ToJson, FromJson)

///|
fn text_editor() -> @component.Component {
  @component.component(
    views={
      "main": @anode.View::new(
        "main",
        raw_view="<div><input :value=\".text\" @on.input=\"setText value\" @on.keydown+send=\"setText 'sent'\"><p><x text=\".text\"></x></p><button @on.click+ctrl=\"setCount valueAsInt\">n</button></div>",
      ),
    },
    name="Editor",
    init=EditorState::{ text: "start", count: 0 },
  )
}

///|
fn mk_app(
  comp : @component.Component,
  args : Map[String, @tutuca.Value],
) -> (@app.App[@memdom.MemNode], @memdom.MemNode) raise {
  let scope = @component.ComponentStack::new()
  scope.register_components([comp])
  let app_scope = scope // compile happens in App::new
  guard app_scope.lookup_component(comp.name) is Some(c) else {
    fail("component missing")
  }
  let doc = @memdom.document()
  let container = @vdom.DomNode::create_element(doc, "DIV", None, None)
  // make() needs compiled specs? fields exist pre-compile; FComp needs scope
  let a = @app.App::new(
    app_scope,
    c.make(args),
    container,
    @vdom.RenderOpts::new(doc),
  )
  a.start()
  (a, container)
}

///|
fn field_v(a : @app.App[@memdom.MemNode], name : String) -> @tutuca.Value {
  match @tutuca.Path::new(steps=[FieldStep(name)]).lookup(a.transactor.root) {
    Some(n) => n.as_value().unwrap_or(Null)
    None => Null
  }
}

///|
test "two-way input: value flows in, re-render morphs the DOM" {
  let (a, container) = mk_app(text_editor(), Map([]))
  assert_true(container.to_html().contains("start"))
  guard find_el(container, "INPUT") is Some(input) else { fail("no input") }
  assert_true(
    a.dispatch(input, @render.DomEvent::new(name="input", value=Str("hello"))),
  )
  assert_true(field_v(a, "text") == Str("hello"))
  // the on_change subscription re-rendered (morph, same container)
  assert_true(container.to_html().contains("hello"))
  assert_false(container.to_html().contains("start"))
  // the input's :value follows the field — as the live IDL property (JS
  // `value` never reflects to the attribute)
  guard find_el(container, "INPUT") is Some(input2) else { fail("no input") }
  assert_true(input2.get_property("value") == Some(Str("hello")))
}

///|
test "keydown+send modifier gates on Enter" {
  let (a, container) = mk_app(text_editor(), Map([]))
  guard find_el(container, "INPUT") is Some(input) else { fail("no input") }
  // a plain key: gated out, nothing changes
  assert_true(a.dispatch(input, @render.DomEvent::new(name="keydown", key="a")))
  assert_true(field_v(a, "text") == Str("start"))
  // Enter passes
  assert_true(
    a.dispatch(input, @render.DomEvent::new(name="keydown", key="Enter")),
  )
  assert_true(field_v(a, "text") == Str("sent"))
}

///|
test "click+ctrl gate and valueAsInt coercion" {
  let (a, container) = mk_app(text_editor(), Map([]))
  guard find_el(container, "BUTTON") is Some(btn) else { fail("no button") }
  // without ctrl: gated out
  assert_true(
    a.dispatch(btn, @render.DomEvent::new(name="click", value=Str("42"))),
  )
  assert_true(field_v(a, "count") == Num(0))
  // with ctrl: valueAsInt parses the string
  assert_true(
    a.dispatch(
      btn,
      @render.DomEvent::new(name="click", value=Str("42"), ctrl_or_cmd=true),
    ),
  )
  assert_true(field_v(a, "count") == Num(42))
  // unparsable -> Null -> field coercion keeps the default
  assert_true(
    a.dispatch(
      btn,
      @render.DomEvent::new(name="click", value=Str("abc"), ctrl_or_cmd=true),
    ),
  )
  assert_true(field_v(a, "count") == Num(0))
}

///|
test "@each `value` bind shadows the DOM event's value" {
  let list = @component.component(
    views={
      "main": @anode.View::new(
        "main",
        raw_view="<ul><li @each=\".items\"><button @on.click=\"pick value\">x</button></li></ul>",
      ),
    },
    name="Picker",
    init=PickerState::{ items: [], picked: "" },
    update=(s : PickerState, msg, _ctx) => {
      match msg {
        Input("pick", [Str(p)]) => Some({ ..s, picked: p })
        _ => None
      }
    },
  )
  let (a, container) = mk_app(list, {
    "items": List([Str("alpha"), Str("beta")]),
  })
  guard find_el(container, "BUTTON", nth=1) is Some(btn) else {
    fail("no second button")
  }
  // the event carries a value, but the @each item bind must win
  assert_true(
    a.dispatch(
      btn,
      @render.DomEvent::new(name="click", value=Str("from-event")),
    ),
  )
  assert_true(field_v(a, "picked") == Str("beta"))
}

///|
test "event_names collects every listened event across views" {
  let scope = @component.ComponentStack::new()
  scope.register_components([text_editor()])
  let doc = @memdom.document()
  let container = @vdom.DomNode::create_element(doc, "DIV", None, None)
  guard scope.lookup_component("Editor") is Some(c) else { fail("no Editor") }
  let a = @app.App::new(
    scope,
    c.make(Map([])),
    container,
    @vdom.RenderOpts::new(doc),
  )
  let names = a.event_names()
  assert_true(names.contains("input"))
  assert_true(names.contains("keydown"))
  assert_true(names.contains("click"))
}

///|
test "batching: a cascade of swaps renders exactly once per dispatch" {
  let chatty = @component.component(
    views={
      "main": @anode.View::new(
        "main",
        raw_view="<div><button @on.click=\"go\">x</button><span><x text=\".n\"></x></span></div>",
      ),
    },
    name="Chatty",
    init=ChattyState::{ n: 0 },
    update=(s : ChattyState, msg, ctx) => {
      match msg {
        Input("go", _) => {
          // three follow-up sends: four root swaps in one drained cascade
          ctx.send("bump", [])
          ctx.send("bump", [])
          ctx.send("bump", [])
          Some({ n: s.n + 1 })
        }
        Receive("bump", _) => Some({ n: s.n + 1 })
        _ => None
      }
    },
  )
  let (a, container) = mk_app(chatty, Map([]))
  assert_eq(a.render_count, 1) // the initial render
  guard find_el(container, "BUTTON") is Some(btn) else { fail("no button") }
  assert_true(a.dispatch(btn, @render.DomEvent::new(name="click")))
  // four state swaps, ONE re-render, final state visible
  assert_eq(a.render_count, 2)
  assert_true(field_v(a, "n") == Num(4))
  assert_true(container.to_html().contains("<span>4</span>"))
}

///|
priv struct PickerState {
  items : Array[String]
  picked : String
} derive(ToJson, FromJson)

///|
priv struct ChattyState {
  n : Int
} derive(ToJson, FromJson)
