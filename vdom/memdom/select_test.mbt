// Port of test/vdom-select.test.js. memdom implements minimal <select>
// semantics (assigning value selects the first matching option), which makes
// the renderer's value-after-children ordering and the morph-time value
// re-application observable.

///|
fn opt(value : String) -> @vdom.Vdom {
  @vdom.h("option", attrs={ "value": Str(value) }, childs=[@vdom.text(value)])
}

///|
fn sel(value : String, options : Array[@vdom.Vdom]) -> @vdom.Vdom {
  @vdom.h("select", attrs={ "value": Str(value) }, childs=options)
}

///|
test "initial render selects the matching option" {
  let dom = to_dom(sel("b", [opt("a"), opt("b"), opt("c")]))
  assert_true(dom.get_property("value") is Some(Str("b")))
  assert_true(dom.childs[1].get_property("selected") is Some(Bool(true)))
  assert_true(dom.childs[0].get_property("selected") is Some(Bool(false)))
}

///|
test "no matching option selects none" {
  let dom = to_dom(sel("z", [opt("a"), opt("b"), opt("c")]))
  assert_true(dom.get_property("value") is Some(Str("")))
  for c in dom.childs {
    assert_false(c.get_property("selected") is Some(Bool(true)))
    // no `selected` attribute is ever written
    assert_true(c.get_attribute("selected") is None)
  }
}

///|
test "morph: changing value updates selection, preserves the select node" {
  let (c, o) = new_env()
  let r1 = @vdom.render(sel("a", [opt("a"), opt("b"), opt("c")]), c, o)
  let first = c.childs[0]
  assert_true(first.childs[0].get_property("selected") is Some(Bool(true)))
  let _ = @vdom.render(sel("c", [opt("a"), opt("b"), opt("c")]), c, o, prev=r1)
  assert_true(physical_equal(c.childs[0], first))
  assert_true(first.get_property("value") is Some(Str("c")))
  assert_true(first.childs[2].get_property("selected") is Some(Bool(true)))
  assert_true(first.childs[0].get_property("selected") is Some(Bool(false)))
}

///|
test "morph reapplies value when a newly-appended option matches" {
  let (c, o) = new_env()
  let r1 = @vdom.render(sel("c", [opt("a"), opt("b")]), c, o)
  let s = c.childs[0]
  assert_true(s.get_property("value") is Some(Str("")))
  // value "c" is NOT in the props diff (unchanged), but the SELECT branch
  // re-applies it after the option children morph
  let _ = @vdom.render(sel("c", [opt("a"), opt("b"), opt("c")]), c, o, prev=r1)
  assert_true(physical_equal(c.childs[0], s))
  assert_true(s.get_property("value") is Some(Str("c")))
  assert_true(s.childs[2].get_property("selected") is Some(Bool(true)))
}

///|
test "morph: removing the selected option resets value" {
  let (c, o) = new_env()
  let r1 = @vdom.render(sel("b", [opt("a"), opt("b"), opt("c")]), c, o)
  let s = c.childs[0]
  assert_true(s.get_property("value") is Some(Str("b")))
  let _ = @vdom.render(sel("b", [opt("a"), opt("c")]), c, o, prev=r1)
  assert_true(physical_equal(c.childs[0], s))
  assert_true(s.get_property("value") is Some(Str("")))
}

///|
test "morph reorders options while value stays the same" {
  let (c, o) = new_env()
  let r1 = @vdom.render(sel("b", [opt("a"), opt("b"), opt("c")]), c, o)
  let s = c.childs[0]
  let _ = @vdom.render(sel("b", [opt("c"), opt("b"), opt("a")]), c, o, prev=r1)
  assert_true(s.get_property("value") is Some(Str("b")))
  assert_true(s.childs[1].get_property("selected") is Some(Bool(true)))
}

///|
test "non-select elements with a value prop are unaffected" {
  let dom = to_dom(@vdom.h("input", attrs={ "value": Str("x") }))
  assert_true(dom.get_property("value") is Some(Str("x")))
}
