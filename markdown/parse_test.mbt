///| The vendored parser, held to the shape `vdom/filter/markdown` walks.
///
/// These are OURS, not upstream's — upstream's own tests are not vendored, so
/// this file is the thing a re-sync has to get past. What it pins is not
/// CommonMark conformance (upstream owns that) but the handful of AST facts the
/// node builder is written against, each of which would be a silent behaviour
/// change if a later version moved it:
///
/// - which constructs exist at all, since the builder matches exhaustively;
/// - that GFM (tables, task lists, strikethrough, footnotes) is on with no
///   configuration, because there is no flag here to turn it on;
/// - **that inline raw HTML is only ever an HTML COMMENT**, and that a bare
///   inline tag comes back as a bogus `Autolink` rather than as markup. Both
///   halves are load-bearing — see the two tests at the bottom of this file.

///|
/// The AST as one line, so a test reads as a claim rather than a dump.
fn shape(doc : Document) -> String {
  doc.children.map(block).join("")
}

///|
fn block(b : Block) -> String {
  match b {
    ThematicBreak(..) => "(hr)"
    Heading(level~, children~, ..) => "(h\{level} \{inlines(children)})"
    Paragraph(children~, ..) => "(p \{inlines(children)})"
    FencedCode(info~, code~, ..) => "(fence \{info.escape()} \{code.escape()})"
    IndentedCode(code~, ..) => "(code \{code.escape()})"
    Blockquote(children~, ..) => "(quote \{children.map(block).join("")})"
    BulletList(tight~, items~, ..) =>
      "(ul\{if tight { "" } else { " loose" }} \{items.map(item).join("")})"
    OrderedList(start~, items~, ..) =>
      "(ol@\{start} \{items.map(item).join("")})"
    HtmlBlock(html~, ..) => "(html \{html.escape()})"
    Table(header~, alignments~, rows~, ..) => {
      let al = alignments.map(align).join(",")
      let hd = header.map(cell).join("")
      let bd = rows.map(r => "[\{r.map(cell).join("")}]").join("")
      "(table [\{al}] \{hd} \{bd})"
    }
    BlankLines(..) => ""
    FootnoteDefinition(label~, children~, ..) =>
      "(footnote \{label} \{children.map(block).join("")})"
  }
}

///|
fn item(li : ListItem) -> String {
  let box = match li.checked {
    Some(true) => "[x]"
    Some(false) => "[ ]"
    None => ""
  }
  "(li\{box} \{li.children.map(block).join("")})"
}

///|
fn cell(c : TableCell) -> String {
  "(td \{inlines(c.children)})"
}

///|
fn align(a : TableAlign) -> String {
  match a {
    Left => "l"
    Center => "c"
    Right => "r"
    None => "-"
  }
}

///|
fn inlines(xs : Array[Inline]) -> String {
  xs.map(inline).join("")
}

///|
fn inline(i : Inline) -> String {
  match i {
    Text(content~, ..) => content.escape()
    SoftBreak(..) => "(soft)"
    HardBreak(..) => "(br)"
    Emphasis(children~, ..) => "(em \{inlines(children)})"
    Strong(children~, ..) => "(strong \{inlines(children)})"
    Strikethrough(children~, ..) => "(del \{inlines(children)})"
    Code(content~, ..) => "(tt \{content.escape()})"
    WikiLink(target~, ..) => "(wiki \{target})"
    Link(children~, url~, title~, ..) =>
      "(a \{url.escape()}\{if title == "" { "" } else { " " + title.escape() }} \{inlines(children)})"
    RefLink(children~, label~, ..) => "(aref \{label} \{inlines(children)})"
    Autolink(url~, is_email~, ..) =>
      "(auto\{if is_email { ":mail" } else { "" }} \{url.escape()})"
    Image(alt~, url~, ..) => "(img \{url.escape()} \{alt.escape()})"
    RefImage(alt~, label~, ..) => "(imgref \{label} \{alt.escape()})"
    HtmlInline(html~, ..) => "(rawinline \{html.escape()})"
    FootnoteReference(label~, ..) => "(fnref \{label})"
  }
}

///|
test "headings, paragraphs and the emphasis pair" {
  inspect(
    shape(parse("# Title\n\nsome *soft* and **hard** text\n").document),
    content=(
      #|(h1 "Title")(p "some "(em "soft")" and "(strong "hard")" text")
    ),
  )
}

///|
/// Setext, so the builder cannot assume `style` is always `Atx`.
test "setext headings reach the same variant" {
  inspect(
    shape(parse("Title\n=====\n\nSub\n---\n").document),
    content=(
      #|(h1 "Title")(h2 "Sub")
    ),
  )
}

///|
test "lists carry tightness, start and nesting" {
  inspect(
    shape(parse("- one\n- two\n\n3. three\n4. four\n").document),
    content=(
      #|(ul (li (p "one"))(li (p "two")))(ol@3 (li (p "three"))(li (p "four")))
    ),
  )
}

///|
/// GFM, with nothing switched on to get it.
test "task lists put the checkbox on the item, not in the text" {
  inspect(
    shape(parse("- [x] done\n- [ ] todo\n").document),
    content=(
      #|(ul (li[x] (p "done"))(li[ ] (p "todo")))
    ),
  )
}

///|
test "tables keep their alignments" {
  inspect(
    shape(parse("| a | b | c |\n|:--|:-:|--:|\n| 1 | 2 | 3 |\n").document),
    content=(
      #|(table [l,c,r] (td "a")(td "b")(td "c") [(td "1")(td "2")(td "3")])
    ),
  )
}

