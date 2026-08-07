// The markdown AST, walked straight into sanitized vdom nodes.

///|
/// Everything the walk needs that does not change as it descends.
priv struct Build {
  sanitizer : @sanitize.Sanitizer
  /// Link reference definitions, by label, for `RefLink` / `RefImage`.
  defs : Map[String, @md.LinkDefinition]
  /// The element the markdown is being built INTO, for the report only.
  host_tag : String
  /// `(tag, attr, value, reason)` — the shape of `@filter.Dropped`.
  on_drop : (String, String, String, String) -> Unit
  /// Footnote definitions, hoisted out of the flow and emitted at the end in
  /// the order they were defined.
  footnotes : Array[(String, Array[@md.Block])]
}

///|
/// Parse a markdown payload and sanitize it into vdom nodes.
///
/// Parsed with `strict=false` (upstream's fast single-pass parser) and
/// `wikilinks=false`, so `Inline::WikiLink` is never produced.
pub fn build(
  source : String,
  sanitizer : @sanitize.Sanitizer,
  host_tag : String,
  on_drop : (String, String, String, String) -> Unit,
) -> Array[@vdom.Vdom] {
  let parsed = @md.parse(source)
  let defs : Map[String, @md.LinkDefinition] = Map([])
  for d in parsed.definitions {
    // First definition wins, which is what CommonMark says.
    let key = fold_label(d.label)
    if !defs.contains(key) {
      defs[key] = d
    }
  }
  let b = Build::{ sanitizer, defs, host_tag, on_drop, footnotes: [] }
  let out = b.blocks(parsed.document.children)
  for node in b.footnote_section() {
    out.push(node)
  }
  out
}

// ---------------------------------------------------------------------------
// The one gate

///|
/// Build one element, or don't. **Every element this package emits goes through
/// here** — there is no `@vdom.h` call anywhere else in the walk — so no arm of
/// the match can forget to ask the sanitizer.
///
/// `ns` is always HTML: markdown has no syntax that produces an SVG or MathML
/// element. Raw HTML inside the document can, but that goes to
/// `@markup.html_nodes`, which does its own namespace handling.
fn Build::emit(
  self : Build,
  tag : String,
  attrs : Map[String, @vdom.AttrValue],
  childs : Array[@vdom.Vdom],
) -> Array[@vdom.Vdom] {
  match self.sanitizer.element_verdict(tag, None) {
    Drop => {
      (self.on_drop)(
        self.host_tag,
        MD_ATTR,
        "<\{tag}>",
        "element is not allowed here",
      )
      []
    }
    // The spec's `replaceWithChildrenElements`: the element goes, its content
    // stays.
    ReplaceWithChildren => childs
    Keep => {
      let kept : Map[String, @vdom.AttrValue] = Map([])
      for name, value in attrs {
        let text = value.to_attr_string()
        if !self.sanitizer.attribute_allowed(tag, None, name) {
          (self.on_drop)(
            self.host_tag,
            name,
            text,
            "attribute is not allowed on <\{tag}> here",
          )
          continue
        }
        // The value half, which the config has no opinion about. These values
        // come out of the markdown source — `[t](javascript:…)` is one URL
        // typed by whoever wrote the document — so this is not belt and braces.
        if !@filter.attr_value_allowed(name, text) {
          (self.on_drop)(
            self.host_tag,
            name,
            text,
            "URL scheme is not one a view may navigate to",
          )
          continue
        }
        kept[name] = value
      }
      [@vdom.h(tag, attrs=kept, childs~)]
    }
  }
}

///|
/// An element with no attributes, which is most of them.
fn Build::wrap(
  self : Build,
  tag : String,
  childs : Array[@vdom.Vdom],
) -> Array[@vdom.Vdom] {
  self.emit(tag, Map([]), childs)
}

// ---------------------------------------------------------------------------
// Blocks

///|
fn Build::blocks(self : Build, bs : Array[@md.Block]) -> Array[@vdom.Vdom] {
  let out : Array[@vdom.Vdom] = []
  for b in bs {
    for node in self.block(b) {
      out.push(node)
    }
  }
  out
}

