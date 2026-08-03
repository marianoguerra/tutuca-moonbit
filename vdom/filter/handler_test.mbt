///| The event-handler rule, and `Baseline` composing it with the URL rule.
///
/// This is a NAME rule, unlike everything in `url_test.mbt`. It lives at render
/// time only because the pass that settles names runs for dyncomp guests and
/// nobody else — see the header of `handler.mbt`.

///|
fn nel(
  tag : String,
  attrs : Map[String, @vdom.AttrValue],
  ns? : @vdom.Ns,
  childs? : Array[@vdom.Vdom] = [],
) -> @vdom.Vdom {
  Node({ tag, attrs, childs, key: None, ns })
}

///|
fn handler_filtered(tree : @vdom.Vdom) -> (@vdom.Vdom, Array[String]) {
  let f = HandlerFilter::new()
  f.filter_tree(tree)
  (tree, f.take_reports().map(Dropped::to_string))
}

///|
test "the prefix predicate matches handlers and nothing else" {
  for name in ["onclick", "onload", "onerror", "ONCLICK", "onAfterPrint"] {
    assert_true(is_event_handler_attr(name))
  }
  // Two characters is not a handler, and neither is a name that merely starts
  // with the letters.
  for name in ["on", "o", "", "one", "class", "href", "data-onclick"] {
    if name == "one" {
      // `one` DOES match the prefix test — three characters beginning `on`.
      // Not an HTML attribute, so the over-match costs nothing, and erring
      // this way is deliberate for a remove rule.
      assert_true(is_event_handler_attr(name))
      continue
    }
    assert_false(is_event_handler_attr(name))
  }
}

///|
test "handler attributes are dropped from a plain element" {
  let (tree, reports) = handler_filtered(
    nel("div", { "onclick": Str("alert(1)"), "class": Str("card") }),
  )
  guard tree is Node(el) else { fail("expected an element") }
  assert_true(el.attrs.get("onclick") is None)
  // Everything else survives: the rule drops the attribute, not the element.
  assert_true(el.attrs.get("class") is Some(Str("card")))
  debug_inspect(
    reports,
    content=(
      #|["dropped onclick on <div>: event-handler attributes are not something a view may set (alert(1))"]
    ),
  )
}

///|
test "handler attributes are dropped from a NAMESPACED element" {
  // The case that motivates the rule: `uses_prop` is `!namespaced && …`, so
  // these would reach the DOM as live content attributes with no accident of
  // routing to make them inert. See vdom/memdom/event_attr_test.mbt.
  let (tree, reports) = handler_filtered(
    nel("svg", { "onclick": Str("alert(1)") }, ns=Svg, childs=[
      nel("circle", { "onload": Str("alert(2)"), "r": Str("5") }, ns=Svg),
    ]),
  )
  guard tree is Node(el) else { fail("expected an element") }
  assert_true(el.attrs.get("onclick") is None)
  guard el.childs[0] is Node(circle) else { fail("expected an element") }
  assert_true(circle.attrs.get("onload") is None)
  assert_true(circle.attrs.get("r") is Some(Str("5")))
  inspect(reports.length(), content="2")
}

///|
test "a handler is dropped whatever the value's type" {
  // By name and regardless of type, including `Data` — a view cannot express a
  // function, so nothing arriving under this name is a working handler, and a
  // remove rule has no reason to inspect the value.
  let (tree, _) = handler_filtered(
    nel("div", {
      "onclick": Data(Json::string("x")),
      "onfocus": Bool(true),
      "onblur": Html("<b>x</b>"),
    }),
  )
  guard tree is Node(el) else { fail("expected an element") }
  inspect(el.attrs.length(), content="0")
}

///|
test "data-* and aria-* are not handlers" {
  let (tree, reports) = handler_filtered(
    nel("div", {
      "data-eid": @vdom.AttrValue::int(3),
      "data-cid": Str("c1"),
      "aria-label": Str("x"),
    }),
  )
  guard tree is Node(el) else { fail("expected an element") }
  // data-eid is how a rendered element finds its handler list; dropping it
  // would produce a component that renders and then responds to nothing.
  inspect(el.attrs.length(), content="3")
  inspect(reports.length(), content="0")
}

///|
test "Baseline applies both rules in one walk" {
  let f = Baseline::new()
  let tree = nel("a", {
    "href": Str("javascript:alert(1)"),
    "onclick": Str("alert(2)"),
    "title": Str("kept"),
  }, childs=[nel("img", { "src": Str("data:image/png;base64,AAA") })])
  f.filter_tree(tree)
  guard tree is Node(el) else { fail("expected an element") }
  assert_true(el.attrs.get("href") is None)
  assert_true(el.attrs.get("onclick") is None)
  assert_true(el.attrs.get("title") is Some(Str("kept")))
  // `data:` on a media attribute is ordinary and stays.
  guard el.childs[0] is Node(img) else { fail("expected an element") }
  assert_true(img.attrs.get("src") is Some(Str("data:image/png;base64,AAA")))
  // Both logs drain through the one call, URL drops first.
  let reports = f.take_reports().map(Dropped::to_string)
  inspect(reports.length(), content="2")
  assert_true(reports[0].contains("href"))
  assert_true(reports[1].contains("onclick"))
  // Drained, not copied.
  inspect(f.take_reports().length(), content="0")
}

///|
test "reports are bounded" {
  let f = HandlerFilter::new(max_reports=2)
  let childs = []
  for i in 0..<10 {
    childs.push(nel("div", { "onclick": Str("h\{i}") }))
  }
  f.filter_tree(nel("div", {}, childs~))
  // Every attribute is still removed; only the LOG is bounded.
  inspect(f.take_reports().length(), content="2")
}

///|
test "a tree with nothing to drop is left alone" {
  let f = Baseline::new()
  let tree = nel("div", { "class": Str("x") }, childs=[
    Text("hello"),
    Comment("§Comp§"),
    Fragment([nel("span", { "id": Str("s") })]),
  ])
  f.filter_tree(tree)
  guard tree is Node(el) else { fail("expected an element") }
  inspect(el.attrs.length(), content="1")
  inspect(f.take_reports().length(), content="0")
}
