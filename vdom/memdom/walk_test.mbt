// DomWalk over the in-memory DOM: the read-side used by event-path
// reconstruction (walk up, walk backward over meta comments, read attrs).

///|
test "walk: parent, prev_sibling, kinds, char data and attributes" {
  let (c, o) = new_env()
  let vdom = @vdom.h("div", attrs={ "data-cid": @vdom.AttrValue::Str("7") }, childs=[
    @vdom.comment("§{\"$\":\"Comp\",\"cid\":0}§"),
    @vdom.comment("§{\"$\":\"Each\",\"nid\":1,\"sk\":\"b\"}§"),
    @vdom.h("button", childs=[@vdom.text("hi")]),
  ])
  let _ = @vdom.render(vdom, c, o)
  let div = c.childs[0]
  assert_eq(div.node_kind(), 1)
  @debug.assert_eq(div.attribute("data-cid"), Some("7"))
  @debug.assert_eq(div.attribute("data-eid"), None)
  let button = div.childs[2]
  assert_eq(button.node_kind(), 1)
  // meta chain: previous siblings, innermost (closest) first
  guard button.prev_sibling() is Some(m2) else { fail("no prev sibling") }
  assert_eq(m2.node_kind(), 8)
  assert_eq(m2.char_data(), "§{\"$\":\"Each\",\"nid\":1,\"sk\":\"b\"}§")
  guard m2.prev_sibling() is Some(m1) else { fail("no second meta") }
  assert_eq(m1.char_data(), "§{\"$\":\"Comp\",\"cid\":0}§")
  assert_true(m1.prev_sibling() is None)
  // walking up
  guard button.parent_node() is Some(p) else { fail("no parent") }
  assert_true(p.is_same_node(div))
  let text = button.childs[0]
  assert_eq(text.node_kind(), 3)
  assert_eq(text.char_data(), "hi")
}
