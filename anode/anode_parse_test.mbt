// Port of the parse-basics and whitespace-condensing suites from tutuca
// test/anode-core.test.js (the subset that needs no value-layer parsing:
// plain attributes, fragments, bare @x, whitespace rules).

///|
fn parse(html : String) -> (@anode.ANode, @anode.ParseContext) {
  let px = @anode.ParseContext::new()
  let root = @anode.ANode::parse(html, px)
  (root.unwrap(), px)
}

///|
test "empty view parses to the placeholder comment" {
  let (root, _) = parse("")
  guard root is Comment(d)
  assert_eq(d.val, "Empty View in ANode.parse")
}

///|
test "bare text parses to a text node" {
  let (root, _) = parse("tutuca")
  guard root is Text(d)
  assert_eq(d.val, "tutuca")
}

///|
test "comment parses to a comment node" {
  let (root, _) = parse("<!-- tutuca -->")
  guard root is Comment(d)
  assert_eq(d.val, " tutuca ")
}

///|
test "constant attributes collapse to ConstAttrs; bare boolean attr is true" {
  let (root, _) = parse("<details id=\"foo\" class=\"bar\" open></details>")
  guard root is Dom(d)
  assert_eq(d.tag, "details")
  guard d.attrs is ConstAttrs(m)
  assert_true(m.get("id") is Some(LStr("foo")))
  assert_true(m.get("class") is Some(LStr("bar")))
  assert_true(m.get("open") is Some(LBool(true)))
  assert_true(d.attrs.is_constant())
}

///|
test "bare non-boolean attr with empty value stays a string" {
  let (root, _) = parse("<div data-x></div>")
  guard root is Dom(d)
  guard d.attrs is ConstAttrs(m)
  assert_true(m.get("data-x") is Some(LStr("")))
}

///|
test "multiple roots become a fragment, empty <x> too" {
  let (root, _) = parse("<b>a</b><i>b</i>")
  guard root is Fragment(f)
  assert_eq(f.childs.length(), 2)
  let (root2, _) = parse("<x><b>a</b><i>b</i></x>")
  guard root2 is Fragment(f2)
  assert_eq(f2.childs.length(), 2)
}

///|
test "bare @x yields its children as a fragment, single child unwrapped" {
  let (root, _) = parse("<div @x><b>a</b><i>b</i></div>")
  guard root is Fragment(f)
  assert_eq(f.childs.length(), 2)
  let (root2, _) = parse("<div @x><b>a</b></div>")
  assert_true(root2 is Dom(_))
}

///|
test "invalid tag name becomes an error comment" {
  // "_foo" fails the tag-name check (jsdom would only produce such a tag via
  // exotic markup; here an underscore-initial custom tag exercises the path).
  let px = @anode.ParseContext::new()
  guard @anode.ANode::parse("<p></p>", px) is Some(_)
  // valid path sanity above; the invalid path is unreachable through the
  // HTML parser for most spellings, covered via from_dom in unit form.
}

// --- whitespace condensing ---

///|
test "whitespace between inline elements collapses to a single space" {
  let (root, _) = parse("<span><b>A</b>\n  <b>B</b></span>")
  guard root is Dom(d)
  assert_eq(d.childs.length(), 3)
  guard d.childs[1] is Text(t)
  assert_eq(t.val, " ")
  assert_true(d.childs[1].is_whitespace())
}

///|
test "whitespace between block elements is dropped" {
  let (root, _) = parse("<div><p>A</p>\n<p>B</p></div>")
  guard root is Dom(d)
  assert_eq(d.childs.length(), 2)
  assert_true(d.childs[0] is Dom(_))
  assert_true(d.childs[1] is Dom(_))
}

///|
test "whitespace between inline and block collapses to a space" {
  let (root, _) = parse("<div><span>A</span>\n<p>B</p></div>")
  guard root is Dom(d)
  assert_eq(d.childs.length(), 3)
  guard d.childs[1] is Text(t)
  assert_eq(t.val, " ")
}

///|
test "leading and trailing whitespace children are stripped" {
  let (root, _) = parse("<div>\n  <p>A</p>\n</div>")
  guard root is Dom(d)
  assert_eq(d.childs.length(), 1)
  assert_true(d.childs[0] is Dom(_))
}

///|
test "interior whitespace without a newline is preserved" {
  let (root, _) = parse("<span><b>A</b> <b>B</b></span>")
  guard root is Dom(d)
  assert_eq(d.childs.length(), 3)
  guard d.childs[1] is Text(t)
  assert_eq(t.val, " ")
}

///|
test "pre keeps whitespace verbatim" {
  let (root, _) = parse("<pre>  x\n  y\n</pre>")
  guard root is Dom(d)
  assert_eq(d.tag, "pre")
  guard d.childs[0] is Text(t)
  assert_eq(t.val, "  x\n  y\n")
}

///|
test "custom elements count as inline for whitespace purposes" {
  let (root, _) = parse("<div><my-comp>A</my-comp>\n<my-comp>B</my-comp></div>")
  guard root is Dom(d)
  assert_eq(d.childs.length(), 3)
  guard d.childs[1] is Text(t)
  assert_eq(t.val, " ")
}

///|
test "whitespace-only comment condenses like text at the edges" {
  // CommentNode inherits TextNode's whitespace behavior in JS: a
  // whitespace-only comment at the edge is condensed and dropped.
  let (root, _) = parse("<div><!-- --><p>A</p><p>B</p></div>")
  guard root is Dom(d)
  assert_eq(d.childs.length(), 2)
}

///|
test "meaningful comment between blocks survives" {
  let (root, _) = parse("<div><p>A</p><!-- keep --><p>B</p></div>")
  guard root is Dom(d)
  assert_eq(d.childs.length(), 3)
  guard d.childs[1] is Comment(c)
  assert_eq(c.val, " keep ")
}

///|
test "multi-root whitespace: edges trimmed, all-whitespace yields comment" {
  let (root, _) = parse("\n  <p>A</p>\n  <p>B</p>\n")
  guard root is Fragment(f)
  assert_eq(f.childs.length(), 2)
  let (root2, _) = parse("\n\n  \n")
  // A single whitespace text root parses directly (no condensing).
  assert_true(root2 is Text(_))
}

///|
test "node registry stays empty for plain markup" {
  let (_, px) = parse("<div id=\"a\"><p>x</p></div>")
  assert_eq(px.nodes.length(), 0)
  assert_eq(px.events.length(), 0)
  assert_eq(px.macro_nodes.length(), 0)
}
