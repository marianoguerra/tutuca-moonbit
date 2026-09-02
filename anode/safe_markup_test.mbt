// The parse side of `@setinnerhtml` and `@setinnersvg`, and the SVG-context
// fragment parser they rest on.

///|
fn safe_parse(html : String) -> @anode.ANode {
  let px = @anode.ParseContext::new()
  @anode.ANode::parse(html, px).unwrap()
}

///|
fn items_of(node : @anode.ANode) -> Array[@anode.AttrItem] {
  guard node is Dom(d) else { return [] }
  match d.attrs {
    DynAttrs(items) => items
    ConstAttrs(_) => []
  }
}

///|
/// Both directives force the DYNAMIC representation, the way the other two
/// markup directives do — their value is an expression, so there is no
/// evaluated map for them to collapse into.
test "the safe markup directives parse to their own items" {
  let items = items_of(
    safe_parse("<article @setinnerhtml=\".body\"></article>"),
  )
  assert_eq(items.length(), 1)
  guard! items[0]
    is SafeHtml(
      val=Some(ERead(place={ root: PState("body"), steps: [], .. }, ..))
    )
  let svg = items_of(safe_parse("<svg @setinnersvg=\".chart\"></svg>"))
  assert_eq(svg.length(), 1)
  guard! svg[0]
    is SafeSvg(
      val=Some(ERead(place={ root: PState("chart"), steps: [], .. }, ..))
    )
}

///|
/// The "push even on a failed parse" rule the raw-HTML directive established:
/// the item is there with the `None` sentinel, and the author is told.
test "a bad value is reported and the item is pushed anyway" {
  let issues : Array[@anode.ParseIssue] = []
  let (root, _) = collecting_parse(
    "<article @setinnerhtml=\".123bad\"></article>", issues,
  )
  let items = items_of(root.unwrap())
  assert_eq(items.length(), 1)
  assert_true(items[0] is SafeHtml(val=None))
  assert_eq(issues.length(), 1)
  assert_true(
    issues[0] is BadValue(role=Directive(name="setinnerhtml"), value=".123bad"),
  )
}

///|
/// Neither is the raw-markup construct, and `has_raw_html` is the predicate a
/// host reads to decide whether it needs to grant `raw_markup`. Answering
/// `true` here would make a host refuse a view that needs no permission at all.
test "the safe directives are not raw html" {
  assert_false(safe_parse("<div @setinnerhtml=\".x\"></div>").has_raw_html())
  assert_false(safe_parse("<div @setinnersvg=\".x\"></div>").has_raw_html())
  assert_true(
    safe_parse("<div @dangerouslysetinnerhtml=\".x\"></div>").has_raw_html(),
  )
}

///|
/// The builders produce exactly what the parser produces, which is what lets
/// `tutuca gen-views` emit a compiled view that behaves like a parsed one.
test "the builders round-trip with the parser" {
  guard! @anode.h(
      "article",
      [@anode.set_inner_html(val=@tutuca.Expr::field("body"))],
      [],
    )
    is Dom(d)
  guard! d.attrs is DynAttrs(items)
  assert_true(
    items[0]
    is SafeHtml(
      val=Some(ERead(place={ root: PState("body"), steps: [], .. }, ..))
    ),
  )
  // The failed-parse sentinel has a spelling too.
  guard! @anode.h("svg", [@anode.set_inner_svg()], []) is Dom(d2)
  guard! d2.attrs is DynAttrs(items2)
  assert_true(items2[0] is SafeSvg(val=None))
}

///|
/// A method named in either payload expression is collected, so a compiled
/// view knows the handler exists.
test "method names in the payload expression are collected" {
  let into : @set.Set[String] = Set([])
  safe_parse("<article @setinnerhtml=\"$render\"></article>").collect_method_names(
    into,
  )
  safe_parse("<svg @setinnersvg=\"$chart\"></svg>").collect_method_names(into)
  let names = into.iter().to_array()
  names.sort()
  debug_inspect(
    names,
    content=(
      #|["chart", "render"]
    ),
  )
}

// ---------------------------------------------------------------------------
// parse_fragment_svg

///|
fn svg_tag(doc : @html5.Document, id : Int) -> String {
  match doc.get_node(id) {
    Some(ElementNode(el)) => el.tag_name
    Some(TextNode(s)) => "#text:" + s
    _ => "#other"
  }
}

///|
/// The whole point: a fragment with no root of its own is SVG, and the source
/// case is adjusted through the HTML5 table on the way in.
test "a bare fragment parses into the SVG namespace" {
  let (doc, roots) = @anode.parse_fragment_svg(
    "<lineargradient></lineargradient><circle r=\"1\"/>",
  )
  assert_eq(roots.length(), 2)
  assert_eq(svg_tag(doc, roots[0]), "linearGradient")
  assert_eq(svg_tag(doc, roots[1]), "circle")
  assert_true(doc.get_ns(roots[0]) is Some(SVG))
  assert_true(doc.get_ns(roots[1]) is Some(SVG))
}

///|
/// The same source through the HTML entry point, for contrast — this is the
/// difference the second directive exists for, not a stylistic one. The
/// sanitizer keys element identity by namespace, so these two trees are asked
/// different questions.
test "the same fragment through parse_fragment is not SVG" {
  let (doc, roots) = @anode.parse_fragment("<circle r=\"1\"/>")
  assert_eq(roots.length(), 1)
  assert_true(doc.get_ns(roots[0]) is Some(HTML))
}

///|
/// A payload wearing its own `<svg>` root is fine and does not double-wrap:
/// the wrapper's children are the payload's root elements.
test "an explicit svg root is not wrapped twice" {
  let (doc, roots) = @anode.parse_fragment_svg("<svg><circle/></svg>")
  assert_eq(roots.length(), 1)
  assert_eq(svg_tag(doc, roots[0]), "svg")
  assert_eq(doc.get_children(roots[0]).length(), 1)
}

///|
/// `<foreignObject>` is the one route back to HTML, and it is the PARSER that
/// says so — which is what makes it safe, because the sanitizer then judges the
/// content as HTML rather than having to special-case it.
test "foreignObject content is HTML again" {
  let (doc, roots) = @anode.parse_fragment_svg(
    "<foreignobject><p>x</p></foreignobject>",
  )
  assert_eq(svg_tag(doc, roots[0]), "foreignObject")
  assert_true(doc.get_ns(roots[0]) is Some(SVG))
  let inner = doc.get_children(roots[0])
  assert_eq(svg_tag(doc, inner[0]), "p")
  assert_true(doc.get_ns(inner[0]) is Some(HTML))
}

///|
/// The documented divergence, and the safe direction to fail in: a payload that
/// closes the wrapper is TRUNCATED, not let out into the HTML namespace. The
/// SVG twin of the `</template>` case `parse_fragment` already documents.
test "a payload that closes the wrapper is truncated" {
  let (doc, roots) = @anode.parse_fragment_svg(
    "<circle/></svg><img src=\"/a.png\">",
  )
  assert_eq(roots.length(), 1)
  assert_eq(svg_tag(doc, roots[0]), "circle")
}

///|
/// Empty in, empty out — no root to unwrap and nothing to report.
test "an empty payload yields no roots" {
  let (_, roots) = @anode.parse_fragment_svg("")
  assert_eq(roots.length(), 0)
}
