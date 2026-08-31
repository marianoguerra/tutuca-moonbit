// §…§ meta emission/parsing round-trips (emission and reconstruction share
// Meta, so a drift here would break event-path rebuilds).

///|
test "Meta round-trips through comment text" {
  let metas : Array[Meta] = [
    Comp(nid=Some(3), cid=7, vid="main", base=None),
    Comp(nid=None, cid=0, vid="detail", base=None),
    Comp(
      nid=Some(4),
      cid=9,
      vid="resumed",
      base=Some(
        @tutuca.Path::new(steps=[
          FieldStep("session"),
          SeqAccessStep(seq_field="themes", key_field="activeTheme"),
        ]),
      ),
    ),
    Each(nid=1, key=KInt(4)),
    Each(nid=2, key=KStr("b")),
    Scope(nid=5),
  ]
  for m in metas {
    assert_true(Meta::parse(m.to_comment_text()) == Some(m))
  }
}

///|
test "render path text preserves fields, keys, and live-key access" {
  let path = @tutuca.Path::new(steps=[
    FieldStep("session"),
    SeqStep(field="rows", key=KStr("a")),
    SeqAccessStep(seq_field="themes", key_field="selected"),
  ])
  assert_eq(parse_render_path_text(render_path_text(path)), Some(path))
}

///|
test "Meta::parse rejects non-meta comments" {
  assert_true(Meta::parse(" note ") is None)
  assert_true(Meta::parse("§not json§") is None)
  assert_true(Meta::parse("§{\"$\":\"Nope\"}§") is None)
  assert_true(Meta::parse("§") is None)
}

///|
test "the JSON wire shape matches the JS renderer" {
  assert_eq(
    Meta::Comp(nid=Some(1), cid=0, vid="main", base=None).to_comment_text(),
    "§{\"$\":\"Comp\",\"nid\":1,\"cid\":0,\"vid\":\"main\"}§",
  )
  assert_eq(
    Meta::Comp(nid=None, cid=2, vid="m", base=None).to_comment_text(),
    "§{\"$\":\"Comp\",\"nid\":null,\"cid\":2,\"vid\":\"m\"}§",
  )
  assert_eq(
    Meta::Each(nid=2, key=KInt(0)).to_comment_text(),
    "§{\"$\":\"Each\",\"nid\":2,\"si\":0}§",
  )
  assert_eq(
    Meta::Each(nid=2, key=KStr("b")).to_comment_text(),
    "§{\"$\":\"Each\",\"nid\":2,\"sk\":\"b\"}§",
  )
  assert_eq(
    Meta::Scope(nid=3).to_comment_text(),
    "§{\"$\":\"Scope\",\"nid\":3}§",
  )
}

///|
test "render_root emits the root Comp boundary with a null nid" {
  let px = @anode.ParseContext::new()
  let node = @anode.ANode::parse("<main>root</main>", px).unwrap()
  let resolver = ViewMap::{ views: { "main": node }, }
  let stack = RenderStack::new(Map(Map([])))
  let ctx = RenderCtx::new(view_resolver=resolver)
  guard render_root(Map(Map([])), stack, ctx) is Some(v) else {
    fail("root did not render")
  }
  let doc = @memdom.document()
  assert_eq(
    @vdom.to_dom(v, @vdom.RenderOpts::new(doc)).to_html(),
    "<!--§{\"$\":\"Comp\",\"nid\":null,\"cid\":0,\"vid\":\"main\"}§--><main>root</main>",
  )
}