///|
fn Build::block(self : Build, b : @md.Block) -> Array[@vdom.Vdom] {
  match b {
    ThematicBreak(..) => self.wrap("hr", [])
    Heading(level~, children~, ..) => {
      let n = if level < 1 { 1 } else if level > 6 { 6 } else { level }
      self.wrap("h\{n}", self.inlines(children))
    }
    Paragraph(children~, ..) => self.wrap("p", self.inlines(children))
    FencedCode(info~, code~, ..) => {
      let attrs : Map[String, @vdom.AttrValue] = Map([])
      let lang = first_word(info)
      if lang != "" {
        attrs["class"] = Str("language-\{lang}")
      }
      self.wrap("pre", self.emit("code", attrs, [Text(code)]))
    }
    IndentedCode(code~, ..) => self.wrap("pre", self.wrap("code", [Text(code)]))
    Blockquote(children~, ..) => self.wrap("blockquote", self.blocks(children))
    BulletList(tight~, items~, ..) =>
      self.wrap("ul", self.list_items(items, tight))
    OrderedList(start~, tight~, items~, ..) => {
      let attrs : Map[String, @vdom.AttrValue] = Map([])
      if start != 1 {
        attrs["start"] = @vdom.AttrValue::int(start)
      }
      self.emit("ol", attrs, self.list_items(items, tight))
    }
    // The one place raw HTML survives at block level. Handed to the SAME
    // builder `@dangerouslysetinnerhtml` uses, so the two cannot disagree.
    //
    // A run of HTML that does not close itself (a lone `<div>` line) is
    // auto-closed inside its own fragment here, so markdown that followed it
    // becomes a SIBLING rather than a child. That is a real divergence from
    // CommonMark, and it is the price of building nodes instead of
    // concatenating strings — there is no partial element to leave open across
    // a boundary when what you are producing is a tree.
    HtmlBlock(html~, ..) =>
      @markup.html_nodes(self.sanitizer, html, self.host_tag, self.on_drop)
    BlankLines(..) => []
    // Hoisted; `footnote_section` emits them once, at the end.
    FootnoteDefinition(label~, children~, ..) => {
      self.footnotes.push((label, children))
      []
    }
    Table(header~, alignments~, rows~, ..) => {
      let head = self.wrap(
        "thead",
        self.wrap("tr", self.cells(header, alignments, "th")),
      )
      let body : Array[@vdom.Vdom] = []
      for row in rows {
        for node in self.wrap("tr", self.cells(row, alignments, "td")) {
          body.push(node)
        }
      }
      let parts = head
      for node in self.wrap("tbody", body) {
        parts.push(node)
      }
      self.wrap("table", parts)
    }
  }
}

///|
fn Build::cells(
  self : Build,
  cells : Array[@md.TableCell],
  alignments : Array[@md.TableAlign],
  tag : String,
) -> Array[@vdom.Vdom] {
  let out : Array[@vdom.Vdom] = []
  for i, c in cells {
    let attrs : Map[String, @vdom.AttrValue] = Map([])
    // `style` is the only attribute this package synthesizes, and a config with
    // a global `remove_attributes` naming it will drop the alignment. That is
    // the config doing its job, not a bug here.
    if i < alignments.length() {
      match alignments[i] {
        Left => attrs["style"] = Str("text-align:left")
        Center => attrs["style"] = Str("text-align:center")
        Right => attrs["style"] = Str("text-align:right")
        None => ()
      }
    }
    for node in self.emit(tag, attrs, self.inlines(c.children)) {
      out.push(node)
    }
  }
  out
}

///|
fn Build::list_items(
  self : Build,
  items : Array[@md.ListItem],
  tight : Bool,
) -> Array[@vdom.Vdom] {
  let out : Array[@vdom.Vdom] = []
  for li in items {
    let content : Array[@vdom.Vdom] = []
    // GFM task list. `disabled` because the checkbox describes the document's
    // state, not the app's — nothing is listening to it.
    match li.checked {
      Some(checked) => {
        let attrs : Map[String, @vdom.AttrValue] = Map([])
        attrs["type"] = Str("checkbox")
        attrs["disabled"] = Bool(true)
        if checked {
          attrs["checked"] = Bool(true)
        }
        for node in self.emit("input", attrs, []) {
          content.push(node)
        }
      }
      None => ()
    }
    for b in li.children {
      // A tight list drops the `<p>` around each item's content, which is what
      // makes `- a` render as `<li>a</li>` rather than `<li><p>a</p></li>`.
      match b {
        Paragraph(children~, ..) if tight =>
          for node in self.inlines(children) {
            content.push(node)
          }
        _ =>
          for node in self.block(b) {
            content.push(node)
          }
      }
    }
    for node in self.wrap("li", content) {
      out.push(node)
    }
  }
  out
}

///|
fn Build::footnote_section(self : Build) -> Array[@vdom.Vdom] {
  if self.footnotes.length() == 0 {
    return []
  }
  let items : Array[@vdom.Vdom] = []
  for pair in self.footnotes {
    let (label, children) = pair
    let attrs : Map[String, @vdom.AttrValue] = Map([])
    // The id a `FootnoteReference` links to. It is derived from the document's
    // own text, so it can collide with an id on the host's page — the same
    // thing every markdown renderer does, and worth knowing before using this
    // on a page with hand-written anchors.
    attrs["id"] = Str("fn-\{label}")
    for node in self.emit("li", attrs, self.blocks(children)) {
      items.push(node)
    }
  }
  let attrs : Map[String, @vdom.AttrValue] = Map([])
  attrs["class"] = Str("footnotes")
  self.emit("section", attrs, self.wrap("ol", items))
}

