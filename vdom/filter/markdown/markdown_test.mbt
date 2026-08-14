///| Markdown, admitted as described nodes.
///
/// The claim under test is that a markdown payload nobody could see at
/// registration reaches the DOM as nodes the sanitizer approved one at a time —
/// elements AND attribute values — and without `set_inner_html` ever being
/// called, which is guaranteed here by the attribute being gone.

///|
fn host(source : String) -> @vdom.Vdom {
  @vdom.h("DIV", attrs={ "setInnerMd": Md(source) })
}

///|
fn run(
  source : String,
  sanitizer? : @sanitize.Sanitizer = @sanitize.Sanitizer::default(),
) -> (String, Array[String]) {
  let tree = host(source)
  let f = MdFilter::new(sanitizer~)
  f.filter_tree(tree)
  (shape(tree), f.take_reports().map(@filter.Dropped::to_string))
}

///|
/// Rendered as text, so the shape of the result is legible in one line.
fn shape(v : @vdom.Vdom) -> String {
  match v {
    Text(s) => s
    Comment(s) => "<!--\{s}-->"
    Fragment(cs) => cs.map(shape).join("")
    Node(el) => {
      let attrs = el.attrs
        .iter()
        .map(pair => " \{pair.0}=\{pair.1.to_attr_string()}")
        .to_array()
      attrs.sort()
      let inner = el.childs.map(shape).join("")
      "<\{el.tag}\{attrs.join("")}>\{inner}</\{el.tag}>"
    }
  }
}

// ---------------------------------------------------------------------------
// The construct itself

///|
/// The attribute is GONE, which is the point. `set_prop` fails closed on that
/// name — it clears the element rather than writing anything — so a filter that
/// left it behind would render an empty div, and one that wrote markdown to
/// `set_inner_html` would be worse. Neither happens.
test "the payload becomes children and the directive disappears" {
  let tree = host("# Title\n\ntext\n")
  let f = MdFilter::new()
  f.filter_tree(tree)
  guard tree is Node(el) else { fail("expected an element") }
  debug_inspect(el.attrs.contains(MD_ATTR), content="false")
  inspect(
    shape(tree),
    content=(
      #|<DIV><H1>Title</H1><P>text</P></DIV>
    ),
  )
  debug_inspect(f.take_reports(), content="[]")
}

///|
/// Declared children are replaced, the same way the raw-markup directive
/// replaces them.
test "declared children do not survive the payload" {
  let tree = @vdom.h("DIV", attrs={ "setInnerMd": Md("hi") }, childs=[
    @vdom.h("SPAN", childs=[Text("gone")]),
  ])
  MdFilter::new().filter_tree(tree)
  inspect(
    shape(tree),
    content=(
      #|<DIV><P>hi</P></DIV>
    ),
  )
}

///|
/// A value that is not markdown under that name is dropped rather than
/// reasoned about — and dropping it matters, because leaving it would make
/// `set_prop` clear the element.
test "a non-Md value under the name is just removed" {
  let tree = @vdom.h("DIV", attrs={ "setInnerMd": Str("hi") }, childs=[
    Text("kept"),
  ])
  MdFilter::new().filter_tree(tree)
  inspect(
    shape(tree),
    content=(
      #|<DIV>kept</DIV>
    ),
  )
}

// ---------------------------------------------------------------------------
// Ordinary documents

///|
test "block structure" {
  let (out, reports) = run(
    "# H1\n\npara with *em* and **strong**\n\n> quoted\n\n---\n",
  )
  inspect(
    out,
    content=(
      #|<DIV><H1>H1</H1><P>para with <EM>em</EM> and <STRONG>strong</STRONG></P><BLOCKQUOTE><P>quoted</P></BLOCKQUOTE><HR></HR></DIV>
    ),
  )
  debug_inspect(reports, content="[]")
}

///|
/// A tight list unwraps the paragraph; a loose one keeps it.
test "lists, tight and loose" {
  let (tight, _) = run("- a\n- b\n")
  inspect(
    tight,
    content=(
      #|<DIV><UL><LI>a</LI><LI>b</LI></UL></DIV>
    ),
  )
  let (loose, _) = run("- a\n\n- b\n")
  inspect(
    loose,
    content=(
      #|<DIV><UL><LI><P>a</P></LI><LI><P>b</P></LI></UL></DIV>
    ),
  )
}

