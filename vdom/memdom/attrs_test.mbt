// Port of test/vdom-attrs-render.test.js: namespace support, attribute
// routing, order-sensitive value/checked, dangerouslySetInnerHTML.

///|
test "namespace: create element respects namespace" {
  let dom = to_dom(@vdom.h("svg"))
  inspect(dom.tag, content="svg")
  assert_true(dom.ns is Some(Svg))
}

///|
test "namespace: different namespaces produce a new element on re-render" {
  let a = @vdom.h("customtag", ns=Other("testing"))
  let b = @vdom.h("customtag", ns=Other("undefined"))
  let (c, o) = new_env()
  let r1 = @vdom.render(a, c, o)
  let root = c.childs[0]
  assert_true(root.ns is Some(Other("testing")))
  let _ = @vdom.render(b, c, o, prev=r1)
  let new_root = c.childs[0]
  assert_false(physical_equal(new_root, root))
  assert_true(new_root.ns is Some(Other("undefined")))
}

///|
test "svg: nested elements inherit the namespace" {
  let dom = to_dom(
    @vdom.h("svg", childs=[@vdom.h("rect", ns=Svg), @vdom.h("circle", ns=Svg)]),
  )
  inspect(dom.childs.length(), content="2")
  inspect(dom.childs[0].tag, content="rect")
  assert_true(dom.childs[0].ns is Some(Svg))
  assert_true(dom.childs[1].ns is Some(Svg))
}

///|
test "svg: replaces html element and back" {
  let (c, o) = new_env()
  let r1 = @vdom.render(div_text("hello"), c, o)
  assert_true(c.childs[0].ns is None)
  let r2 = @vdom.render(@vdom.h("svg"), c, o, prev=r1)
  inspect(c.childs[0].tag, content="svg")
  assert_true(c.childs[0].ns is Some(Svg))
  let _ = @vdom.render(div_text("hello"), c, o, prev=r2)
  inspect(c.childs[0].tag, content="DIV")
  assert_true(c.childs[0].ns is None)
}

///|
test "svg: updates children correctly with keys" {
  let left = @vdom.h("svg", childs=[@vdom.h("rect", key="r1", ns=Svg)])
  let right = @vdom.h("svg", childs=[
    @vdom.h("rect", key="r1", ns=Svg),
    @vdom.h("circle", key="c1", ns=Svg),
  ])
  let (c, o) = new_env()
  let r1 = @vdom.render(left, c, o)
  inspect(c.childs[0].childs.length(), content="1")
  let _ = @vdom.render(right, c, o, prev=r1)
  let root = c.childs[0]
  inspect(root.childs.length(), content="2")
  inspect(root.childs[0].tag, content="rect")
  inspect(root.childs[1].tag, content="circle")
  assert_true(root.childs[1].ns is Some(Svg))
}

///|
test "auto namespace: svg propagates to children at render time" {
  // children built with plain h() know nothing about the namespace;
  // they inherit it through opts during to_dom
  let dom = to_dom(@vdom.h("svg", childs=[@vdom.h("rect")]))
  assert_true(dom.ns is Some(Svg))
  // h("rect") uppercased the tag (no ns at build time); to_dom lowercases it
  // back when the inherited namespace applies
  inspect(dom.childs[0].tag, content="rect")
  assert_true(dom.childs[0].ns is Some(Svg))
}

///|
test "auto namespace: math propagates" {
  let dom = to_dom(
    @vdom.h("math", childs=[@vdom.h("mi", childs=[@vdom.text("x")])]),
  )
  assert_true(dom.ns is Some(MathMl))
  assert_true(dom.childs[0].ns is Some(MathMl))
  inspect(dom.childs[0].tag, content="mi")
}

///|
test "auto namespace: inheritance through <g> deep into descendants" {
  let dom = to_dom(
    @vdom.h("svg", childs=[@vdom.h("g", childs=[@vdom.h("circle")])]),
  )
  assert_true(dom.childs[0].ns is Some(Svg))
  assert_true(dom.childs[0].childs[0].ns is Some(Svg))
  inspect(dom.childs[0].childs[0].tag, content="circle")
}

///|
test "foreignObject switches children back to html" {
  let dom = to_dom(
    @vdom.h("svg", childs=[
      @vdom.h("foreignObject", ns=Svg, childs=[div_text("html")]),
    ]),
  )
  let fo = dom.childs[0]
  assert_true(fo.ns is Some(Svg))
  inspect(fo.tag, content="foreignObject")
  let div = fo.childs[0]
  assert_true(div.ns is None)
  inspect(div.tag, content="DIV")
  inspect(div.childs[0].data, content="html")
}

