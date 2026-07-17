// Smoke tests against a real-ish DOM (happy-dom via npm; run with
// `moon test --target js vdom/browser`). The heavy behavioral coverage
// lives in vdom/memdom — these confirm the adapter wiring: creation,
// attribute/property routing, morphing, SVG namespaces.

///|
fn env() -> (@browser.BrowserNode, @vdom.RenderOpts[@browser.BrowserNode]) {
  let doc = @test_utils.create_happy_window().document()
  let container = @browser.BrowserNode::from_element(doc.createElement("div"))
  (container, @browser.opts_for(doc))
}

///|
/// Pins the DomNode contract (dom_trait.mbt): wrappers are re-created per
/// call, so is_same_node must compare the underlying node, never the wrapper.
/// The wasm twin satisfies it via @core.equal (JS === in the jscore imports).
test "browser: is_same_node compares the node, not the wrapper" {
  let (c, o) = env()
  let _ = @vdom.render(
    @vdom.h("div", childs=[@vdom.h("span"), @vdom.h("span")]),
    c,
    o,
  )
  let root = @vdom.DomNode::child_nodes(c)[0]
  // two independently-created wrappers of the same element
  let a = @vdom.DomNode::child_nodes(root)[0]
  let b = @vdom.DomNode::child_nodes(root)[0]
  assert_true(@vdom.DomNode::is_same_node(a, b))
  let other = @vdom.DomNode::child_nodes(root)[1]
  assert_false(@vdom.DomNode::is_same_node(a, other))
}

///|
test "browser: render, attributes and properties" {
  let (c, o) = env()
  let _ = @vdom.render(
    @vdom.h("input", attrs={
      "className": Str("field"),
      "tabindex": @vdom.AttrValue::int(0),
      "type": Str("text"),
      "value": Str("hello"),
    }),
    c,
    o,
  )
  let childs = @vdom.DomNode::child_nodes(c)
  inspect(childs.length(), content="1")
  let input = childs[0]
  inspect(@vdom.DomNode::tag_name(input), content="INPUT")
  // className routed via the IDL property, reflected to class
  let cls : String = input.as_any()._get("className").cast()
  inspect(cls, content="field")
  // lowercase tabindex fell through to setAttribute
  let tabindex : String = input
    .as_any()
    ._call("getAttribute", [@core.any("tabindex")])
    .cast()
  inspect(tabindex, content="0")
  // value is a live property, no attribute
  let value : String = input.as_any()._get("value").cast()
  inspect(value, content="hello")
}

///|
test "browser: morph patches in place and updates text" {
  let (c, o) = env()
  let r1 = @vdom.render(
    @vdom.h("div", attrs={ "id": Str("a") }, childs=[@vdom.text("one")]),
    c,
    o,
  )
  let before = @vdom.DomNode::child_nodes(c)[0]
  let _ = @vdom.render(
    @vdom.h("div", attrs={ "id": Str("b") }, childs=[@vdom.text("two")]),
    c,
    o,
    prev=r1,
  )
  let after = @vdom.DomNode::child_nodes(c)[0]
  assert_true(@vdom.DomNode::is_same_node(after, before))
  let id : String = after.as_any()._get("id").cast()
  inspect(id, content="b")
  let text : String = after.as_any()._get("textContent").cast()
  inspect(text, content="two")
}

///|
test "browser: keyed reorder preserves nodes" {
  let (c, o) = env()
  fn tree(ks : Array[String]) {
    @vdom.h(
      "ul",
      childs=ks.map(k => @vdom.h("li", key=k, childs=[@vdom.text(k)])),
    )
  }

  let r1 = @vdom.render(tree(["a", "b", "c"]), c, o)
  let root = @vdom.DomNode::child_nodes(c)[0]
  let before = @vdom.DomNode::child_nodes(root)
  let _ = @vdom.render(tree(["c", "a", "b"]), c, o, prev=r1)
  let after = @vdom.DomNode::child_nodes(root)
  inspect(after.length(), content="3")
  assert_true(@vdom.DomNode::is_same_node(after[0], before[2]))
  assert_true(@vdom.DomNode::is_same_node(after[1], before[0]))
  assert_true(@vdom.DomNode::is_same_node(after[2], before[1]))
}

///|
test "browser: svg namespace and innerHTML" {
  let (c, o) = env()
  let _ = @vdom.render(
    @vdom.h("svg", childs=[
      @vdom.h("rect", attrs={ "x": @vdom.AttrValue::int(1) }),
    ]),
    c,
    o,
  )
  let svg = @vdom.DomNode::child_nodes(c)[0]
  assert_true(@vdom.DomNode::namespace_uri(svg) is Some(Svg))
  let rect = @vdom.DomNode::child_nodes(svg)[0]
  assert_true(@vdom.DomNode::namespace_uri(rect) is Some(Svg))
  let x : String = rect.as_any()._call("getAttribute", [@core.any("x")]).cast()
  inspect(x, content="1")
  // dangerouslySetInnerHTML through the adapter
  let (c2, o2) = env()
  let _ = @vdom.render(
    @vdom.h("div", attrs={ "dangerouslySetInnerHTML": Html("<b>bold</b>") }),
    c2,
    o2,
  )
  inspect(
    @vdom.DomNode::get_inner_html(@vdom.DomNode::child_nodes(c2)[0]),
    content="<b>bold</b>",
  )
}