///|
test "an ordered list carries its start only when it is not 1" {
  let (one, _) = run("1. a\n")
  inspect(
    one,
    content=(
      #|<DIV><OL><LI>a</LI></OL></DIV>
    ),
  )
  let (five, _) = run("5. a\n")
  inspect(
    five,
    content=(
      #|<DIV><OL start=5><LI>a</LI></OL></DIV>
    ),
  )
}

///|
/// GFM, with nothing switched on to get it.
test "task lists become disabled checkboxes" {
  let (out, _) = run("- [x] done\n- [ ] todo\n")
  inspect(
    out,
    content=(
      #|<DIV><UL><LI><INPUT checked=true disabled=true type=checkbox></INPUT>done</LI><LI><INPUT disabled=true type=checkbox></INPUT>todo</LI></UL></DIV>
    ),
  )
}

///|
test "tables carry their alignment as a style" {
  let (out, _) = run("| a | b |\n|:--|--:|\n| 1 | 2 |\n")
  inspect(
    out,
    content=(
      #|<DIV><TABLE><THEAD><TR><TH style=text-align:left>a</TH><TH style=text-align:right>b</TH></TR></THEAD><TBODY><TR><TD style=text-align:left>1</TD><TD style=text-align:right>2</TD></TR></TBODY></TABLE></DIV>
    ),
  )
}

///|
test "fenced code keeps its language as a class and its body as text" {
  let (out, _) = run("```moonbit\nlet x = 1\n```\n")
  inspect(
    out,
    content=(
      #|<DIV><PRE><CODE class=language-moonbit>let x = 1
      #|</CODE></PRE></DIV>
    ),
  )
}

///|
/// Text is a text node, so there is no markup context for it to break out of
/// and nothing to escape. A `<script>` typed as prose stays prose.
test "text is text, not markup" {
  let (out, reports) = run("a < b & c \"d\"\n")
  inspect(
    out,
    content=(
      #|<DIV><P>a < b & c "d"</P></DIV>
    ),
  )
  debug_inspect(reports, content="[]")
}

///|
test "footnotes become a reference and a section" {
  let (out, _) = run("text[^a]\n\n[^a]: the note\n")
  inspect(
    out,
    content=(
      #|<DIV><P>text<SUP><A href=#fn-a>a</A></SUP></P><SECTION class=footnotes><OL><LI id=fn-a><P>the note</P></LI></OL></SECTION></DIV>
    ),
  )
}

///|
test "reference links resolve, case-insensitively" {
  let (out, _) = run("[t][REF]\n\n[ref]: /u \"ti\"\n")
  inspect(
    out,
    content=(
      #|<DIV><P><A href=/u title=ti>t</A></P></DIV>
    ),
  )
}

///|
/// An unresolved reference keeps the words and loses the brackets.
test "an unresolved reference is not a link" {
  let (out, _) = run("[t][nope]\n")
  inspect(
    out,
    content=(
      #|<DIV><P>t</P></DIV>
    ),
  )
}

// ---------------------------------------------------------------------------
// The autolink rule

///|
/// The case this package would be wrong without. Upstream's autolink scanner
/// accepts any `<…>` with no whitespace, so a bare inline tag arrives as an
/// `Autolink` — and turning those into `<a>` would fill a comment body with
/// stray links to relative paths. Only a URL with a real scheme becomes a link.
test "bare inline tags are text, not links" {
  let (out, reports) = run("a <span>b</span> c\n")
  inspect(
    out,
    content=(
      #|<DIV><P>a <span>b</span> c</P></DIV>
    ),
  )
  debug_inspect(reports, content="[]")
}

///|
test "a real autolink is a link, and an email gets mailto" {
  let (out, _) = run("<https://e.com> and <a@e.com>\n")
  inspect(
    out,
    content=(
      #|<DIV><P><A href=https://e.com>https://e.com</A> and <A href=mailto:a@e.com>a@e.com</A></P></DIV>
    ),
  )
}

// ---------------------------------------------------------------------------
// URL values

///|
/// The value half, which the sanitizer config has no opinion about. A denied
/// `href` drops the ATTRIBUTE, not the element: the words survive, inert.
test "a javascript url loses the href and keeps the text" {
  let (out, reports) = run("[click](javascript:alert(1))\n")
  inspect(
    out,
    content=(
      #|<DIV><P><A>click</A></P></DIV>
    ),
  )
  inspect(
    reports.join("\n"),
    content=(
      #|dropped href on <DIV>: URL scheme is not one a view may navigate to (javascript:alert(1))
    ),
  )
}

