///| The URL-scheme rule, which is the part of sanitization the Sanitizer API
/// does not do and the part a static pass cannot do.
///
/// The table below is the whole security claim of this package, so it is worth
/// reading as a specification rather than as coverage: everything in the
/// "allowed" column reaches the DOM, and everything in the "denied" column does
/// not.

///|
fn el(tag : String, attrs : Map[String, @vdom.AttrValue]) -> @vdom.Vdom {
  Node({ tag, attrs, childs: [], key: None, ns: None })
}

///|
fn filtered(tree : @vdom.Vdom) -> (@vdom.Vdom, Array[String]) {
  let f = UrlFilter::new()
  f.filter_tree(tree)
  (tree, f.take_reports().map(Dropped::to_string))
}

///|
/// A relative URL has no scheme and is what almost every real value is.
test "relative URLs are untouched" {
  for
    url in [
      "/about", "about.html", "../x", "#frag", "?q=1", "//example.com/x", "",
    ] {
    assert_true(url_value_allowed("href", url))
    debug_inspect(scheme_of(url), content="None")
  }
  // A colon after a path separator is not a scheme.
  debug_inspect(scheme_of("/a/b:c"), content="None")
  debug_inspect(scheme_of("?x=a:b"), content="None")
  assert_true(url_value_allowed("href", "/a/b:c"))
}

///|
/// Ordinary schemes are locators and stay.
test "ordinary schemes are allowed" {
  for
    url in [
      "https://example.com", "http://example.com", "mailto:a@b.c", "tel:+123", "blob:https://example.com/x",
      "ftp://example.com",
    ] {
    assert_true(url_value_allowed("href", url))
  }
}

///|
/// The whole point. Case and embedded whitespace are where the attacks live:
/// tab, newline and carriage return are stripped from ANYWHERE in a URL before
/// a browser reads the scheme, so a comparison that does not strip them first
/// is a comparison against the wrong string.
test "script schemes are denied however they are spelled" {
  for
    url in [
      "javascript:alert(1)", "JavaScript:alert(1)", "JAVASCRIPT:alert(1)", "  javascript:alert(1)",
      "\tjavascript:alert(1)", "java\tscript:alert(1)", "java\nscript:alert(1)",
      "java\rscript:alert(1)", "jav\ta\nscr\ript:alert(1)", "vbscript:msgbox(1)",
    ] {
    assert_false(url_value_allowed("href", url))
  }
  // The normalization, made visible.
  debug_inspect(
    scheme_of("java\tscript:x"),
    content=(
      #|Some("javascript")
    ),
  )
  debug_inspect(
    scheme_of("  \n HTTPS://x"),
    content=(
      #|Some("https")
    ),
  )
}

///|
/// `data:` is the one scheme whose answer depends on the attribute.
/// `<img src="data:image/png;base64,…">` is ordinary and useful;
/// `<a href="data:text/html,…">` is a document that runs in the page's origin.
test "data: depends on whether the attribute navigates" {
  for attr in ["href", "action", "formaction", "ping", "data", "xlink:href"] {
    assert_false(url_value_allowed(attr, "data:text/html,<script>x</script>"))
  }
  for attr in ["src", "srcset", "poster", "background"] {
    assert_true(url_value_allowed(attr, "data:image/png;base64,iVBOR"))
  }
}

///|
/// A denied value drops the ATTRIBUTE, not the element: the link stops being a
/// link and everything else about it survives. There is no author to report to
/// here — the value may have come from application state rather than from
/// anyone's template — so it is recorded instead.
test "a denied value drops the attribute and is recorded" {
  let (tree, reports) = filtered(
    el("A", {
      "href": Str("javascript:alert(1)"),
      "class": Str("btn"),
      "title": Str("go"),
    }),
  )
  guard tree is Node(e) else { fail("expected an element") }
  debug_inspect(e.attrs.contains("href"), content="false")
  debug_inspect(e.attrs.contains("class"), content="true")
  debug_inspect(e.attrs.contains("title"), content="true")
  debug_inspect(
    reports,
    content=(
      #|["dropped href on <A>: URL scheme is not one a view may navigate to (javascript:alert(1))"]
    ),
  )
}

