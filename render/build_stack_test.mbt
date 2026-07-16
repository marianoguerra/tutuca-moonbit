// Stack rebuild tests (ports of the buildStack-through-clicks cases in
// test/path.test.js): reconstruct a path from a rendered DOM, rebuild the
// stack, and check the handler-visible binds — including the frame-boundary
// invariant (@key/@value must NOT leak into a child component).

///|
fn rebuilt(
  reg : @render.ViewRegistry,
  state : @tutuca.Value,
  container : @memdom.MemNode,
  btn : @memdom.MemNode,
) -> @render.RenderStack raise {
  guard @render.from_node_and_event_name(btn, "click", container, reg)
    is Some(ed) else {
    fail("no event info")
  }
  let stack = @render.RenderStack::new(state)
  guard @render.build_stack(ed.path.to_transaction_path(), stack) is Some(st) else {
    fail("stack rebuild failed")
  }
  st
}

///|
test "@each binds are visible to a handler in the SAME component" {
  let reg = @render.ViewRegistry::new()
  reg.add(
    "main", "<ul><li @each=\".items\"><button @on.click=\"pick\">x</button></li></ul>",
  )
  let state : @tutuca.Value = Map({
    "items": Map({ "a": Str("first"), "b": Str("second") }),
  })
  let container = mount(reg, state)
  guard find_el(container, "BUTTON", nth=1) is Some(btn) else {
    fail("no second button")
  }
  let st = rebuilt(reg, state, container, btn)
  // the EachBindStep scope replays the renderer's {key, value} binds
  assert_true(@tutuca.Stack::lookup_bind(st, "key") is Str("b"))
  assert_true(@tutuca.Stack::lookup_bind(st, "value") is Str("second"))
  // frame-only: `it` stays the component value (JS EachBindStep pass-through)
  assert_true(st.it == state)
}

///|
test "frame boundary: @key/@value do NOT leak into a rendered child component" {
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
  let st = rebuilt(reg, state, container, btn)
  // the item scope sits BELOW the render-it frame: invisible to the child
  assert_true(@tutuca.Stack::lookup_bind(st, "key") is Null)
  assert_true(@tutuca.Stack::lookup_bind(st, "value") is Null)
  // but `it` IS the item the component rendered
  assert_true(st.it == item_b)
}

///|
test "@enrich-with scope binds are replayed by ScopeBindStep" {
  let reg = @render.ViewRegistry::new()
  reg.add(
    "main", "<div @enrich-with=\"info\"><button @on.click=\"go\">x</button></div>",
  )
  let state : @tutuca.Value = Map({
    "info": Fn(_args => Map({ "label": Str("scoped") })),
  })
  let container = mount(reg, state)
  guard find_el(container, "BUTTON") is Some(btn) else { fail("no button") }
  let st = rebuilt(reg, state, container, btn)
  assert_true(@tutuca.Stack::lookup_bind(st, "label") is Str("scoped"))
  assert_true(st.it == state)
}

///|
test "@each + @enrich-with: enriched binds replay per item" {
  let reg = @render.ViewRegistry::new()
  reg.add(
    "main", "<ul><li @each=\".items\" @enrich-with=\"decorate\"><button @on.click=\"go\">x</button></li></ul>",
  )
  let state : @tutuca.Value = Map({
    "items": List([Str("x"), Str("y")]),
    "decorate": Fn(args => {
      match args {
        [_, Map(binds), _key, Str(v), _] => {
          binds["label"] = Str("\{v}!")
          binds["value"] = Str("clobbered") // must be restored
          Null
        }
        _ => Null
      }
    }),
  })
  let container = mount(reg, state)
  guard find_el(container, "BUTTON", nth=1) is Some(btn) else {
    fail("no second button")
  }
  let st = rebuilt(reg, state, container, btn)
  assert_true(@tutuca.Stack::lookup_bind(st, "label") is Str("y!"))
  assert_true(@tutuca.Stack::lookup_bind(st, "key") is Num(1))
  assert_true(@tutuca.Stack::lookup_bind(st, "value") is Str("y"))
}

///|
test "a stale path fails the rebuild instead of building a wrong stack" {
  let reg = @render.ViewRegistry::new()
  reg.add("main", "<div><x render=\".child\" as=\"detail\"></x></div>")
  reg.add("detail", "<button @on.click=\"hit\">x</button>")
  let state : @tutuca.Value = Map({ "child": Map({}) })
  let container = mount(reg, state)
  guard find_el(container, "BUTTON") is Some(btn) else { fail("no button") }
  guard @render.from_node_and_event_name(btn, "click", container, reg)
    is Some(ed) else {
    fail("no event info")
  }
  // the state moved on: the child is gone
  let gone : @tutuca.Value = Map({})
  let stack = @render.RenderStack::new(gone)
  assert_true(@render.build_stack(ed.path.to_transaction_path(), stack) is None)
}