// ---------------------------------------------------------------------------
// Inlines

///|
fn Build::inlines(self : Build, xs : Array[@md.Inline]) -> Array[@vdom.Vdom] {
  let out : Array[@vdom.Vdom] = []
  for x in xs {
    for node in self.inline(x) {
      out.push(node)
    }
  }
  out
}

///|
fn Build::inline(self : Build, i : @md.Inline) -> Array[@vdom.Vdom] {
  match i {
    // Text reaches the DOM through `createTextNode`, so it is never escaped and
    // never can be: there is no markup context for it to break out of.
    Text(content~, ..) => [Text(content)]
    SoftBreak(..) => [Text("\n")]
    HardBreak(..) => self.wrap("br", [])
    Emphasis(children~, ..) => self.wrap("em", self.inlines(children))
    Strong(children~, ..) => self.wrap("strong", self.inlines(children))
    Strikethrough(children~, ..) => self.wrap("del", self.inlines(children))
    Code(content~, ..) => self.wrap("code", [Text(content)])
    Link(children~, url~, title~, ..) =>
      self.anchor(url, title, self.inlines(children))
    RefLink(children~, label~, ..) =>
      match self.defs.get(fold_label(label)) {
        Some(d) => self.anchor(d.url, d.title, self.inlines(children))
        // An unresolved reference is not a link. CommonMark renders the source
        // text verbatim; we render the link TEXT unlinked, which is the same
        // words without the brackets and is what a reader wants from a comment
        // body whose author mistyped a label.
        None => self.inlines(children)
      }
    // The rule this package would be wrong without. Upstream's
    // `try_parse_autolink` accepts any `<…>` with no whitespace in it, so
    // `<span>` arrives here as `Autolink(url="span")` and `</span>` as
    // `Autolink(url="/span")` — see `markdown/parse_test.mbt`. Turning those
    // into `<a>` would fill a document with stray links pointing at relative
    // paths. A real autolink has a scheme; anything else is the literal text
    // the author typed, brackets included.
    Autolink(url~, is_email~, ..) =>
      if is_email {
        self.anchor("mailto:\{url}", "", [Text(url)])
      } else if @filter.scheme_of(url) is Some(_) {
        self.anchor(url, "", [Text(url)])
      } else {
        [Text("<\{url}>")]
      }
    Image(alt~, url~, title~, ..) => self.image(url, alt, title)
    RefImage(alt~, label~, ..) =>
      match self.defs.get(fold_label(label)) {
        Some(d) => self.image(d.url, alt, d.title)
        None => [Text(alt)]
      }
    // Always a complete `<!-- … -->` — it is the only thing upstream's inline
    // parser produces this variant for. Through the shared builder, so
    // `Sanitizer.comments` decides, exactly as it does for raw markup.
    HtmlInline(html~, ..) =>
      @markup.html_nodes(self.sanitizer, html, self.host_tag, self.on_drop)
    FootnoteReference(label~, ..) =>
      self.wrap("sup", self.anchor("#fn-\{label}", "", [Text(label)]))
    // Unreachable: `build` parses with `wikilinks=false`. Rendered as its text
    // rather than left to a panic, so a future caller that turns the flag on
    // gets something legible instead of a hole.
    WikiLink(target~, label~, ..) =>
      [Text(if label == "" { target } else { label })]
  }
}

///|
fn Build::anchor(
  self : Build,
  url : String,
  title : String,
  childs : Array[@vdom.Vdom],
) -> Array[@vdom.Vdom] {
  let attrs : Map[String, @vdom.AttrValue] = Map([])
  attrs["href"] = Str(url)
  if title != "" {
    attrs["title"] = Str(title)
  }
  // A denied `href` drops the ATTRIBUTE, not the element (that is
  // `attr_value_allowed`'s rule, applied in `emit`), so the link text survives
  // as an inert `<a>`. The words stay; only the navigation goes.
  self.emit("a", attrs, childs)
}

///|
fn Build::image(
  self : Build,
  url : String,
  alt : String,
  title : String,
) -> Array[@vdom.Vdom] {
  let attrs : Map[String, @vdom.AttrValue] = Map([])
  attrs["src"] = Str(url)
  attrs["alt"] = Str(alt)
  if title != "" {
    attrs["title"] = Str(title)
  }
  self.emit("img", attrs, [])
}

// ---------------------------------------------------------------------------

///|
/// Link labels match case-insensitively in CommonMark.
fn fold_label(s : String) -> String {
  s.to_lower()
}

///|
/// The language of a fence's info string: everything up to the first space.
/// `” ```json:file.json ”` keeps the whole first token, which is what upstream's
/// own info-string convention expects.
fn first_word(s : String) -> String {
  let out = StringBuilder::new()
  for c in s {
    if c == ' ' || c == '\t' {
      break
    }
    out.write_char(c)
  }
  out.to_string()
}