///|
/// Normalization happens before the scheme is read, so case does not smuggle it
/// through. This is the obfuscation that actually reaches the rule: a
/// destination markdown is willing to parse.
test "case does not smuggle a javascript url past the rule" {
  let (out, reports) = run("[click](JaVaScRiPt:alert(1))\n")
  inspect(
    out,
    content=(
      #|<DIV><P><A>click</A></P></DIV>
    ),
  )
  inspect(reports.length(), content="1")
}

///|
/// The classic `java\tscript:` never gets as far as the URL rule, because
/// markdown will not accept whitespace in a bare link destination — the whole
/// construct falls back to text. Worth pinning as its own case so that nobody
/// reads the test above as covering it: the defence here is the parser's, and
/// `@filter.scheme_of` owns the same trick for values that arrive by any other
/// route (`vdom/filter/url_test.mbt`).
test "an embedded tab stops the link from being a link at all" {
  let (out, reports) = run("[click](java\tscript:alert(1))\n")
  inspect(
    out,
    content=(
      #|<DIV><P>[click](java	script:alert(1))</P></DIV>
    ),
  )
  debug_inspect(reports, content="[]")
}

///|
/// `data:` splits by attribute: ordinary on an image, a same-origin document on
/// a link.
test "data urls are allowed on img and denied on a" {
  let (img, img_reports) = run("![a](data:image/png;base64,AAAA)\n")
  inspect(
    img,
    content=(
      #|<DIV><P><IMG alt=a src=data:image/png;base64,AAAA></IMG></P></DIV>
    ),
  )
  debug_inspect(img_reports, content="[]")
  let (link, _) = run("[t](data:text/html,<script>alert(1)</script>)\n")
  inspect(
    link,
    content=(
      #|<DIV><P><A>t</A></P></DIV>
    ),
  )
}

///|
test "a relative url is fine" {
  let (out, reports) = run("[t](/docs/a.html)\n")
  inspect(
    out,
    content=(
      #|<DIV><P><A href=/docs/a.html>t</A></P></DIV>
    ),
  )
  debug_inspect(reports, content="[]")
}

// ---------------------------------------------------------------------------
// Raw HTML inside the document

///|
/// Through the SAME builder `@dangerouslysetinnerhtml` uses, so the unsafe
/// baseline applies here without this package knowing what is on it.
///
/// The report says `setInnerMd`, not `dangerouslySetInnerHTML`. Four directives
/// reach that builder now, and a developer reading a drop log wants the name of
/// the attribute in their own view — the shared builder is an implementation
/// detail they did not write.
test "a script in an html block produces no element" {
  let (out, reports) = run("<div>ok<script>alert(1)</script></div>\n")
  inspect(
    out,
    content=(
      #|<DIV><DIV>ok</DIV>
      #|</DIV>
    ),
  )
  inspect(
    reports.join("\n"),
    content=(
      #|dropped setInnerMd on <DIV>: element is not allowed here (<script>)
    ),
  )
}

///|
/// The SVG hole the baseline was once wrong about, reached through markdown
/// this time.
test "an svg script in an html block produces no element" {
  let (out, reports) = run("<div><svg><script>alert(1)</script></svg></div>\n")
  inspect(
    out,
    content=(
      #|<DIV><DIV><svg></svg></DIV>
      #|</DIV>
    ),
  )
  inspect(reports.length(), content="1")
}

///|
/// An event handler on raw HTML, which is a name rule rather than a value one.
test "an event handler attribute in an html block is dropped" {
  let (out, _) = run("<div onclick=\"alert(1)\">hi</div>\n")
  inspect(
    out,
    content=(
      #|<DIV><DIV>hi</DIV>
      #|</DIV>
    ),
  )
}

///|
/// An HTML comment is the ONLY thing upstream's inline parser produces
/// `HtmlInline` for, and it follows `Sanitizer.comments` like any other.
test "inline comments follow the comments setting" {
  let (kept, _) = run("a <!-- note --> b\n")
  inspect(
    kept,
    content=(
      #|<DIV><P>a <!-- note --> b</P></DIV>
    ),
  )
  let dropped = @sanitize.Sanitizer::new({
    ..@sanitize.SanitizerConfig::empty(),
    comments: Some(false),
  })
  let (out, _) = run("a <!-- note --> b\n", sanitizer=dropped)
  inspect(
    out,
    content=(
      #|<DIV><P>a  b</P></DIV>
    ),
  )
}

