// Port of the toDom / render / re-render / unmount groups of
// test/vdom-vnode.test.js and test/vdom-attrs-render.test.js.

///|
test "toDom: renders text child" {
  let dom = to_dom(span_text("hello"))
  inspect(dom.tag, content="SPAN")
  inspect(dom.childs.length(), content="1")
  inspect(dom.childs[0].data, content="hello")
}

///|
test "toDom: renders empty div" {
  let dom = to_dom(@vdom.h("div"))
  inspect(dom.tag, content="DIV")
  inspect(dom.childs.length(), content="0")
}

///|
test "toDom: id and className applied via property, reflected to attrs" {
  let dom = to_dom(
    @vdom.h("div", attrs={ "id": Str("important"), "className": Str("pretty") }),
  )
  assert_true(dom.get_attribute("id") is Some("important"))
  assert_true(dom.get_attribute("class") is Some("pretty"))
  assert_true(dom.get_property("className") is Some(Str("pretty")))
}

///|
test "toDom: class prop sets class attribute directly" {
  // `class` is not an IDL property name; it falls through to set_attribute.
  let dom = to_dom(@vdom.h("div", attrs={ "class": Str("foo") }))
  assert_true(dom.get_attribute("class") is Some("foo"))
}

///|
test "toDom: data-* and aria-* set attributes with coercion at render" {
  let dom = to_dom(
    @vdom.h("div", attrs={
      "data-foo": Str("bar"),
      "data-user-id": @vdom.AttrValue::int(123),
      "data-is-active": Bool(true),
      "aria-pressed": Bool(false),
    }),
  )
  assert_true(dom.get_attribute("data-foo") is Some("bar"))
  assert_true(dom.get_attribute("data-user-id") is Some("123"))
  assert_true(dom.get_attribute("data-is-active") is Some("true"))
  // aria-* preserves a literal "false" instead of removing
  assert_true(dom.get_attribute("aria-pressed") is Some("false"))
}

///|
test "toDom: nested children" {
  let dom = to_dom(
    @vdom.h("div", childs=[
      @vdom.h("div", childs=[
        @vdom.text("just testing"),
        @vdom.text("multiple"),
        @vdom.h("b", childs=[@vdom.text("nodes")]),
      ]),
      @vdom.text("hello"),
      span_text("test"),
    ]),
  )
  inspect(dom.childs.length(), content="3")
  inspect(dom.childs[0].tag, content="DIV")
  inspect(dom.childs[1].data, content="hello")
  inspect(dom.childs[2].tag, content="SPAN")
  let sub = dom.childs[0].childs
  inspect(sub.length(), content="3")
  inspect(sub[0].data, content="just testing")
  inspect(sub[2].tag, content="B")
}

///|
test "render: renders vnode into container, returns root dom" {
  let (c, o) = new_env()
  let result = @vdom.render(span_text("hello"), c, o)
  inspect(c.childs.length(), content="1")
  inspect(c.childs[0].tag, content="SPAN")
  assert_true(physical_equal(result.dom, c.childs[0]))
}

///|
test "render: clears container before rendering" {
  let (c, o) = new_env()
  let _ = @vdom.render(div_text("old"), c, o)
  let _ = @vdom.render(div_text("older"), c, o) // no prev: fresh render
  // fresh render replaces everything
  let _ = @vdom.render(span_text("new content"), c, o)
  inspect(c.childs.length(), content="1")
  inspect(c.childs[0].tag, content="SPAN")
}

///|
test "render: renders text and comment roots" {
  let (c1, o1) = new_env()
  let _ = @vdom.render(@vdom.text("hello world"), c1, o1)
  inspect(c1.childs.length(), content="1")
  assert_true(c1.childs[0].kind is TextNode)
  inspect(c1.childs[0].data, content="hello world")
  let (c2, o2) = new_env()
  let _ = @vdom.render(@vdom.comment("my comment"), c2, o2)
  assert_true(c2.childs[0].kind is CommentNode)
  inspect(c2.childs[0].data, content="my comment")
}

///|
test "render: fragment children go directly into container" {
  let (c, o) = new_env()
  let _ = @vdom.render(
    @vdom.fragment([@vdom.text("one"), span_text("two"), @vdom.text("three")]),
    c,
    o,
  )
  inspect(c.childs.length(), content="3")
  inspect(c.childs[0].data, content="one")
  inspect(c.childs[1].tag, content="SPAN")
  inspect(c.childs[2].data, content="three")
}

///|
test "re-render: text change patches in place" {
  let (c, o) = new_env()
  let r1 = @vdom.render(div_text("hello"), c, o)
  let root = c.childs[0]
  let r2 = @vdom.render(div_text("goodbye"), c, o, prev=r1)
  inspect(c.childs.length(), content="1")
  assert_true(physical_equal(c.childs[0], root))
  inspect(c.childs[0].childs[0].data, content="goodbye")
  assert_true(physical_equal(r2.dom, root))
}

///|
test "re-render: child additions and removals" {
  let (c, o) = new_env()
  let one = @vdom.h("div", childs=[span_text("one")])
  let two = @vdom.h("div", childs=[span_text("one"), span_text("two")])
  let r1 = @vdom.render(one, c, o)
  let r2 = @vdom.render(two, c, o, prev=r1)
  inspect(c.childs[0].childs.length(), content="2")
  inspect(c.childs[0].childs[1].tag, content="SPAN")
  let _ = @vdom.render(one, c, o, prev=r2)
  inspect(c.childs[0].childs.length(), content="1")
}

