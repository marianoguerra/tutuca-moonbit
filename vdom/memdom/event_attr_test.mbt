// What happens to an attribute literally named `onclick`.
//
// Not a construct tutuca asks anyone to write — a handler is `@on.click`,
// which compiles to `data-eid` and never reaches vdom as an `on*` name. These
// pin the OTHER path: a view (or a guest bundle) that writes the content
// attribute directly, and what `set_prop` then does with it.
//
// `anode/sanitize` refuses the name at registration, but only for a dyncomp
// guest — `Policy::check_view` has one call site. A plain tutuca app runs no
// static pass, so vdom's routing is the whole of its behaviour here. See
// docs/sanitizer.md, "Order of work".

///|
test "onclick with a string value takes the property path, not the attribute" {
  // The routing that makes this safe in a browser: `"onclick" in div` is true,
  // so set_prop assigns the STRING to the `.onclick` property, and a browser
  // installs a handler there only from a function. The content attribute --
  // which a browser WOULD compile -- is never written.
  let dom = to_dom(
    @vdom.h("div", attrs={ "onclick": Str("alert(1)") }, childs=[
      @vdom.text("x"),
    ]),
  )
  assert_true(dom.get_attribute("onclick") is None)
  assert_true(dom.get_property("onclick") is Some(Str("alert(1)")))
}

///|
test "the onclick property path is an accident of routing, not a defense" {
  // set_prop's property branch is `if node.set_property(name, v) { return }`
  // (vdom/to_dom.mbt) -- it falls through to set_attribute when the assignment
  // fails. memdom's `throwingProp` sentinel is that failure, and it shows what
  // the fallthrough writes: a live content attribute.
  //
  // So nothing here REMOVES the name; a browser's `.onclick =` happening to
  // ignore a string is what makes it inert. That is why the fix is dropping
  // the name (statically for a guest, in a filter for an app) rather than
  // anything in this file.
  let dom = to_dom(@vdom.h("div", attrs={ "throwingProp": Str("alert(1)") }))
  assert_true(dom.get_attribute("throwingProp") is Some("alert(1)"))
}

///|
test "onclick on a namespaced element IS written as a content attribute" {
  // `uses_prop` is `!namespaced && …` (vdom/to_dom.mbt), so an SVG or MathML
  // element routes EVERY attribute through set_attribute -- including this
  // one. SVG elements fire click events and honour the content attribute, so
  // unlike the HTML case above there is no accident of routing saving it.
  //
  // Pinned as the current behaviour, not as intended behaviour: the static
  // pass refuses the name for a guest, and Stage 2 of docs/sanitizer.md is
  // what covers a plain app.
  let dom = to_dom(
    @vdom.h("svg", attrs={ "onclick": Str("alert(1)") }, childs=[
      @vdom.h("circle", ns=Svg, attrs={ "onload": Str("alert(2)") }),
    ]),
  )
  assert_true(dom.ns is Some(Svg))
  assert_true(dom.get_attribute("onclick") is Some("alert(1)"))
  assert_true(dom.childs[0].get_attribute("onload") is Some("alert(2)"))
}

///|
test "never_assign is not the fix: it forces the attribute path" {
  // Adding `onclick` to vdom's never_assign set would make `uses_prop` false
  // and take the branch below on a PLAIN html element too -- turning the inert
  // property assignment into a live content attribute. Strictly worse. The
  // members of that set are names whose attribute form is the correct one,
  // which is not true of an event handler.
  let dom = to_dom(@vdom.h("td", attrs={ "colSpan": @vdom.AttrValue::int(3) }))
  assert_true(dom.get_attribute("colSpan") is Some("3"))
  assert_true(dom.get_property("colSpan") is None)
}

///|
test "removing an on* attribute across a re-render clears the property" {
  // The removal path matters for a filter that drops the name on a later
  // render: the stale handler must not survive on the element.
  let c = morphed(
    @vdom.h("div", attrs={ "onclick": Str("alert(1)") }),
    @vdom.h("div"),
  )
  let el = c.childs[0]
  assert_true(el.get_attribute("onclick") is None)
  assert_true(el.get_property("onclick") is Some(Str("")))
}