// ---------------------------------------------------------------------------
// The config

///|
/// The lever a host actually has over markdown: name the elements. There is no
/// permission to withhold, because there is nothing unchecked to permit.
test "an allow-list without img drops images and keeps the rest" {
  let s = @sanitize.Sanitizer::new({
    ..@sanitize.SanitizerConfig::empty(),
    elements: Some(
      ["p", "a", "em"].map(n => @sanitize.ElementRule::of(@sanitize.html(n))),
    ),
  })
  let (out, reports) = run("text ![a](x.png) and *em*\n", sanitizer=s)
  inspect(
    out,
    content=(
      #|<DIV><P>text  and <EM>em</EM></P></DIV>
    ),
  )
  inspect(
    reports.join("\n"),
    content=(
      #|dropped setInnerMd on <DIV>: element is not allowed here (<img>)
    ),
  )
}

///|
/// `replaceWithChildrenElements`: the element goes, its content stays.
test "an unwrap rule keeps the content" {
  let s = @sanitize.Sanitizer::new({
    ..@sanitize.SanitizerConfig::empty(),
    replace_with_children_elements: Some([@sanitize.html("em")]),
  })
  let (out, _) = run("a *b* c\n", sanitizer=s)
  inspect(
    out,
    content=(
      #|<DIV><P>a b c</P></DIV>
    ),
  )
}

///|
/// A `remove_attributes` naming `style` takes the table alignment with it,
/// which is the config doing its job rather than a bug here.
test "removing style takes the table alignment with it" {
  let s = @sanitize.Sanitizer::new({
    ..@sanitize.SanitizerConfig::empty(),
    remove_attributes: Some(["style"]),
  })
  let (out, _) = run("| a |\n|:--|\n| 1 |\n", sanitizer=s)
  inspect(
    out,
    content=(
      #|<DIV><TABLE><THEAD><TR><TH>a</TH></TR></THEAD><TBODY><TR><TD>1</TD></TR></TBODY></TABLE></DIV>
    ),
  )
}

///|
/// The concrete instance of why this does not serialize, found by rendering the
/// landing-site example in a real browser and reading the DOM back.
///
/// `java&#9;script:` is the classic entity obfuscation. It arrives by two
/// routes, and they are safe for DIFFERENT reasons — which is the whole point:
///
/// - **As raw HTML**, `@anode.parse_fragment` is a real HTML parser, so it
///   DECODES the entity to a tab before the value is looked at.
///   `attr_value_allowed` strips the tab, reads the scheme as `javascript`, and
///   denies it. The normalization does exactly the work it exists for.
/// - **As a markdown link destination**, nothing decodes it — markdown has no
///   entity rule here — so the value stays the literal characters. The scheme
///   is `java&#9;script`, which no browser registers, and the attribute reaches
///   the DOM through `setAttribute`, where entities are not a thing. It never
///   becomes `javascript:` at any point.
///
/// **The second one is what a serializing design would get wrong.** Write the
/// sanitized tree back out as HTML text and hand it to `innerHTML`, and the
/// browser's parser decodes `&#9;` on the way back in — turning a value this
/// code correctly allowed as an unknown scheme into `java\tscript:`, which
/// Blink normalizes to `javascript:` and fires. Same input, same sanitizer,
/// opposite outcome, and the only difference is the second parse. Building
/// nodes is what removes it.
test "an entity in a url is decoded on the html route and never on the markdown one" {
  // Raw HTML — a real block, so it goes through `parse_fragment`. Decoded,
  // normalized, denied: the anchor survives with no href at all.
  let raw = host("<div><a href=\"java&#9;script:alert(1)\">x</a></div>\n")
  MdFilter::new().filter_tree(raw)
  guard raw is Node(rd) else { fail("expected an element") }
  guard rd.childs[0] is Node(inner) else { fail("expected the html block") }
  guard inner.childs[0] is Node(ra) else { fail("expected an anchor") }
  debug_inspect(ra.attrs.contains("href"), content="false")

  // Markdown destination — never decoded, so never `javascript:`. It survives
  // as an unknown scheme, which navigates nowhere.
  let md = host("[x](java&#9;script:alert(1))\n")
  MdFilter::new().filter_tree(md)
  guard md is Node(mdiv) else { fail("expected an element") }
  guard mdiv.childs[0] is Node(p) else { fail("expected a paragraph") }
  guard p.childs[0] is Node(a) else { fail("expected an anchor") }
  // The literal characters, `&#9;` included — not a tab, and not `javascript:`.
  inspect(
    a.attrs.get("href").unwrap().to_attr_string(),
    content=(
      #|java&#9;script:alert(1)
    ),
  )
}