///|
test "re-render: root element replacement div -> span" {
  let (c, o) = new_env()
  let r1 = @vdom.render(div_text("content"), c, o)
  inspect(c.childs[0].tag, content="DIV")
  let r2 = @vdom.render(span_text("content"), c, o, prev=r1)
  inspect(c.childs.length(), content="1")
  inspect(c.childs[0].tag, content="SPAN")
  assert_true(physical_equal(r2.dom, c.childs[0]))
}

///|
test "re-render: attribute changes" {
  let c = morphed(
    @vdom.h("div", attrs={ "className": Str("old") }, childs=[
      @vdom.text("text"),
    ]),
    @vdom.h("div", attrs={ "className": Str("new"), "id": Str("added") }, childs=[
      @vdom.text("text"),
    ]),
  )
  let root = c.childs[0]
  assert_true(root.get_attribute("class") is Some("new"))
  assert_true(root.get_attribute("id") is Some("added"))
}

///|
test "re-render: fragment root morphs" {
  let (c, o) = new_env()
  let r1 = @vdom.render(
    @vdom.fragment([@vdom.text("a"), @vdom.text("b")]),
    c,
    o,
  )
  inspect(c.childs.length(), content="2")
  let r2 = @vdom.render(
    @vdom.fragment([@vdom.text("c"), @vdom.text("d")]),
    c,
    o,
    prev=r1,
  )
  inspect(c.childs.length(), content="2")
  inspect(c.childs[0].data, content="c")
  inspect(c.childs[1].data, content="d")
  // child addition
  let r3 = @vdom.render(
    @vdom.fragment([@vdom.text("c"), @vdom.text("d"), @vdom.text("e")]),
    c,
    o,
    prev=r2,
  )
  inspect(c.childs.length(), content="3")
  // child removal
  let _ = @vdom.render(@vdom.fragment([@vdom.text("c")]), c, o, prev=r3)
  inspect(c.childs.length(), content="1")
  inspect(c.childs[0].data, content="c")
}

///|
test "re-render: fragment <-> node transitions" {
  let (c, o) = new_env()
  let r1 = @vdom.render(
    @vdom.fragment([@vdom.text("a"), @vdom.text("b")]),
    c,
    o,
  )
  inspect(c.childs.length(), content="2")
  let r2 = @vdom.render(div_text("content"), c, o, prev=r1)
  inspect(c.childs.length(), content="1")
  inspect(c.childs[0].tag, content="DIV")
  let _ = @vdom.render(
    @vdom.fragment([@vdom.text("a"), @vdom.text("b")]),
    c,
    o,
    prev=r2,
  )
  inspect(c.childs.length(), content="2")
  inspect(c.childs[0].data, content="a")
}

///|
test "re-render: fragment root with nested fragment children" {
  // Simulates the component pattern: comment marker + fragment child.
  // fragment() splices nested fragments, so the container sees a flat list.
  let (c, o) = new_env()
  let r1 = @vdom.render(
    @vdom.fragment([
      @vdom.comment("comp-root"),
      @vdom.fragment([
        @vdom.comment("comp-child"),
        @vdom.h("section", childs=[@vdom.text("v1")]),
      ]),
    ]),
    c,
    o,
  )
  inspect(c.childs.length(), content="3")
  assert_true(c.childs[0].kind is CommentNode)
  assert_true(c.childs[1].kind is CommentNode)
  inspect(c.childs[2].tag, content="SECTION")
  let _ = @vdom.render(
    @vdom.fragment([
      @vdom.comment("comp-root"),
      @vdom.fragment([
        @vdom.comment("comp-child"),
        @vdom.h("section", childs=[@vdom.text("v2")]),
        div_text("added"),
      ]),
    ]),
    c,
    o,
    prev=r1,
  )
  inspect(c.childs.length(), content="4")
  inspect(c.childs[2].childs[0].data, content="v2")
  inspect(c.childs[3].tag, content="DIV")
}

///|
test "re-render: subsequent re-renders after root replacement" {
  let (c, o) = new_env()
  let r1 = @vdom.render(div_text("first"), c, o)
  let r2 = @vdom.render(span_text("second"), c, o, prev=r1)
  let r3 = @vdom.render(span_text("third"), c, o, prev=r2)
  inspect(c.childs.length(), content="1")
  let root = c.childs[0]
  inspect(root.tag, content="SPAN")
  inspect(root.childs[0].data, content="third")
  assert_true(physical_equal(r3.dom, root))
}

///|
test "unmount clears container; render after unmount is fresh" {
  let (c, o) = new_env()
  let _ = @vdom.render(div_text("hello"), c, o)
  inspect(c.childs.length(), content="1")
  @vdom.unmount(c)
  inspect(c.childs.length(), content="0")
  let result = @vdom.render(span_text("fresh"), c, o)
  inspect(c.childs.length(), content="1")
  inspect(c.childs[0].tag, content="SPAN")
  assert_true(physical_equal(result.dom, c.childs[0]))
}

///|
test "diff uses is_equal_to: equal trees preserve DOM references" {
  let tree = fn() {
    @vdom.h("div", childs=[span_text("hello"), span_text("world")])
  }
  let (c, o) = new_env()
  let r1 = @vdom.render(tree(), c, o)
  let first = c.childs[0]
  let _ = @vdom.render(tree(), c, o, prev=r1)
  assert_true(physical_equal(c.childs[0], first))
}
