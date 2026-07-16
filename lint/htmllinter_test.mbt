// Port of test/htmllinter.test.js (all describes, including the §A/§B
// regression pins and §C token-level lints). The JS suite runs each case
// against two tokenizers; here the WHATWG tokenizer from
// moonbit-community/html is the single engine.

///|
fn lint(
  html : String,
  fragment_context? : String = "template",
  transparent_tag_prefixes? : Array[String] = ["x"],
) -> Array[@lint.Finding] {
  @lint.lint_html(html, fragment_context~, transparent_tag_prefixes~)
}

///|
fn codes(findings : Array[@lint.Finding]) -> Array[@lint.LintCode] {
  findings.map(f => f.code)
}

///|
fn has_code(findings : Array[@lint.Finding], code : @lint.LintCode) -> Bool {
  findings.iter().any(f => f.code == code)
}

///|
fn info_of(f : @lint.Finding, key : String) -> String? {
  for pair in f.info {
    if pair.0 == key {
      return Some(pair.1)
    }
  }
  None
}

///|
fn has_action(findings : Array[@lint.Finding], action : String) -> Bool {
  findings
  .iter()
  .any(f => {
    f.code == HtmlTagNotAllowedInParent && info_of(f, "action") == Some(action)
  })
}

// ─── tag-name case violations (HTML namespace) ──────────────────────────────

///|
test "flags single uppercase letter" {
  let f = lint("<MyComp></MyComp>")
  assert_true(codes(f) == [HtmlTagNameHasUppercase])
  @debug.assert_eq(info_of(f[0], "raw"), Some("MyComp"))
  @debug.assert_eq(info_of(f[0], "lowercased"), Some("mycomp"))
}

///|
test "does not flag lowercase tags" {
  assert_eq(lint("<div><span></span></div>").length(), 0)
}

///|
test "flags multiple distinct uppercase tags" {
  let f = lint("<MyA><MyB></MyB></MyA>")
  assert_true(codes(f) == [HtmlTagNameHasUppercase, HtmlTagNameHasUppercase])
}

///|
test "does not flag custom-element kebab tags" {
  assert_eq(lint("<gd-gmap></gd-gmap>").length(), 0)
}

// ─── SVG tag-name case violations ───────────────────────────────────────────

///|
test "foreignObject and clipPath are allowed (WHATWG list)" {
  assert_eq(lint("<svg><foreignObject></foreignObject></svg>").length(), 0)
  assert_eq(lint("<svg><clipPath></clipPath></svg>").length(), 0)
}

///|
test "camelCase svg tag NOT in WHATWG list flags" {
  let f = lint("<svg><myThing></myThing></svg>")
  assert_true(codes(f) == [HtmlSvgTagWillLowercase])
  @debug.assert_eq(info_of(f[0], "raw"), Some("myThing"))
  @debug.assert_eq(info_of(f[0], "lowercased"), Some("mything"))
}

///|
test "lowercase svg tags pass" {
  assert_eq(lint("<svg><circle/><rect/></svg>").length(), 0)
}

// ─── table foster-parenting ─────────────────────────────────────────────────

///|
test "flags div inside table as foster-parent" {
  let f = lint("<table><div></div></table>")
  let fp = f.filter(x => x.code == HtmlTagNotAllowedInParent)
  assert_true(fp.length() >= 1)
  @debug.assert_eq(info_of(fp[0], "tag"), Some("div"))
  @debug.assert_eq(info_of(fp[0], "action"), Some("foster-parent"))
}

///|
test "non-whitespace text inside table is flagged, whitespace is fine" {
  assert_true(
    has_code(lint("<table>hello</table>"), HtmlTextNotAllowedInParent),
  )
  assert_eq(lint("<table>   \n   </table>").length(), 0)
}

///|
test "legal table structure with implicit closes" {
  assert_eq(lint("<table><tr><td>a<tr><td>b</tr></table>").length(), 0)
  assert_eq(
    lint("<thead><tr><td>x</td></tr><tr><td>y</td></tr></thead>").length(),
    0,
  )
}

///|
test "colgroup with non-col child foster-parents" {
  assert_true(
    has_code(
      lint("<colgroup><div></div></colgroup>"),
      HtmlTagNotAllowedInParent,
    ),
  )
}

// ─── select content model ───────────────────────────────────────────────────

///|
test "div inside select is flagged; options are fine; nested select closes" {
  assert_true(
    has_code(lint("<select><div></div></select>"), HtmlTagNotAllowedInParent),
  )
  assert_eq(
    lint("<select><option>a<optgroup><option>b</option></optgroup></select>").length(),
    0,
  )
  assert_true(
    has_code(lint("<select><select></select>"), HtmlTagNotAllowedInParent),
  )
}

