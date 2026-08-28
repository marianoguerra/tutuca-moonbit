// `components_at`: the component ancestry under an element.
//
// A different question from `from_node_and_event_name`'s, and the tests are
// about the difference: that one answers "where would a click go" and stops at
// the first component that would run one, clearing the steps below it. This one
// answers "what is this", which is every component from the root down, whether
// any of them handles anything or not.

///|
fn path_labels(cs : Array[Crossing]) -> Array[String] {
  cs.map(c => {
    let l = c.path.to_transaction_path().to_label()
    if l == "" {
      "(root)"
    } else {
      l
    }
  })
}

///|
test "a node in the root component has one crossing, at the root" {
  let reg = ViewRegistry::new()
  reg.add("main", "<div><button @on.click=\"doIt\">go</button></div>")
  let container = mount(reg, Map({ "title": Str("t") }))
  guard find_el(container, "BUTTON") is Some(btn) else { fail("no button") }
  assert_eq(path_labels(components_at(btn, container, reg)), ["(root)"])
}

///|
/// The whole chain, outermost first: this is what a picker offers, and offering
/// only the innermost would be offering the one place a person can already see.
test "a node inside a child names both components, outermost first" {
  let reg = ViewRegistry::new()
  reg.add("main", "<div><x render=\".child\" as=\"detail\"></x></div>")
  reg.add("detail", "<button @on.click=\"hit\">x</button>")
  let state : @tutuca.Value = Map({ "child": Map({ "name": Str("c1") }) })
  let container = mount(reg, state)
  guard find_el(container, "BUTTON") is Some(btn) else { fail("no button") }
  let cs = components_at(btn, container, reg)
  assert_eq(path_labels(cs), ["(root)", "child"])
  // Each path resolves to the component it names, which is what makes it
  // usable as a place to cut a recording to.
  assert_eq(
    cs[1].path.to_transaction_path().lookup(state),
    Some(state.field("child")),
  )
}

///|
/// Handlers are not consulted at all, which is the point: a picker offers a
/// component because it exists, not because it happens to answer clicks.
test "a component with no handler is still named" {
  let reg = ViewRegistry::new()
  reg.add("main", "<div><x render=\".child\" as=\"detail\"></x></div>")
  reg.add("detail", "<span>quiet</span>")
  let container = mount(reg, Map({ "child": Map({ "name": Str("c1") }) }))
  guard find_el(container, "SPAN") is Some(span) else { fail("no span") }
  assert_eq(path_labels(components_at(span, container, reg)), [
    "(root)", "child",
  ])
  // The event walk gives up here, and correctly so — there is nothing to run.
  assert_true(from_node_and_event_name(span, "click", container, reg) is None)
}

///|
/// A keyed row is the case a relocation picker is FOR: "this row", not "the
/// list", and not "the app".
test "a row inside a loop names the row it is" {
  let reg = ViewRegistry::new()
  reg.add(
    "main", "<ul><li @each=\".items\"><x render-it as=\"item\"></x></li></ul>",
  )
  reg.add("item", "<button @on.click=\"pick\">x</button>")
  let state : @tutuca.Value = Map({
    "items": Map({ "a": Map({ "id": Str("a") }), "b": Map({ "id": Str("b") }) }),
  })
  let container = mount(reg, state)
  guard find_el(container, "BUTTON", nth=1) is Some(btn) else {
    fail("no second button")
  }
  let cs = components_at(btn, container, reg)
  assert_eq(path_labels(cs), ["(root)", "items[b]"])
  let want = state.field("items").item(KStr("b"), default=Null)
  assert_eq(cs[1].path.to_transaction_path().lookup(state), Some(want))
}

///|
/// Outside the app is a real answer and not a failure: a click on the page's
/// own chrome is a click on nothing the app rendered.
test "a node outside the app names nothing" {
  let reg = ViewRegistry::new()
  reg.add("main", "<div><button @on.click=\"doIt\">go</button></div>")
  let container = mount(reg, Map({ "title": Str("t") }))
  assert_eq(components_at(container, container, reg).length(), 0)
}
