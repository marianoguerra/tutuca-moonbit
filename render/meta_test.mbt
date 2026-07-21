// §…§ meta emission/parsing round-trips (emission and reconstruction share
// Meta, so a drift here would break event-path rebuilds).

///|
test "Meta round-trips through comment text" {
  let metas : Array[@render.Meta] = [
    Comp(nid=Some(3), cid=7, vid="main"),
    Comp(nid=None, cid=0, vid="detail"),
    Each(nid=1, key=KInt(4)),
    Each(nid=2, key=KStr("b")),
    Scope(nid=5),
  ]
  for m in metas {
    assert_true(@render.Meta::parse(m.to_comment_text()) == Some(m))
  }
}

///|
test "Meta::parse rejects non-meta comments" {
  assert_true(@render.Meta::parse(" note ") is None)
  assert_true(@render.Meta::parse("§not json§") is None)
  assert_true(@render.Meta::parse("§{\"$\":\"Nope\"}§") is None)
  assert_true(@render.Meta::parse("§") is None)
}

///|
test "the JSON wire shape matches the JS renderer" {
  assert_eq(
    @render.Meta::Comp(nid=Some(1), cid=0, vid="main").to_comment_text(),
    "§{\"$\":\"Comp\",\"nid\":1,\"cid\":0,\"vid\":\"main\"}§",
  )
  assert_eq(
    @render.Meta::Comp(nid=None, cid=2, vid="m").to_comment_text(),
    "§{\"$\":\"Comp\",\"nid\":null,\"cid\":2,\"vid\":\"m\"}§",
  )
  assert_eq(
    @render.Meta::Each(nid=2, key=KInt(0)).to_comment_text(),
    "§{\"$\":\"Each\",\"nid\":2,\"si\":0}§",
  )
  assert_eq(
    @render.Meta::Each(nid=2, key=KStr("b")).to_comment_text(),
    "§{\"$\":\"Each\",\"nid\":2,\"sk\":\"b\"}§",
  )
  assert_eq(
    @render.Meta::Scope(nid=3).to_comment_text(),
    "§{\"$\":\"Scope\",\"nid\":3}§",
  )
}

///|
test "render_root emits the root Comp boundary with a null nid" {
  let px = @anode.ParseContext::new()
  let node = @anode.ANode::parse("<main>root</main>", px).unwrap()
  let resolver = @render.ViewMap::{ views: { "main": node } }
  let stack = @render.RenderStack::new(Map(Map([])))
  let ctx = @render.RenderCtx::new(view_resolver=resolver)
  guard @render.render_root(Map(Map([])), stack, ctx) is Some(v) else {
    fail("root did not render")
  }
  let doc = @memdom.document()
  assert_eq(
    @vdom.to_dom(v, @vdom.RenderOpts::new(doc)).to_html(),
    "<!--§{\"$\":\"Comp\",\"nid\":null,\"cid\":0,\"vid\":\"main\"}§--><main>root</main>",
  )
}