// ─── ul/ol content model, p auto-close ──────────────────────────────────────

///|
test "div inside ul is not reparented; nested li auto-closes cleanly" {
  assert_eq(lint("<ul><div></div></ul>").length(), 0)
  assert_eq(lint("<ul><li>a<li>b</ul>").length(), 0)
}

///|
test "p auto-closes on block-level open" {
  assert_eq(lint("<p>foo<div></div></p>").length(), 0)
}

// ─── forms, interactive nesting, formatting ─────────────────────────────────

///|
test "form nested in form flags duplicate form" {
  assert_true(has_code(lint("<form><form></form></form>"), HtmlDuplicateForm))
}

///|
test "a inside a flags nested interactive" {
  assert_true(has_code(lint("<a><a></a></a>"), HtmlNestedInteractive))
}

///|
test "b/i misnesting triggers adoption agency" {
  assert_true(has_code(lint("<b><i></b></i>"), HtmlMisnestedFormatting))
}

// ─── raw-text content ───────────────────────────────────────────────────────

///|
test "script and style content is opaque" {
  assert_eq(lint("<script>if (a < b) { foo() }</script>").length(), 0)
  assert_eq(lint("<style>div > span { color: red }</style>").length(), 0)
}

// ─── void elements ──────────────────────────────────────────────────────────

///|
test "explicit </br> warns; self-closing voids are fine" {
  assert_true(has_code(lint("<br></br>"), HtmlVoidElementHasCloseTag))
  assert_eq(lint("<br/><img/><input/>").length(), 0)
}

// ─── template fragment context (default) ────────────────────────────────────

///|
test "template context allows option, tr, td, col at top level" {
  assert_eq(lint("<option>Foo</option><option>Bar</option>").length(), 0)
  assert_eq(lint("<tr><td>x</td></tr>").length(), 0)
  assert_eq(lint("<td>x</td>").length(), 0)
  assert_eq(lint("<col span=\"2\">").length(), 0)
}

///|
test "body context flags top-level tr" {
  assert_true(
    has_code(
      lint("<tr><td>x</td></tr>", fragment_context="body"),
      HtmlTagNotAllowedInParent,
    ),
  )
}

// ─── location reporting ─────────────────────────────────────────────────────

///|
test "line/column point at the offending tag-name start" {
  let f = lint("<div>\n  <Foo></Foo>\n</div>")
  guard f.iter().find_first(x => x.code == HtmlTagNameHasUppercase)
    is Some(finding)
  guard finding.location is Some(loc)
  assert_eq(loc.line, 2)
  assert_eq(loc.column, 4)
}

///|
test "first line is line 1" {
  let f = lint("<MyComp></MyComp>")
  guard f[0].location is Some(loc)
  assert_eq(loc.line, 1)
  assert_eq(loc.column, 2) // '<' is col 1, 'M' is col 2
}

// ─── §A regressions ─────────────────────────────────────────────────────────

///|
test "A1: bare font inside svg stays foreign; font with color/face/size breaks out" {
  assert_eq(lint("<svg><font>x</font></svg>").length(), 0)
  assert_true(
    has_action(
      lint("<svg><font color=\"red\"></font></svg>"),
      "foreign-breakout",
    ),
  )
  assert_true(
    has_action(lint("<svg><font face=\"x\"></font></svg>"), "foreign-breakout"),
  )
  assert_true(
    has_action(lint("<svg><font size=\"2\"></font></svg>"), "foreign-breakout"),
  )
}

///|
test "A2: foreignObject bounds the button scope walk" {
  let f = lint(
    "<button><svg><foreignObject><button></button></foreignObject></svg></button>",
  )
  assert_eq(codes(f).filter(c => c == HtmlTagNotAllowedInParent).length(), 0)
}

///|
test "A3: button inside select reports (select content model)" {
  assert_true(
    has_code(
      lint("<button><select><button></button></select></button>"),
      HtmlTagNotAllowedInParent,
    ),
  )
}

///|
test "A5: annotation-xml encoding=text/html is an HTML integration point" {
  assert_eq(
    lint(
      "<math><annotation-xml encoding=\"text/html\"><div></div></annotation-xml></math>",
    ).length(),
    0,
  )
  assert_true(
    has_action(
      lint("<math><annotation-xml><div></div></annotation-xml></math>"),
      "foreign-breakout",
    ),
  )
}

///|
test "A8: sequential forms are fine, nested form still flagged" {
  assert_eq(lint("<form></form><form></form>").length(), 0)
  assert_true(has_code(lint("<form><form></form></form>"), HtmlDuplicateForm))
}

