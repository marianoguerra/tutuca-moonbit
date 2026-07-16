// Port of the <x> op suites from tutuca test/anode.test.js and the node-id
// registration checks from test/anode-core.test.js.

///|
fn xparse(html : String) -> (@anode.ANode?, @anode.ParseContext) {
  let px = @anode.ParseContext::new()
  (@anode.ANode::parse(html, px), px)
}

///|
test "render-each: no when/loop-with by default" {
  guard xparse("<x render-each=\".items\"></x>").0 is Some(Each(e))
  assert_true(e.iter_info.when_val is None)
  assert_true(e.iter_info.loop_with_val is None)
  assert_true(e.from_render_each)
}

///|
test "render-each with when" {
  guard xparse("<x render-each=\".items\" when=\"$whenH\"></x>").0
    is Some(Each(e))
  assert_true(e.iter_info.when_val is Some(Method("whenH")))
  assert_true(e.iter_info.loop_with_val is None)
}

///|
test "render-each with when and loop-with" {
  guard xparse(
      "<x render-each=\".items\" when=\"$whenH\" loop-with=\"$lwith\"></x>",
    ).0
    is Some(Each(e))
  assert_true(e.iter_info.when_val is Some(Method("whenH")))
  assert_true(e.iter_info.loop_with_val is Some(Method("lwith")))
}

///|
test "x text const" {
  guard xparse("<x text=\"'hi'\"></x>").0 is Some(RenderText(t))
  assert_true(t.val is Const(lit=LStr("hi"), ..))
  assert_true(t.node_id is Some(0))
}

///|
test "x text parse error yields null" {
  let (root, _) = xparse("<x text=\"%a\"></x>")
  assert_true(root is None)
}

///|
test "x render-it with show wraps in Show" {
  guard xparse("<x render-it show=\".isOpen\"></x>").0 is Some(Show(w))
  assert_true(w.node is RenderIt(_))
}

///|
test "x render-it with hide wraps in Hide" {
  guard xparse("<x render-it hide=\".closed\"></x>").0 is Some(Hide(w))
  assert_true(w.node is RenderIt(_))
}

///|
test "x text with show wraps in Show" {
  guard xparse("<x text=\"'hi'\" show=\".isOpen\"></x>").0 is Some(Show(w))
  assert_true(w.node is RenderText(_))
}

///|
test "x render with show wraps in Show" {
  guard xparse("<x render=\".v\" show=\".isOpen\"></x>").0 is Some(Show(_))
}

///|
test "x render-each with show keeps when/loop-with" {
  guard xparse(
      "<x render-each=\".items\" when=\"$whenH\" loop-with=\"$lwith\" show=\".isOpen\"></x>",
    ).0
    is Some(Show(w))
  guard w.node is Each(e)
  assert_true(e.node is RenderIt(_))
  assert_true(e.iter_info.when_val is Some(Method("whenH")))
  assert_true(e.iter_info.loop_with_val is Some(Method("lwith")))
}

///|
test "x render-it show then hide: first attr outermost" {
  guard xparse("<x render-it show=\".a\" hide=\".b\"></x>").0 is Some(Show(s))
  guard s.node is Hide(h)
  assert_true(h.node is RenderIt(_))
}

///|
test "@text puts a RenderText first child" {
  guard xparse("<span @text=\"'hi'\"></span>").0 is Some(Dom(d))
  guard d.childs[0] is RenderText(t)
  assert_true(t.val is Const(lit=LStr("hi"), ..))
  // The @text child is unregistered (JS constructs it with a null nodeId).
  assert_true(t.node_id is None)
}

///|
test "@text parse error leaves no child" {
  guard xparse("<span @text=\"%a\"></span>").0 is Some(Dom(d))
  assert_eq(d.childs.length(), 0)
}

///|
test "render-it registers a node id without a value" {
  let (root, px) = xparse("<x render-it></x>")
  guard root is Some(RenderIt(r))
  assert_eq(r.node_id, 0)
  assert_eq(px.nodes.length(), 1)
}

///|
test "render-each registers render-it then each" {
  let (root, px) = xparse("<x render-each=\".items\"></x>")
  guard root is Some(Each(e))
  assert_eq(e.node_id, 1)
  guard e.node is RenderIt(r)
  assert_eq(r.node_id, 0)
  assert_eq(px.nodes.length(), 2)
}

///|
test "pseudo-x render-each inside select" {
  guard xparse(
      "<select><option @x render-each=\".items\" as=\"option\"></option></select>",
    ).0
    is Some(Dom(select))
  guard select.childs[0] is Each(e)
  guard e.node is RenderIt(r)
  // `as=` falls back to a literal const view name.
  assert_true(r.view_val is Some(Const(lit=LStr("option"), ..)))
}

///|
test "unknown x op becomes an error comment and reports" {
  let (root, _) = xparse("<x nope=\"v\"></x>")
  guard root is Some(Comment(c))
  assert_eq(c.val, "Error: InvalidSpecialTagOp nope=v")
}

///|
test "x op with unparseable @show reports and drops the wrapper" {
  // `@show`/`@hide` used as wrapper attrs on an <x> op previously dropped the
  // wrapper silently when the bool failed to parse (xops.mbt). Now it surfaces
  // a BadValue(Directive) like the regular directive path, and the inner op
  // node survives unwrapped.
  let issues : Array[@anode.ParseIssue] = []
  let (root, _) = collecting_parse("<x text=\"'hi'\" @show=\"%a\"></x>", issues)
  assert_true(root is Some(RenderText(_)))
  assert_true(
    issues
    .iter()
    .any(i => i is BadValue(role=Directive(name="show"), value="%a")),
  )
}

///|
test "x slot wraps childs and keeps the name" {
  guard xparse("<x slot=\"header\"><p>hi</p></x>").0 is Some(Slot(s))
  assert_eq(s.name, "header")
  assert_true(s.node is Dom(_))
}