///|
test "strikethrough and inline code" {
  inspect(
    shape(parse("~~gone~~ and `kept`\n").document),
    content=(
      #|(p (del "gone")" and "(tt "kept"))
    ),
  )
}

///|
test "footnotes are a reference and a definition" {
  inspect(
    shape(parse("text[^a]\n\n[^a]: the note\n").document),
    content=(
      #|(p "text"(fnref a))(footnote a (p "the note"))
    ),
  )
}

///|
/// The URL sits on the node as a plain string — un-escaped, un-normalized, and
/// entirely untrusted. `attr_value_allowed` is what has to look at it.
test "links and images carry raw urls" {
  inspect(
    shape(parse("[t](javascript:alert(1)) ![a](x.png \"ti\")\n").document),
    content=(
      #|(p (a "javascript:alert(1)" "t")" "(img "x.png" "a"))
    ),
  )
}

///|
test "reference links keep the label for the caller to resolve" {
  let r = parse("[t][ref]\n\n[ref]: /u \"ti\"\n")
  inspect(
    shape(r.document),
    content=(
      #|(p (aref ref "t"))
    ),
  )
  inspect(r.definitions.length(), content="1")
  let d = r.definitions[0]
  inspect(
    "\{d.label} -> \{d.url} \{d.title}",
    content=(
      #|ref -> /u ti
    ),
  )
}

///|
test "fenced code keeps its info string and body verbatim" {
  inspect(
    shape(parse("```moonbit meta\nlet x = 1\n```\n").document),
    content=(
      #|(fence "moonbit meta" "let x = 1\n")
    ),
  )
}

///|
/// A block of raw HTML arrives as ONE string, which is what makes it safe to
/// hand to `parse_fragment` on its own.
test "html blocks arrive whole" {
  inspect(
    shape(parse("<div class=\"x\">\n<span>hi</span>\n</div>\n").document),
    content=(
      #|(html "<div class=\"x\">\n<span>hi</span>\n</div>\n")
    ),
  )
}

///|
/// THE load-bearing one, and the reason there is no half-open tag for a node
/// builder to reassemble across siblings: `HtmlInline` is produced from exactly
/// one place upstream — `InlineParser::try_parse_html_comment` — so it is
/// always a complete `<!-- … -->` and always safe to hand to `parse_fragment`
/// alone. A bare inline tag never becomes markup at all.
///
/// What it becomes instead is the surprise. `try_parse_autolink` accepts ANY
/// `<…>` with no whitespace inside, so `<span>` comes back as
/// `Autolink(url="span")` and `</span>` as `Autolink(url="/span")` — neither of
/// which is a link. That is why the builder may not turn an `Autolink` into an
/// `<a>` on sight: it renders one as a link only when the URL carries a real
/// scheme, and as the literal text `<url>` otherwise. Without that rule,
/// `<span>bold</span>` in a comment body would render as two stray links.
///
/// If a future upstream tightens either of these, this test fails and the
/// builder in `vdom/filter/markdown` needs revisiting before the bump lands.
test "inline raw html is only ever a comment; bare tags become bogus autolinks" {
  inspect(
    shape(parse("a <span>b</span> c <!-- note --> d\n").document),
    content=(
      #|(p "a "(auto "span")"b"(auto "/span")" c "(rawinline "<!-- note -->")" d")
    ),
  )
}

///|
/// A tag with an attribute has a space in it, so it fails the autolink scan and
/// survives as text. Between this and the case above, no spelling of an inline
/// tag reaches the DOM as markup.
test "an inline tag with attributes is plain text" {
  inspect(
    shape(parse("x <a href=\"y\">z</a>\n").document),
    content=(
      #|(p "x <a href=\"y\">z"(auto "/a"))
    ),
  )
}

///|
/// A real autolink, which the builder does have to distinguish from the two
/// above — by scheme, since `is_email` alone would not separate `<span>` from
/// `<https://e.com>`.
test "autolinks distinguish mail from web" {
  inspect(
    shape(parse("<https://e.com> <a@e.com>\n").document),
    content=(
      #|(p (auto "https://e.com")" "(auto:mail "a@e.com"))
    ),
  )
}

///|
test "blockquotes nest blocks" {
  inspect(
    shape(parse("> quoted\n>\n> - a\n").document),
    content=(
      #|(quote (p "quoted")(ul (li (p "a"))))
    ),
  )
}

///|
test "thematic breaks and hard breaks" {
  inspect(
    shape(parse("a  \nb\n\n---\n").document),
    content=(
      #|(p "a"(br)"b")(hr)
    ),
  )
}

///|
/// Off by default, so the builder never has to render a `WikiLink`.
test "wikilinks stay off unless asked for" {
  inspect(
    shape(parse("[[target]]").document),
    content=(
      #|(p "[[target]]")
    ),
  )
  inspect(
    shape(parse("[[target]]", wikilinks=true).document),
    content=(
      #|(p (wiki target))
    ),
  )
}

///|
/// The strict path exists and reaches the same AST for ordinary input; it is
/// vendored because `parse(strict=true)` is part of the surface, not because
/// anything here calls it.
test "strict mode parses the same shapes" {
  inspect(
    shape(parse("# T\n\n*a* **b**\n", strict=true).document),
    content=(
      #|(h1 "T")(p (em "a")" "(strong "b"))
    ),
  )
}