///|
/// A list-valued attribute is not one URL. Checking only the whole string would
/// let a bad candidate ride along behind a good one.
test "srcset and ping are lists" {
  let (tree, reports) = filtered(
    el("IMG", { "srcset": Str("a.png 1x, javascript:alert(1) 2x") }),
  )
  guard tree is Node(e) else { fail("expected an element") }
  debug_inspect(e.attrs.contains("srcset"), content="false")
  debug_inspect(reports.length(), content="1")
  // A srcset with nothing wrong in it survives whole.
  let (ok, _) = filtered(el("IMG", { "srcset": Str("a.png 1x, b.png 2x") }))
  guard ok is Node(e2) else { fail("expected an element") }
  debug_inspect(e2.attrs.contains("srcset"), content="true")
  // ping is whitespace-separated rather than comma-separated.
  let (pinged, _) = filtered(
    el("A", { "ping": Str("/track javascript:alert(1)") }),
  )
  guard pinged is Node(e3) else { fail("expected an element") }
  debug_inspect(e3.attrs.contains("ping"), content="false")
}

///|
/// Only the URL-bearing names are inspected. An attribute that happens to
/// contain a colon is not a URL, and `data-*` is not `<object data>`.
test "non-URL attributes are not inspected" {
  let (tree, reports) = filtered(
    el("DIV", {
      "title": Str("javascript:not-a-url"),
      "data-note": Str("javascript:still-not"),
      "class": Str("a:b"),
    }),
  )
  guard tree is Node(e) else { fail("expected an element") }
  debug_inspect(e.attrs.length(), content="3")
  debug_inspect(reports, content="[]")
}

///|
/// The filter mutates in place. That is load-bearing rather than incidental:
/// morph short-circuits a subtree by PHYSICAL identity and the render cache
/// hands back the same `Vdom` object when a site's inputs have not changed, so
/// a filter that rebuilt nodes would quietly turn every render into a full
/// diff.
test "filtering preserves node identity" {
  let child = el("A", { "href": Str("javascript:alert(1)") })
  let tree : @vdom.Vdom = Node({
    tag: "DIV",
    attrs: {},
    childs: [child],
    key: None,
    ns: None,
  })
  let f = UrlFilter::new()
  f.filter_tree(tree)
  guard tree is Node(root) else { fail("expected an element") }
  // The same object, with the attribute gone from it.
  @test.assert_same_object(root.childs[0], child)
  guard child is Node(c) else { fail("expected an element") }
  debug_inspect(c.attrs.contains("href"), content="false")
}

///|
/// Raw markup is deliberately not this filter's business: its payload needs
/// parsing and a config, which is the next piece of work (docs/sanitizer.md,
/// pass 3). Passing it through rather than half-checking it keeps the boundary
/// honest.
test "an Html value is left for the filter that can parse it" {
  let (tree, reports) = filtered(
    el("DIV", { "dangerouslySetInnerHTML": Html("<a href=javascript:x>hi</a>") }),
  )
  guard tree is Node(e) else { fail("expected an element") }
  debug_inspect(e.attrs.contains("dangerouslySetInnerHTML"), content="true")
  debug_inspect(reports, content="[]")
}

///|
/// The bound exists so a component rendering a bad URL inside an `@each` over
/// ten thousand rows cannot turn the report log into the memory leak.
test "reports are bounded" {
  let f = UrlFilter::new(max_reports=2)
  for _i in 0..<10 {
    f.filter_tree(el("A", { "href": Str("javascript:alert(1)") }))
  }
  debug_inspect(f.take_reports().length(), content="2")
  // Draining resets it.
  f.filter_tree(el("A", { "href": Str("javascript:alert(1)") }))
  debug_inspect(f.take_reports().length(), content="1")
}
