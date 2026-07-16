// Port of test/vdom-vnode.test.js. JS cases about iterable flattening and
// primitive->VText coercion have no analog here: children are typed
// Array[Vdom] and `text()` is explicit. toDom / render cases live in
// memdom's test suites.

///|
test "node_type parity with DOM nodeType" {
  inspect(@vdom.h("div").node_type(), content="1")
  inspect(@vdom.text("hello").node_type(), content="3")
  inspect(@vdom.comment("hi").node_type(), content="8")
  inspect(@vdom.fragment([]).node_type(), content="11")
}

///|
test "is_equal_to: text nodes" {
  let a = @vdom.text("hello")
  let b = @vdom.text("hello")
  assert_true(a.is_equal_to(b))
  assert_true(b.is_equal_to(a))
  assert_false(a.is_equal_to(@vdom.text("world")))
  assert_false(a.is_equal_to(@vdom.comment("hello")))
}

///|
test "is_equal_to: comments" {
  assert_true(@vdom.comment("comment").is_equal_to(@vdom.comment("comment")))
  assert_false(@vdom.comment("one").is_equal_to(@vdom.comment("two")))
}

///|
test "is_equal_to: fragments" {
  assert_true(@vdom.fragment([]).is_equal_to(@vdom.fragment([])))
  let a = @vdom.fragment([@vdom.text("hello"), @vdom.text("world")])
  let b = @vdom.fragment([@vdom.text("hello"), @vdom.text("world")])
  assert_true(a.is_equal_to(b))
  assert_false(
    @vdom.fragment([@vdom.text("hello")]).is_equal_to(
      @vdom.fragment([@vdom.text("world")]),
    ),
  )
  assert_false(
    @vdom.fragment([@vdom.text("hello")]).is_equal_to(
      @vdom.fragment([@vdom.text("hello"), @vdom.text("world")]),
    ),
  )
}

///|
test "fragment flattens nested fragment children" {
  let inner = @vdom.fragment([@vdom.text("a"), @vdom.text("b")])
  let outer = @vdom.fragment([@vdom.text("x"), inner, @vdom.text("y")])
  guard outer is Fragment(childs)
  inspect(childs.length(), content="4")
  assert_true(childs[0] is Text("x"))
  assert_true(childs[1] is Text("a"))
  assert_true(childs[2] is Text("b"))
  assert_true(childs[3] is Text("y"))
}

///|
test "h flattens fragment children" {
  let frag = @vdom.fragment([@vdom.text("a"), @vdom.text("b")])
  let node = @vdom.h("div", childs=[@vdom.text("x"), frag, @vdom.text("y")])
  guard node is Node(el)
  inspect(el.childs.length(), content="4")
  assert_true(el.childs[1] is Text("a"))
  assert_true(el.childs[3] is Text("y"))
}

///|
test "is_equal_to: element nodes" {
  assert_true(@vdom.h("div").is_equal_to(@vdom.h("div")))
  assert_false(@vdom.h("div").is_equal_to(@vdom.h("span")))
  let a = @vdom.h("div", attrs={ "className": Str("foo"), "id": Str("bar") })
  let b = @vdom.h("div", attrs={ "className": Str("foo"), "id": Str("bar") })
  assert_true(a.is_equal_to(b))
  assert_false(
    @vdom.h("div", attrs={ "className": Str("foo") }).is_equal_to(
      @vdom.h("div", attrs={ "className": Str("bar") }),
    ),
  )
  assert_false(
    @vdom.h("div", attrs={ "className": Str("foo") }).is_equal_to(
      @vdom.h("div", attrs={ "className": Str("foo"), "id": Str("bar") }),
    ),
  )
}

///|
test "is_equal_to: attrs compare by content, order-insensitive" {
  let a = @vdom.h("div", attrs={ "id": Str("x"), "className": Str("y") })
  let b = @vdom.h("div", attrs={ "className": Str("y"), "id": Str("x") })
  assert_true(a.is_equal_to(b))
}

///|
test "is_equal_to: children" {
  let a = @vdom.h("div", childs=[
    @vdom.h("span", childs=[@vdom.text("hello")]),
    @vdom.h("span", childs=[@vdom.text("world")]),
  ])
  let b = @vdom.h("div", childs=[
    @vdom.h("span", childs=[@vdom.text("hello")]),
    @vdom.h("span", childs=[@vdom.text("world")]),
  ])
  assert_true(a.is_equal_to(b))
  assert_false(
    @vdom.h("div", childs=[@vdom.h("span", childs=[@vdom.text("hello")])]).is_equal_to(
      @vdom.h("div", childs=[@vdom.h("span", childs=[@vdom.text("world")])]),
    ),
  )
  assert_false(
    @vdom.h("div", childs=[@vdom.h("span")]).is_equal_to(
      @vdom.h("div", childs=[@vdom.h("span"), @vdom.h("span")]),
    ),
  )
}

