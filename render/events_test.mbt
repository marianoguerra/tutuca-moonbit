// End-to-end event-path reconstruction (ports of test/path.test.js): render
// real views to the in-memory DOM — the metas in the tree are the renderer's
// own output — then reconstruct from a click target and resolve the path
// against the state.

///|
fn find_el(
  root : @memdom.MemNode,
  tag : String,
  nth? : Int = 0,
) -> @memdom.MemNode? {
  let hits : Array[@memdom.MemNode] = []
  fn walk(n : @memdom.MemNode) {
    if n.tag == tag {
      hits.push(n)
    }
    for c in n.childs {
      walk(c)
    }
  }

  walk(root)
  hits.get(nth)
}

///|
/// Render `state` as the app root through `reg` into a fresh container.
fn mount(
  reg : @render.ViewRegistry,
  state : @tutuca.Value,
) -> @memdom.MemNode raise {
  let stack = @render.RenderStack::new(state)
  let ctx = @render.RenderCtx::new(view_resolver=reg)
  guard @render.render_root(state, stack, ctx) is Some(v) else {
    fail("root did not render")
  }
  let doc = @memdom.document()
  let container = @vdom.DomNode::create_element(doc, "DIV", None, None)
  let _ = @vdom.render(v, container, @vdom.RenderOpts::new(doc))
  container
}

///|
fn resolve_leaf(
  ed : @render.EventDispatch,
  state : @tutuca.Value,
) -> @tutuca.Value {
  let root : &@tutuca.PathNode = state
  match ed.path.to_transaction_path().lookup(root) {
    Some(n) => n.as_value().unwrap_or(Null)
    None => Null
  }
}

///|
test "click on the root component: empty path, handlers found" {
  let reg = @render.ViewRegistry::new()
  reg.add("main", "<div><button @on.click=\"doIt\">go</button></div>")
  let state : @tutuca.Value = Map({ "title": Str("t") })
  let container = mount(reg, state)
  guard find_el(container, "BUTTON") is Some(btn) else { fail("no button") }
  guard @render.from_node_and_event_name(btn, "click", container, reg)
    is Some(ed) else {
    fail("no event info")
  }
  assert_eq(ed.handlers.length(), 1)
  assert_eq(ed.handlers[0].name, "click")
  assert_eq(ed.path.items.length(), 0)
  assert_true(resolve_leaf(ed, state) == state)
}

///|
test "no handler for the event name aborts (stop_on_no_event)" {
  let reg = @render.ViewRegistry::new()
  reg.add("main", "<div><button @on.click=\"doIt\">go</button></div>")
  let container = mount(reg, Map(Map([])))
  guard find_el(container, "BUTTON") is Some(btn) else { fail("no button") }
  assert_true(
    @render.from_node_and_event_name(btn, "keydown", container, reg) is None,
  )
  // stop_on_no_event=false still returns the path (two-way binds use this)
  guard @render.from_node_and_event_name(
      btn,
      "keydown",
      container,
      reg,
      stop_on_no_event=false,
    )
    is Some(ed) else {
    fail("expected a path")
  }
  assert_eq(ed.handlers.length(), 0)
}

///|
test "click inside a rendered child component: one FieldStep per boundary" {
  let reg = @render.ViewRegistry::new()
  reg.add("main", "<div><x render=\".child\" as=\"detail\"></x></div>")
  reg.add("detail", "<button @on.click=\"hit\">x</button>")
  let child : @tutuca.Value = Map({ "name": Str("c1") })
  let state : @tutuca.Value = Map({ "child": child })
  let container = mount(reg, state)
  guard find_el(container, "BUTTON") is Some(btn) else { fail("no button") }
  guard @render.from_node_and_event_name(btn, "click", container, reg)
    is Some(ed) else {
    fail("no event info")
  }
  assert_eq(ed.handlers.length(), 1)
  assert_true(ed.path.items is [Plain(step=FieldStep("child"), origin=Some(0))])
  assert_true(resolve_leaf(ed, state) == child)
}

///|
test "click on an @each + render-it item resolves the keyed item" {
  let reg = @render.ViewRegistry::new()
  reg.add(
    "main", "<ul><li @each=\".items\"><x render-it as=\"item\"></x></li></ul>",
  )
  reg.add("item", "<button @on.click=\"pick\">x</button>")
  let item_b : @tutuca.Value = Map({ "id": Str("b") })
  let state : @tutuca.Value = Map({
    "items": Map({ "a": Map({ "id": Str("a") }), "b": item_b }),
  })
  let container = mount(reg, state)
  guard find_el(container, "BUTTON", nth=1) is Some(btn) else {
    fail("no second button")
  }
  guard @render.from_node_and_event_name(btn, "click", container, reg)
    is Some(ed) else {
    fail("no event info")
  }
  assert_eq(ed.handlers.length(), 1)
  assert_true(
    ed.path.items
    is [Plain(step=EachRenderItStep(field="items", key=KStr("b")), origin=_)],
  )
  // compact abstracts it to a SeqStep; both address items["b"]
  assert_true(
    ed.path.compact().items
    is [Plain(step=SeqStep(field="items", key=KStr("b")), origin=_)],
  )
  assert_true(resolve_leaf(ed, state) == item_b)
}

///|
test "an @each over a list resolves the indexed item" {
  let reg = @render.ViewRegistry::new()
  reg.add(
    "main", "<ul><li @each=\".items\"><x render-it as=\"item\"></x></li></ul>",
  )
  reg.add("item", "<button @on.click=\"pick\">x</button>")
  let state : @tutuca.Value = Map({
    "items": List([Str("first"), Str("second")]),
  })
  let container = mount(reg, state)
  guard find_el(container, "BUTTON", nth=1) is Some(btn) else {
    fail("no second button")
  }
  guard @render.from_node_and_event_name(btn, "click", container, reg)
    is Some(ed) else {
    fail("no event info")
  }
  assert_true(
    ed.path.items
    is [Plain(step=EachRenderItStep(field="items", key=KInt(1)), origin=_)],
  )
  assert_true(resolve_leaf(ed, state) == Str("second"))
}

///|
test "a scope boundary contributes a frame-only ScopeBindStep" {
  let reg = @render.ViewRegistry::new()
  reg.add(
    "main", "<div @enrich-with=\"info\"><button @on.click=\"go\">x</button></div>",
  )
  let state : @tutuca.Value = Map({
    "info": Fn(_args => Map({ "label": Str("s") })),
  })
  let container = mount(reg, state)
  guard find_el(container, "BUTTON") is Some(btn) else { fail("no button") }
  guard @render.from_node_and_event_name(btn, "click", container, reg)
    is Some(ed) else {
    fail("no event info")
  }
  assert_eq(ed.handlers.length(), 1)
  assert_true(ed.path.items is [Plain(step=ScopeBindStep(val=_), origin=_)])
  // frame-only: the transaction path still resolves to the root value
  assert_true(resolve_leaf(ed, state) == state)
}