///|
test "re-render preserves svg namespace for descendants" {
  let (c, o) = new_env()
  let r1 = @vdom.render(@vdom.h("svg", childs=[@vdom.h("rect")]), c, o)
  assert_true(c.childs[0].childs[0].ns is Some(Svg))
  let _ = @vdom.render(
    @vdom.h("svg", childs=[
      @vdom.h("rect", attrs={ "x": @vdom.AttrValue::int(10) }),
    ]),
    c,
    o,
    prev=r1,
  )
  let rect = c.childs[0].childs[0]
  assert_true(rect.ns is Some(Svg))
  assert_true(rect.get_attribute("x") is Some("10"))
}

///|
test "namespaced elements route every attribute through set_attribute" {
  let dom = to_dom(
    @vdom.h("svg", attrs={ "id": Str("logo"), "className": Str("icon") }),
  )
  // no property routing on namespaced nodes: className lands verbatim as an
  // attribute named className, not class
  assert_true(dom.get_attribute("id") is Some("logo"))
  assert_true(dom.get_attribute("className") is Some("icon"))
  assert_true(dom.get_property("id") is None)
}

///|
test "is= passes through to create_element and the attribute is set" {
  let dom = to_dom(
    @vdom.h("button", attrs={ "is": Str("x-cool") }, childs=[
      @vdom.text("click"),
    ]),
  )
  inspect(dom.tag, content="BUTTON")
  assert_true(dom.created_is is Some("x-cool"))
  assert_true(dom.get_attribute("is") is Some("x-cool"))
}

///|
test "data-* add / remove / toggle via re-render" {
  // add
  let c1 = morphed(
    @vdom.h("div"),
    @vdom.h("div", attrs={ "data-id": @vdom.AttrValue::int(123) }),
  )
  assert_true(c1.childs[0].get_attribute("data-id") is Some("123"))
  // remove
  let c2 = morphed(
    @vdom.h("div", attrs={ "data-id": @vdom.AttrValue::int(123) }),
    @vdom.h("div"),
  )
  assert_true(c2.childs[0].get_attribute("data-id") is None)
  // aria toggle true -> false keeps a literal "false"
  let c3 = morphed(
    @vdom.h("button", attrs={ "aria-expanded": Bool(true) }),
    @vdom.h("button", attrs={ "aria-expanded": Bool(false) }),
  )
  assert_true(c3.childs[0].get_attribute("aria-expanded") is Some("false"))
}

///|
test "tabindex: lowercase spelling falls through to set_attribute" {
  // `tabindex` is not the IDL name (`tabIndex` is), so has_property is false
  // and the attribute path is taken — which is the correct behavior
  let dom = to_dom(
    @vdom.h("div", attrs={ "tabindex": @vdom.AttrValue::int(0) }),
  )
  assert_true(dom.get_attribute("tabindex") is Some("0"))
  assert_true(dom.get_property("tabindex") is None)
  let dom2 = to_dom(
    @vdom.h("div", attrs={ "tabindex": @vdom.AttrValue::int(-1) }),
  )
  assert_true(dom2.get_attribute("tabindex") is Some("-1"))
  // add / remove via re-render
  let c = morphed(
    @vdom.h("div", attrs={ "tabindex": @vdom.AttrValue::int(0) }),
    @vdom.h("div"),
  )
  assert_true(c.childs[0].get_attribute("tabindex") is None)
}

///|
test "camelCase IDL fallthrough: readonly, maxlength, colspan, novalidate" {
  // all-lowercase spellings are not IDL property names; they take the
  // attribute path and keep their lowercase attribute name
  let input = to_dom(
    @vdom.h("input", attrs={
      "readonly": Bool(true),
      "maxlength": @vdom.AttrValue::int(10),
      "inputmode": Str("numeric"),
    }),
  )
  assert_true(input.get_attribute("readonly") is Some("true"))
  assert_true(input.get_attribute("maxlength") is Some("10"))
  assert_true(input.get_attribute("inputmode") is Some("numeric"))
  let td = to_dom(
    @vdom.h("td", attrs={
      "colspan": @vdom.AttrValue::int(3),
      "rowspan": @vdom.AttrValue::int(2),
    }),
  )
  assert_true(td.get_attribute("colspan") is Some("3"))
  assert_true(td.get_attribute("rowspan") is Some("2"))
  let form = to_dom(@vdom.h("form", attrs={ "novalidate": Bool(true) }))
  assert_true(form.get_attribute("novalidate") is Some("true"))
  // removal across re-render
  let c = morphed(
    @vdom.h("input", attrs={ "readonly": Bool(true) }),
    @vdom.h("input"),
  )
  assert_true(c.childs[0].get_attribute("readonly") is None)
}

///|
test "NEVER_ASSIGN names are forced to the attribute path" {
  // tabIndex IS an IDL name but lives in the NEVER_ASSIGN set
  let dom = to_dom(
    @vdom.h("td", attrs={
      "tabIndex": @vdom.AttrValue::int(2),
      "colSpan": @vdom.AttrValue::int(3),
      "width": @vdom.AttrValue::int(100),
    }),
  )
  assert_true(dom.get_property("tabIndex") is None)
  assert_true(dom.get_attribute("tabIndex") is Some("2"))
  assert_true(dom.get_attribute("colSpan") is Some("3"))
  assert_true(dom.get_attribute("width") is Some("100"))
}