///|
test "A10: transparentTagPrefixes is case-insensitive" {
  assert_eq(lint("<x></x>", transparent_tag_prefixes=["X"]).length(), 0)
  assert_eq(
    lint("<x:macro></x:macro>", transparent_tag_prefixes=["X"]).length(),
    0,
  )
}

// ─── §B additions ───────────────────────────────────────────────────────────

///|
test "B2: input type=hidden allowed inside table, type=text foster-parents" {
  assert_eq(lint("<table><input type=\"hidden\"></table>").length(), 0)
  assert_true(
    has_code(
      lint("<table><input type=\"text\"></table>"),
      HtmlTagNotAllowedInParent,
    ),
  )
}

///|
test "B8: unmatched end tag past a special element warns; implied closes stay silent" {
  assert_true(
    has_code(lint("<article></span></article>"), HtmlUnexpectedEndTag),
  )
  assert_eq(lint("<ul><li><p>x</ul>").length(), 0)
}

///|
test "B10: foreign end tags fall through to HTML mode" {
  assert_eq(lint("<div><svg><circle></circle></svg></div>").length(), 0)
  assert_eq(lint("<p><svg></svg></p>").length(), 0)
}

// ─── §C token-level lints ───────────────────────────────────────────────────

///|
test "duplicate attribute warns, distinct attrs are fine" {
  assert_true(
    has_code(
      lint("<div class=\"a\" class=\"b\"></div>"),
      HtmlDuplicateAttribute,
    ),
  )
  assert_eq(lint("<div class=\"a\" id=\"b\"></div>").length(), 0)
}

///|
test "attributes on end tag and self-closing end tag warn" {
  assert_true(
    has_code(lint("<div></div class=\"foo\">"), HtmlAttributesOnEndTag),
  )
  assert_true(has_code(lint("<div></div/>"), HtmlSelfClosingEndTag))
  assert_eq(lint("<div></div>").length(), 0)
}

///|
test "missing attribute value warns, quoted empty is fine" {
  assert_true(has_code(lint("<input value=>"), HtmlMissingAttributeValue))
  assert_eq(lint("<input value=\"\">").length(), 0)
}

///|
test "CDATA warns in HTML, fine inside svg" {
  assert_true(has_code(lint("<![CDATA[some data]]>"), HtmlCdataInHtmlNamespace))
  assert_eq(lint("<svg><![CDATA[some data]]></svg>").length(), 0)
}

///|
test "bogus comment warns, real comment does not" {
  assert_true(has_code(lint("<!foo>"), HtmlBogusComment))
  assert_eq(lint("<!-- normal comment -->").length(), 0)
}

///|
test "svg attr case correction: viewbox warns, viewBox is clean" {
  assert_true(
    has_code(
      lint("<svg viewbox=\"0 0 10 10\"></svg>"),
      HtmlSvgAttrWillLowercase,
    ),
  )
  assert_eq(lint("<svg viewBox=\"0 0 10 10\"></svg>").length(), 0)
}

///|
test "mathml attr case correction: definitionurl warns" {
  assert_true(
    has_code(
      lint("<math definitionurl=\"x\"></math>"),
      HtmlMathmlAttrWillLowercase,
    ),
  )
}

///|
test "unclosed span before </div> warns; implied li is silent" {
  assert_true(has_code(lint("<div><span></div>"), HtmlUnclosedBeforeEnd))
  assert_eq(lint("<ul><li>a<li>b</ul>").length(), 0)
}

///|
test "duplicate attribute and misnested formatting report together" {
  let f = lint("<b class=\"a\" class=\"b\"><i></b></i>")
  assert_true(has_code(f, HtmlDuplicateAttribute))
  assert_true(has_code(f, HtmlMisnestedFormatting))
}

// ─── valid tutuca usage stays clean ─────────────────────────────────────────

///|
test "representative tutuca templates produce zero findings" {
  for
    tpl in [
      "<div class=\"m-4\"><x text=\".title\"></x></div>", "<ul><li @each=\".items\"><x text=\"@value\"></x></li></ul>",
      "<x:card title=\"hi\"><x slot=\"body\"><p>content</p></x></x:card>", "<table><tr @x render-each=\".rows\"></tr></table>",
      "<select><option @x render-each=\".opts\" as=\"option\"></option></select>",
      "<svg viewBox=\"0 0 24 24\"><path d=\"M0 0\"/></svg>", "<form @on.submit=\"save\"><input type=\"text\" :value=\".name\"><button>ok</button></form>",
    ] {
    let f = lint(tpl)
    if f.length() > 0 {
      fail("expected zero findings for \{tpl}, got \{to_repr(f)}")
    }
  }
}
