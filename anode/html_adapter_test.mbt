// Risk-gate smoke suite: parse_fragment must reproduce jsdom
// `template.innerHTML` semantics (template-contents insertion mode). If these
// fail, the fragment strategy has to change before anything is built on it.

///|
fn tag_of(doc : @html5.Document, id : Int) -> String {
  doc.get_tag_name(id).unwrap_or("?")
}

///|
test "bare tr survives unwrapped" {
  let (doc, roots) = @anode.parse_fragment("<tr><td>x</td></tr>")
  assert_eq(roots.length(), 1)
  assert_eq(tag_of(doc, roots[0]), "tr")
  let tds = doc.get_children(roots[0])
  assert_eq(tds.length(), 1)
  assert_eq(tag_of(doc, tds[0]), "td")
  assert_eq(doc.get_text_content(tds[0]), "x")
}

///|
test "bare options and col survive" {
  let (doc, roots) = @anode.parse_fragment(
    "<option>a</option><option>b</option>",
  )
  assert_eq(roots.length(), 2)
  assert_eq(tag_of(doc, roots[0]), "option")
  assert_eq(tag_of(doc, roots[1]), "option")
  let (doc2, roots2) = @anode.parse_fragment("<col>")
  assert_eq(roots2.length(), 1)
  assert_eq(tag_of(doc2, roots2[0]), "col")
}

///|
test "plain text and adjacent text runs merge" {
  let (doc, roots) = @anode.parse_fragment("hello")
  assert_eq(roots.length(), 1)
  guard doc.get_node(roots[0]) is Some(TextNode(s))
  assert_eq(s, "hello")
  // text-comment-text: three roots, text runs kept whole
  let (doc3, roots3) = @anode.parse_fragment("a<!--c-->b")
  assert_eq(roots3.length(), 3)
  assert_true(doc3.get_node(roots3[0]) is Some(TextNode("a")))
  assert_true(doc3.get_node(roots3[1]) is Some(CommentNode("c")))
  assert_true(doc3.get_node(roots3[2]) is Some(TextNode("b")))
}

///|
test "svg subtree gets SVG namespace and preserves camelCase" {
  let (doc, roots) = @anode.parse_fragment(
    "<svg viewBox=\"0 0 1 1\"><linearGradient></linearGradient><circle/></svg>",
  )
  assert_eq(roots.length(), 1)
  assert_true(doc.get_ns(roots[0]) is Some(SVG))
  assert_true(doc.get_attribute(roots[0], "viewBox") is Some("0 0 1 1"))
  let childs = doc.get_children(roots[0])
  assert_eq(childs.length(), 2)
  assert_eq(tag_of(doc, childs[0]), "linearGradient")
  assert_true(doc.get_ns(doc.get_children(roots[0])[1]) is Some(SVG))
}

///|
test "mathml subtree gets MathML namespace" {
  let (doc, roots) = @anode.parse_fragment("<math><mi>x</mi></math>")
  assert_eq(roots.length(), 1)
  assert_true(doc.get_ns(roots[0]) is Some(MathML))
  let childs = doc.get_children(roots[0])
  assert_true(doc.get_ns(childs[0]) is Some(MathML))
}

///|
test "html tag names are lowercased, attrs keep order" {
  let (doc, roots) = @anode.parse_fragment("<DIV b=\"2\" a=\"1\">x</DIV>")
  assert_eq(roots.length(), 1)
  assert_eq(tag_of(doc, roots[0]), "div")
  guard doc.get_element(roots[0]) is Some(el)
  assert_true(el.attributes == [("b", "2"), ("a", "1")])
}

///|
test "pre keeps whitespace verbatim" {
  let (doc, roots) = @anode.parse_fragment("<pre>\n  x\n</pre>")
  assert_eq(roots.length(), 1)
  // Note: HTML spec drops ONE newline immediately after <pre>; jsdom does the
  // same, so the port inherits identical behavior either way.
  assert_eq(doc.get_text_content(roots[0]), "  x\n")
}

///|
test "nested template inside fragment is not mistaken for the wrapper" {
  let (doc, roots) = @anode.parse_fragment(
    "<div><template><b>t</b></template></div>",
  )
  assert_eq(roots.length(), 1)
  assert_eq(tag_of(doc, roots[0]), "div")
  let inner = doc.get_children(roots[0])
  assert_eq(tag_of(doc, inner[0]), "template")
}

///|
test "empty input yields no roots" {
  let (_, roots) = @anode.parse_fragment("")
  assert_eq(roots.length(), 0)
}

///|
test "leading whitespace before root element is preserved as a text node" {
  let (doc, roots) = @anode.parse_fragment("\n  <div>x</div>")
  assert_eq(roots.length(), 2)
  guard doc.get_node(roots[0]) is Some(TextNode(ws))
  assert_eq(ws, "\n  ")
  assert_eq(tag_of(doc, roots[1]), "div")
}