///|
test "aliased prop removal drops the aliased attribute" {
  // className reflects to `class`; removal must remove `class`, not
  // `className`
  let c = morphed(
    @vdom.h("div", attrs={ "className": Str("x") }),
    @vdom.h("div"),
  )
  assert_true(c.childs[0].get_attribute("class") is None)
  assert_true(c.childs[0].attrs.length() == 0)
  let c2 = morphed(
    @vdom.h("label", attrs={ "htmlFor": Str("field") }),
    @vdom.h("label"),
  )
  assert_true(c2.childs[0].get_attribute("for") is None)
}

///|
test "set_property failure falls through to the attribute path" {
  let dom = to_dom(@vdom.h("div", attrs={ "throwingProp": Str("v") }))
  // memdom's sentinel throwing property: assignment "throws", so the
  // renderer falls back to set_attribute
  assert_true(dom.get_property("throwingProp") is None)
  assert_true(dom.get_attribute("throwingProp") is Some("v"))
}

///|
test "value applied after min/max (range clamp order)" {
  // memdom does not clamp, but the ordering is observable: value must be the
  // last property applied
  let dom = to_dom(
    @vdom.h("input", attrs={
      "type": Str("range"),
      "value": @vdom.AttrValue::int(50),
      "min": @vdom.AttrValue::int(0),
      "max": @vdom.AttrValue::int(100),
    }),
  )
  assert_true(dom.get_property("value") is Some(Num(50)))
  assert_true(dom.get_attribute("min") is Some("0"))
  assert_true(dom.get_attribute("max") is Some("100"))
}

///|
test "checkbox checked applied after other props" {
  let dom = to_dom(
    @vdom.h("input", attrs={ "type": Str("checkbox"), "checked": Bool(true) }),
  )
  assert_true(dom.get_property("checked") is Some(Bool(true)))
  // checked never reflects to an attribute
  assert_true(dom.get_attribute("checked") is None)
}

///|
test "progress with value=0 removes the attribute (not indeterminate)" {
  let dom = to_dom(
    @vdom.h("progress", attrs={
      "value": @vdom.AttrValue::int(0),
      "max": @vdom.AttrValue::int(100),
    }),
  )
  assert_true(dom.get_attribute("value") is None)
  // nonzero value goes through the normal property path
  let dom2 = to_dom(
    @vdom.h("progress", attrs={ "value": @vdom.AttrValue::int(50) }),
  )
  assert_true(dom2.get_property("value") is Some(Num(50)))
}

///|
test "dangerouslySetInnerHTML: set, update, clear" {
  let (c, o) = new_env()
  let r1 = @vdom.render(
    @vdom.h("div", attrs={ "dangerouslySetInnerHTML": Html("<b>bold</b>") }),
    c,
    o,
  )
  inspect(c.childs[0].get_inner_html(), content="<b>bold</b>")
  // update
  let r2 = @vdom.render(
    @vdom.h("div", attrs={
      "dangerouslySetInnerHTML": Html("<strong>second</strong>"),
    }),
    c,
    o,
    prev=r1,
  )
  inspect(c.childs[0].get_inner_html(), content="<strong>second</strong>")
  // clear on removal
  let _ = @vdom.render(@vdom.h("div"), c, o, prev=r2)
  inspect(c.childs[0].get_inner_html(), content="")
}

///|
test "dangerouslySetInnerHTML: identical rerender skips the re-parse" {
  let (c, o) = new_env()
  let v = fn() {
    @vdom.h("div", attrs={ "dangerouslySetInnerHTML": Html("<span>hi</span>") })
  }
  let r1 = @vdom.render(v(), c, o)
  let root = c.childs[0]
  inspect(root.inner_html_sets, content="1")
  let _ = @vdom.render(v(), c, o, prev=r1)
  assert_true(physical_equal(c.childs[0], root))
  // identical markup must not re-trigger set_inner_html
  inspect(root.inner_html_sets, content="1")
}

///|
test "dangerouslySetInnerHTML: switches to and from children" {
  // children -> dangerous
  let c1 = morphed(
    @vdom.h("div", childs=[span_text("child")]),
    @vdom.h("div", attrs={ "dangerouslySetInnerHTML": Html("<b>raw</b>") }),
  )
  inspect(c1.childs[0].get_inner_html(), content="<b>raw</b>")
  inspect(c1.childs[0].childs.length(), content="0")
  // dangerous -> children
  let c2 = morphed(
    @vdom.h("div", attrs={ "dangerouslySetInnerHTML": Html("<b>raw</b>") }),
    @vdom.h("div", childs=[span_text("child")]),
  )
  let root = c2.childs[0]
  inspect(root.childs.length(), content="1")
  inspect(root.childs[0].tag, content="SPAN")
  assert_true(root.dangerous_html is None)
}