///|
/// The adjacent trap, and the reason the test above uses a `<div>` wrapper.
///
/// `<a href="…">x</a>` on a line of its own is NOT a CommonMark HTML block —
/// type 7 wants the tag alone on the line — so the whole thing is a PARAGRAPH
/// OF TEXT. There is no anchor and no attribute; the characters reach the DOM
/// through `createTextNode` and are inert.
///
/// It is worth a test because of how it READS in a failure message: memdom and
/// this file's `shape()` both print a text node verbatim, so an unsanitized
/// `<a href="javascript:…">` appears in the output string exactly as it would
/// if it were a live element. Asserting on the string would have called this a
/// hole; asking the tree what it contains gets the right answer.
test "an inline anchor is a text node, not an element" {
  let tree = host("<a href=\"javascript:alert(1)\">x</a>\n")
  MdFilter::new().filter_tree(tree)
  guard tree is Node(div) else { fail("expected an element") }
  guard div.childs[0] is Node(p) else { fail("expected a paragraph") }
  // Every child is text. No element, so nothing to sanitize and nothing to run.
  for c in p.childs {
    assert_true(c is Text(_))
  }
  assert_true(
    p.childs.iter().any(c => c is Text(t) && t.contains("javascript:")),
  )
}

///|
/// Which attacks are DROPPED and which are DEGRADED — both safe, by different
/// mechanisms, and the split is not the one you would guess.
///
/// mizchi's block parser recognises some raw-HTML openers as HTML blocks and
/// not others. The ones it recognises go through `@markup.html_nodes` and are
/// dropped as elements, with a report. The ones it does not fall through to the
/// inline parser, become bogus autolinks or text, and land as TEXT NODES —
/// visible characters that reach the DOM through `createTextNode` and can never
/// be parsed as markup. Nothing is reported for those, because nothing was
/// dropped: they were never markup in the first place.
///
/// Notably `<script>` is in the SECOND group. That reads alarming in any output
/// that prints text unescaped (memdom's `to_html`, this file's `shape`), and it
/// is why the browser check for this feature asked the DOM for `script` element
/// COUNT rather than searching the serialized string.
///
/// This is pinned because it is exactly what a parser bump would move. A future
/// upstream that adds `script` to its HTML-block list flips that case from
/// "text, no report" to "dropped, one report" — still safe, but a visible
/// change to what the landing-site example demonstrates.
test "attacks are either dropped as elements or degraded to inert text" {
  // Recognised as HTML blocks: dropped, and reported.
  for
    c in [
      ("<svg><script>alert(1)</script></svg>\n", "script"),
      ("<iframe src=\"https://e.com\"></iframe>\n", "iframe"),
      ("<base href=\"https://e.com/\">\n", "base"),
      ("<div onclick=\"alert(1)\">x</div>\n", "onclick"),
    ] {
    let (src, _) = c
    let (out, reports) = run(src)
    assert_true(reports.length() >= 1)
    assert_false(out.contains("alert(1)"))
  }

  // Not recognised: no element is ever built, so there is nothing to drop and
  // nothing to report. The characters survive as text.
  for
    src in [
      "<script>alert(1)</script>\n", "<object data=\"x\"></object>\n", "<span style=\"color:red\">x</span>\n",
    ] {
    let tree = host(src)
    let f = MdFilter::new()
    f.filter_tree(tree)
    debug_inspect(f.take_reports(), content="[]")
    // Every descendant of the paragraph is a text node — no elements at all.
    guard tree is Node(div) else { fail("expected an element") }
    guard div.childs[0] is Node(p) else { fail("expected a paragraph") }
    for c in p.childs {
      assert_true(c is Text(_))
    }
  }
}
