///|
test "minimum-viable-component: renders nothing, but mounts" {
  let h = @harness.mount(minimum_viable_module(), "MinimumViableComponent")
  inspect(h.text("div"), content="")
}

///|
test "static-view-component: renders its static view" {
  let h = @harness.mount(static_view_module(), "StaticViewComponent")
  inspect(h.text("p"), content="Hello, world!")
}

///|
test "text-directive: renders fields, a method call, and every value type" {
  let h = @harness.mount(text_directive_module(), "TextDirective")
  inspect(h.text(".v-str"), content="hello")
  // @text PREPENDS: the element's own children survive
  inspect(h.text(".v-num"), content="42 <- text directive is prepended")
  // a null value renders NOTHING (JS drops null children in vdom addChild)
  inspect(h.text(".v-notset"), content="")
  inspect(h.text(".v-method"), content="HELLO")
  // <x text=".bool"> is a bare text node — no element of its own
  inspect(h.html().contains("true"), content="true")
}

///|
test "text-directive: custom values" {
  let h = @harness.mount(text_directive_module(), "TextDirective", args={
    "str": Str("tutuca"),
    "num": Num(100),
    "bool": Bool(false),
  })
  inspect(h.text(".v-str"), content="tutuca")
  inspect(h.text(".v-method"), content="TUTUCA")
  inspect(h.html().contains("false"), content="true")
}

///|
test "danger-set-inner-html: raw markup lands as real elements" {
  let h = @harness.mount(danger_set_inner_html_module(), "DangerSetInnerHtml")
  inspect(
    h.find(".raw").to_html(),
    content=(
      #|<div class="raw"><strong><em>Raw HTML!</em></strong></div>
    ),
  )
}

///|
test "danger-set-inner-html: custom markup" {
  let h = @harness.mount(danger_set_inner_html_module(), "DangerSetInnerHtml", args={
    "content": Str("<h3>Title</h3><ul><li>One</li><li>Two</li></ul>"),
  })
  inspect(
    h.find(".raw").to_html(),
    content=(
      #|<div class="raw"><h3>Title</h3><ul><li>One</li><li>Two</li></ul></div>
    ),
  )
}

///|
/// `@setinnermd` through the real mount path, which is what the storybook and
/// the landing-site editor both drive.
test "set-inner-md: markdown lands as real elements" {
  let h = @harness.mount(set_inner_md_module(), "SetInnerMd")
  inspect(
    h.find(".md").to_html(),
    content=(
      #|<div class="md"><h1>Markdown</h1><p>With <em>emphasis</em>, <code>code</code>, and a <a href="/docs">link</a>.</p><ul><li>and</li><li>a list</li></ul></div>
    ),
  )
}

///|
/// GFM, with nothing switched on to get it.
test "set-inner-md: tables, task lists and footnotes" {
  let h = @harness.mount(set_inner_md_module(), "SetInnerMd", args={
    "source": Str(
      "| a | b |\n|:--|--:|\n| 1 | 2 |\n\n- [x] task lists\n- [ ] and footnotes[^1]\n\n[^1]: like this\n",
    ),
  })
  inspect(
    h.find(".md").to_html(),
    content=(
      #|<div class="md"><table><thead><tr><th style="text-align:left">a</th><th style="text-align:right">b</th></tr></thead><tbody><tr><td style="text-align:left">1</td><td style="text-align:right">2</td></tr></tbody></table><ul><li><input type="checkbox"></input>task lists</li><li><input type="checkbox"></input>and footnotes<sup><a href="#fn-1">1</a></sup></li></ul><section class="footnotes"><ol><li id="fn-1"><p>like this</p></li></ol></section></div>
    ),
  )
  // `checked` and `disabled` are absent from that string and present on the
  // DOM, which is the correct half to assert. Both are IDL properties here —
  // `checked` never reflects to an attribute (the attribute is the DEFAULT
  // state, the property is the current one), and `set_prop` routes a `Bool` to
  // the property path for anything the element really has. Serializing does not
  // see them; the checkbox is still ticked and still inert.
  assert_true(h.prop("input", "checked", nth=0) is Some(Bool(true)))
  // The unticked one is not ticked. Asserted as "not true" rather than
  // "false", because the builder OMITS `checked` when the item is unchecked —
  // there is no attribute to set, so what the property reads back as is the
  // DOM's default, not something this code chose.
  assert_false(h.prop("input", "checked", nth=1) is Some(Bool(true)))
  for i in [0, 1] {
    assert_true(h.prop("input", "disabled", nth=i) is Some(Bool(true)))
  }
}

///|
/// The half the landing-site example exists to show. Every attack in the
/// storybook's "Sanitized" story, judged by the app's own sanitizer:
/// `<script>` in HTML's namespace AND in SVG's (different elements, since
/// identity is namespace-qualified), `<iframe>`, an `on*` handler dropped by
/// name, and a `javascript:` URL that takes the ATTRIBUTE with it and leaves
/// the link's words behind.
test "set-inner-md: the dangerous half renders nothing dangerous" {
  let h = @harness.mount(set_inner_md_module(), "SetInnerMd", args={
    "source": Str(
      "<script>alert(1)</script>\n\n<svg><script>alert(2)</script></svg>\n\n<iframe src=\"https://example.com\"></iframe>\n\n<div onclick=\"alert(3)\">handler dropped</div>\n\n[keeps its words, loses its href](javascript:alert(4))\n",
    ),
  })
  let html = h.find(".md").to_html()
  // Not one of them survived as an element.
  for tag in ["SCRIPT", "IFRAME"] {
    assert_true(h.find_all(tag).length() == 0)
  }
  // The handler is gone by NAME, whatever its value.
  assert_false(html.contains("onclick"))
  assert_false(html.contains("alert(3)"))
  // The link kept its words and lost its destination.
  assert_true(html.contains("keeps its words, loses its href"))
  assert_false(html.contains("javascript:"))
}