///|
test "is_equal_to: keys and namespaces" {
  assert_false(@vdom.h("div", key="a").is_equal_to(@vdom.h("div", key="b")))
  assert_true(@vdom.h("div", key="a").is_equal_to(@vdom.h("div", key="a")))
  // svg auto-namespace vs an explicitly HTML-namespaced same tag
  let svg = @vdom.h("svg")
  let plain = @vdom.h("svg", ns=Other(@vdom.html_ns))
  assert_false(svg.is_equal_to(plain))
  // element vs text with the same string
  assert_false(@vdom.h("div").is_equal_to(@vdom.text("div")))
}

///|
test "is_equal_to: deeply nested trees" {
  fn tree(last : String) {
    @vdom.h("div", childs=[
      @vdom.h("ul", childs=[
        @vdom.h("li", childs=[@vdom.text("one")]),
        @vdom.h("li", childs=[@vdom.text(last)]),
      ]),
      @vdom.h("p", childs=[@vdom.text("text")]),
    ])
  }

  assert_true(tree("two").is_equal_to(tree("two")))
  assert_false(tree("two").is_equal_to(tree("THREE")))
}

///|
test "h: tag case normalization" {
  guard @vdom.h("span") is Node(span)
  inspect(span.tag, content="SPAN")
  // mixed-case tags are preserved
  guard @vdom.h("linearGradient", ns=Svg) is Node(grad)
  inspect(grad.tag, content="linearGradient")
  // under a namespace, lowercase tags are preserved
  guard @vdom.h("rect", ns=Svg) is Node(rect)
  inspect(rect.tag, content="rect")
}

///|
test "h: svg and math auto-namespace" {
  guard @vdom.h("svg") is Node(svg)
  assert_true(svg.ns is Some(Svg))
  inspect(svg.tag, content="svg")
  guard @vdom.h("SVG") is Node(svg2)
  assert_true(svg2.ns is Some(Svg))
  inspect(svg2.tag, content="svg")
  guard @vdom.h("math") is Node(math)
  assert_true(math.ns is Some(MathMl))
  inspect(math.tag, content="math")
  guard @vdom.h("div") is Node(div)
  assert_true(div.ns is None)
}

///|
test "h: class and for pass through verbatim" {
  guard @vdom.h("div", attrs={ "class": Str("foo") }) is Node(el)
  assert_true(el.attrs.get("class") is Some(Str("foo")))
  assert_true(el.attrs.get("className") is None)
  guard @vdom.h("label", attrs={ "for": Str("input-id") }) is Node(lbl)
  assert_true(lbl.attrs.get("for") is Some(Str("input-id")))
  assert_true(lbl.attrs.get("htmlFor") is None)
}

///|
test "h: data-* and aria-* kept without coercion" {
  guard @vdom.h("div", attrs={
      "data-foo": Str("bar"),
      "data-user-id": AttrValue::int(123),
      "aria-hidden": Bool(true),
      "data-active": Bool(false),
    })
    is Node(el)
  assert_true(el.attrs.get("data-foo") is Some(Str("bar")))
  assert_true(el.attrs.get("data-user-id") is Some(Num(123)))
  assert_true(el.attrs.get("aria-hidden") is Some(Bool(true)))
  assert_true(el.attrs.get("data-active") is Some(Bool(false)))
}

///|
test "h: key and namespace extracted from attrs map" {
  guard @vdom.h("div", attrs={ "key": Str("k1"), "id": Str("x") }) is Node(el)
  assert_true(el.key is Some("k1"))
  assert_true(el.attrs.get("key") is None)
  assert_true(el.attrs.get("id") is Some(Str("x")))
  // labeled argument wins over the attrs entry
  guard @vdom.h("div", attrs={ "key": Str("from-attrs") }, key="labeled")
    is Node(el2)
  assert_true(el2.key is Some("labeled"))
  // numeric keys are coerced like JS String(key)
  guard @vdom.h("div", attrs={ "key": AttrValue::int(7) }) is Node(el3)
  assert_true(el3.key is Some("7"))
  // namespace attr entry
  guard @vdom.h("circle", attrs={
      "namespace": Str("http://www.w3.org/2000/svg"),
    })
    is Node(el4)
  assert_true(el4.ns is Some(Svg))
  assert_true(el4.attrs.get("namespace") is None)
  inspect(el4.tag, content="circle")
}

///|
test "h: empty attrs and childs" {
  guard @vdom.h("div") is Node(el)
  inspect(el.childs.length(), content="0")
  inspect(el.attrs.length(), content="0")
  assert_true(el.key is None)
}

///|
test "Ns uri round-trip" {
  inspect(@vdom.Ns::Svg.to_uri(), content="http://www.w3.org/2000/svg")
  inspect(
    @vdom.Ns::MathMl.to_uri(),
    content="http://www.w3.org/1998/Math/MathML",
  )
  assert_true(@vdom.Ns::from_uri("http://www.w3.org/2000/svg") is Svg)
  assert_true(@vdom.Ns::from_uri("urn:x") is Other("urn:x"))
  // dom-side classification: null and the HTML namespace are "not namespaced"
  assert_true(@vdom.ns_from_dom_uri(None) is None)
  assert_true(@vdom.ns_from_dom_uri(Some(@vdom.html_ns)) is None)
  assert_true(
    @vdom.ns_from_dom_uri(Some("http://www.w3.org/2000/svg")) is Some(Svg),
  )
}
