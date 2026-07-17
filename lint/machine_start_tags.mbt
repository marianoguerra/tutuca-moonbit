// Start-tag dispatch and the per-insertion-mode start-tag steps
// (§13.2.6.4 "the rules for parsing tokens in HTML content" — inBody,
// inTable, inCaption, inColumnGroup, inTableBody, inRow, inCell, inSelect,
// inSelectInTable, inTemplate, plus foreign-content dispatch).
// Split from machine.mbt; same package, purely organizational.

///|
fn Machine::handle_start_tag(
  self : Machine,
  name : String,
  raw : String,
  attrs : Array[RawAttr],
  self_closing : Bool,
  start : Int,
) -> Unit {
  self.current_attrs = attrs
  let ns = self.current_namespace()

  // Case-violation checks happen on every open tag.
  if ns == NsHtml {
    if raw != name {
      self.report(
        HtmlTagNameHasUppercase,
        Error,
        start,
        [("raw", raw), ("lowercased", name)],
        suggestion=Rewrite(from="<" + raw + ">", to="<" + name + ">"),
      )
    }
  } else if ns == NsSvg {
    if raw != raw.to_lower() && !standard_svg_camel_elements.contains(raw) {
      self.report(
        HtmlSvgTagWillLowercase,
        Error,
        start,
        [("raw", raw), ("lowercased", name)],
        suggestion=Rewrite(from="<" + raw + ">", to="<" + name + ">"),
      )
    }
  }

  // Foreign-content attribute case correction applies to the element's
  // TARGET namespace (a root <svg>/<math> tag adjusts its own attrs).
  let target_ns : FNs = if ns != NsHtml {
    ns
  } else if name == "svg" {
    NsSvg
  } else if name == "math" {
    NsMath
  } else {
    NsHtml
  }
  if target_ns == NsSvg {
    for a in attrs {
      if svg_attr_lowercase_to_camel.get(a.name) is Some(canonical) &&
        a.raw_name != canonical {
        self.report(
          HtmlSvgAttrWillLowercase,
          Error,
          a.name_start,
          [("raw", a.raw_name), ("canonical", canonical)],
          suggestion=Rewrite(from=a.raw_name, to=canonical),
        )
      }
    }
  } else if target_ns == NsMath {
    for a in attrs {
      if mathml_attr_lowercase_to_camel.get(a.name) is Some(canonical) &&
        a.raw_name != canonical {
        self.report(
          HtmlMathmlAttrWillLowercase,
          Error,
          a.name_start,
          [("raw", a.raw_name), ("canonical", canonical)],
          suggestion=Rewrite(from=a.raw_name, to=canonical),
        )
      }
    }
  }

  // Phantom templating tags: case checks above applied, parent rules don't.
  if self.is_transparent_tag(name) {
    return
  }

  // Foreign content has its own algorithm; integration points re-enter HTML.
  let in_foreign = ns != NsHtml &&
    !(self.current_node() is Some(top) && is_integration_point(top))
  if in_foreign {
    if !self.should_breakout_from_foreign(name) {
      self.start_tag_in_foreign(name, raw, self_closing, start)
      return
    }
    self.report(HtmlTagNotAllowedInParent, Warn, start, [
      ("tag", raw),
      ("parent", self.current_name()),
      ("mode", self.insertion_mode.to_name()),
      ("action", "foreign-breakout"),
    ])
    while self.open_elements.length() > 0 && self.current_namespace() != NsHtml {
      self.open_elements.pop() |> ignore
    }
  }
  self.dispatch_start_tag(name, raw, self_closing, start)
}

///|
fn Machine::should_breakout_from_foreign(self : Machine, name : String) -> Bool {
  if foreign_breakout_tags.contains(name) {
    return true
  }
  if name == "font" {
    // Only <font> with color/face/size escapes foreign content.
    return self.has_attr("color") ||
      self.has_attr("face") ||
      self.has_attr("size")
  }
  false
}

///|
fn Machine::start_tag_in_foreign(
  self : Machine,
  name : String,
  raw : String,
  self_closing : Bool,
  start : Int,
) -> Unit {
  let ns : FNs = if name == "svg" {
    NsSvg
  } else if name == "math" {
    NsMath
  } else {
    self.current_namespace()
  }
  // Integration points re-enter HTML (mglyph/malignmark excluded per spec).
  if self.current_node() is Some(top) &&
    is_integration_point(top) &&
    name != "mglyph" &&
    name != "malignmark" {
    self.dispatch_start_tag(name, raw, self_closing, start)
    return
  }
  if self_closing {
    return // don't push
  }
  let frame = self.mk_frame(name, ns)
  // annotation-xml is an HTML integration point when encoding is text/html
  // or application/xhtml+xml; capture at push time.
  if ns == NsMath && name == "annotation-xml" {
    let enc = self.get_attr("encoding").unwrap_or("").to_lower()
    if enc == "text/html" || enc == "application/xhtml+xml" {
      frame.html_integration = true
    }
  }
  self.open_elements.push(frame)
}

///|
fn Machine::dispatch_start_tag(
  self : Machine,
  name : String,
  raw : String,
  self_closing : Bool,
  start : Int,
) -> Unit {
  match self.insertion_mode {
    InTemplate => self.start_in_template(name, raw, self_closing, start)
    InBody => self.start_in_body(name, raw, self_closing, start)
    InTable => self.start_in_table(name, raw, self_closing, start)
    InCaption => self.start_in_caption(name, raw, self_closing, start)
    InColumnGroup => self.start_in_column_group(name, raw, self_closing, start)
    InTableBody => self.start_in_table_body(name, raw, self_closing, start)
    InRow => self.start_in_row(name, raw, self_closing, start)
    InCell => self.start_in_cell(name, raw, self_closing, start)
    InSelect => self.start_in_select(name, raw, self_closing, start)
    InSelectInTable =>
      self.start_in_select_in_table(name, raw, self_closing, start)
  }
}

///|
fn Machine::tag_not_allowed(
  self : Machine,
  level : LintLevel,
  start : Int,
  tag : String,
  parent : String,
  action : String,
) -> Unit {
  self.report(HtmlTagNotAllowedInParent, level, start, [
    ("tag", tag),
    ("parent", parent),
    ("mode", self.insertion_mode.to_name()),
    ("action", action),
  ])
}

// ─── inBody ─────────────────────────────────────────────────────────────────

///|
fn Machine::start_in_body(
  self : Machine,
  name : String,
  raw : String,
  self_closing : Bool,
  start : Int,
) -> Unit {
  if name is ("html" | "head" | "body" | "frame" | "frameset") {
    // Rare in fragments; ignore but flag as unexpected. (No parent key: the
    // JS info object had none here either.)
    self.report(HtmlTagNotAllowedInParent, Warn, start, [
      ("tag", raw),
      ("mode", self.insertion_mode.to_name()),
      ("action", "ignored"),
    ])
    return
  }
  if name
    is ("address"
    | "article"
    | "aside"
    | "blockquote"
    | "center"
    | "details"
    | "dialog"
    | "dir"
    | "div"
    | "dl"
    | "fieldset"
    | "figcaption"
    | "figure"
    | "footer"
    | "header"
    | "hgroup"
    | "main"
    | "menu"
    | "nav"
    | "ol"
    | "p"
    | "search"
    | "section"
    | "summary"
    | "ul") {
    if self.has_in_button_scope("p") {
      self.implicitly_close("p")
    }
    self.push_el(raw, NsHtml)
    return
  }
  if name is ("h1" | "h2" | "h3" | "h4" | "h5" | "h6") {
    if self.has_in_button_scope("p") {
      self.implicitly_close("p")
    }
    if self.current_node() is Some(top) &&
      top.name is ("h1" | "h2" | "h3" | "h4" | "h5" | "h6") {
      self.tag_not_allowed(Error, start, raw, top.name, "auto-close-implicit")
      self.open_elements.pop() |> ignore
    }
    self.push_el(raw, NsHtml)
    return
  }
  if name is ("pre" | "listing") {
    if self.has_in_button_scope("p") {
      self.implicitly_close("p")
    }
    self.push_el(raw, NsHtml)
    return
  }
  if name == "form" {
    // A still-open <form> (outside a template) means this one is dropped.
    if self.open_elements_has("form") && !self.open_elements_has("template") {
      self.report(
        HtmlDuplicateForm,
        Error,
        start,
        [("tag", raw), ("mode", self.insertion_mode.to_name())],
        suggestion=Remove(what="the inner <form>"),
      )
      return
    }
    if self.has_in_button_scope("p") {
      self.implicitly_close("p")
    }
    self.push_el(raw, NsHtml)
    return
  }
  if name == "li" {
    for i = self.open_elements.length() - 1; i >= 0; i = i - 1 {
      let f = self.open_elements[i]
      if f.ns != NsHtml {
        break
      }
      if f.name == "li" {
        self.generate_implied_end_tags(except="li")
        self.pop_until_name("li")
        break
      }
      if special_elements.contains(f.name) &&
        !(f.name is ("address" | "div" | "p")) {
        break
      }
    }
    if self.has_in_button_scope("p") {
      self.implicitly_close("p")
    }
    self.push_el(raw, NsHtml)
    return
  }
  if name is ("dd" | "dt") {
    for i = self.open_elements.length() - 1; i >= 0; i = i - 1 {
      let f = self.open_elements[i]
      if f.ns != NsHtml {
        break
      }
      if f.name is ("dd" | "dt") {
        self.generate_implied_end_tags(except=f.name)
        self.pop_until_name(f.name)
        break
      }
      if special_elements.contains(f.name) &&
        !(f.name is ("address" | "div" | "p")) {
        break
      }
    }
    if self.has_in_button_scope("p") {
      self.implicitly_close("p")
    }
    self.push_el(raw, NsHtml)
    return
  }
  if name == "plaintext" {
    if self.has_in_button_scope("p") {
      self.implicitly_close("p")
    }
    self.push_el(raw, NsHtml)
    return
  }
  if name == "button" {
    if self.has_in_default_scope("button") {
      self.tag_not_allowed(Error, start, raw, "button", "auto-close-implicit")
      self.generate_implied_end_tags()
      self.pop_until_name("button")
    }
    self.push_el(raw, NsHtml)
    return
  }
  if name is ("a" | "nobr") {
    // Only the ACTIVE FORMATTING LIST triggers adoption-agency for <a>/<nobr>.
    if self.active_formatting_has(name) {
      self.report(HtmlNestedInteractive, Warn, start, [
        ("tag", raw),
        ("mode", self.insertion_mode.to_name()),
      ])
      self.run_adoption_agency(name)
    }
    self.push_el(raw, NsHtml)
    self.active_formatting.push(self.current_node())
    return
  }
  if formatting_elements.contains(name) {
    self.push_el(raw, NsHtml)
    self.active_formatting.push(self.current_node())
    return
  }
  if name == "table" {
    if self.has_in_button_scope("p") {
      self.implicitly_close("p")
    }
    self.push_el(raw, NsHtml)
    self.insertion_mode = InTable
    return
  }
  if name
    is ("area"
    | "br"
    | "embed"
    | "img"
    | "keygen"
    | "wbr"
    | "input"
    | "param"
    | "source"
    | "track"
    | "hr"
    | "meta"
    | "link"
    | "col"
    | "base") {
    // Void elements — don't push.
    return
  }
  if name == "select" {
    if self.has_in_button_scope("p") {
      self.implicitly_close("p")
    }
    self.push_el(raw, NsHtml)
    // §"in body": reached from a table mode via fall-through (the mode is
    // still the table one here), the select parses "in select in table" —
    // the JS linter shortcuts this to inSelect with an apologetic comment;
    // this port follows the spec.
    self.insertion_mode = if self.insertion_mode
      is (InTable | InCaption | InTableBody | InRow | InCell) {
      InSelectInTable
    } else {
      InSelect
    }
    return
  }
  if name is ("option" | "optgroup") {
    if self.current_name() == "option" {
      self.open_elements.pop() |> ignore
    }
    self.push_el(raw, NsHtml)
    return
  }
  if name is ("textarea" | "title") || raw_text_elements.contains(name) {
    self.push_el(raw, NsHtml)
    return
  }
  if name is ("math" | "svg") {
    self.push_el(raw, if name == "svg" { NsSvg } else { NsMath })
    return
  }
  if name
    is ("caption"
    | "col"
    | "colgroup"
    | "frame"
    | "tbody"
    | "td"
    | "tfoot"
    | "th"
    | "thead"
    | "tr") {
    self.tag_not_allowed(Error, start, raw, self.current_name(), "ignored")
    return
  }
  // Generic catch-all: any other start tag — push (unless self-closing).
  if self_closing {
    return
  }
  self.push_el(raw, NsHtml)
}

///|
fn Machine::start_in_template(
  self : Machine,
  name : String,
  raw : String,
  self_closing : Bool,
  start : Int,
) -> Unit {
  let next : Mode = if name
    is ("caption" | "colgroup" | "tbody" | "tfoot" | "thead") {
    InTable
  } else if name == "col" {
    InColumnGroup
  } else if name == "tr" {
    InTableBody
  } else if name is ("td" | "th") {
    InRow
  } else {
    self.pop_template_mode()
    self.push_template_mode(InBody)
    self.insertion_mode = InBody
    self.start_in_body(name, raw, self_closing, start)
    return
  }
  self.pop_template_mode()
  self.push_template_mode(next)
  self.insertion_mode = next
  self.dispatch_start_tag(name, raw, self_closing, start)
}

///|
fn Machine::start_in_table(
  self : Machine,
  name : String,
  raw : String,
  self_closing : Bool,
  start : Int,
) -> Unit {
  if name == "caption" {
    self.clear_stack_back_to_table()
    self.active_formatting.push(None) // marker
    self.push_el(raw, NsHtml)
    self.insertion_mode = InCaption
    return
  }
  if name == "colgroup" {
    self.clear_stack_back_to_table()
    self.push_el(raw, NsHtml)
    self.insertion_mode = InColumnGroup
    return
  }
  if name == "col" {
    self.clear_stack_back_to_table()
    self.push_el("colgroup", NsHtml)
    self.insertion_mode = InColumnGroup
    self.dispatch_start_tag(name, raw, self_closing, start)
    return
  }
  if name is ("tbody" | "thead" | "tfoot") {
    self.clear_stack_back_to_table()
    self.push_el(raw, NsHtml)
    self.insertion_mode = InTableBody
    return
  }
  if name is ("td" | "th" | "tr") {
    self.clear_stack_back_to_table()
    self.push_el("tbody", NsHtml)
    self.insertion_mode = InTableBody
    self.dispatch_start_tag(name, raw, self_closing, start)
    return
  }
  if name == "table" {
    self.tag_not_allowed(Error, start, raw, "table", "auto-close-implicit")
    if self.has_in_table_scope("table") {
      self.pop_until_name("table")
      self.reset_insertion_mode_appropriately()
      self.dispatch_start_tag(name, raw, self_closing, start)
    }
    return
  }
  if name is ("style" | "script" | "template") {
    self.start_in_body(name, raw, self_closing, start)
    return
  }
  if name == "input" {
    // <input type=hidden> is the one input allowed inside a table without
    // foster-parenting.
    let type_ = self.get_attr("type").unwrap_or("").to_lower()
    if type_ == "hidden" {
      return
    }
    self.tag_not_allowed(Warn, start, raw, "table", "foster-parent")
    return
  }
  if name == "form" {
    self.tag_not_allowed(Error, start, raw, "table", "ignored")
    return
  }
  // Foster-parent anything else; keep parsing the TOKENS per "in body".
  self.tag_not_allowed(Error, start, raw, self.current_name(), "foster-parent")
  self.start_in_body(name, raw, self_closing, start)
}

///|
fn Machine::start_in_caption(
  self : Machine,
  name : String,
  raw : String,
  self_closing : Bool,
  start : Int,
) -> Unit {
  if caption_cell_breakout_tags.contains(name) {
    if self.has_in_table_scope("caption") {
      self.generate_implied_end_tags()
      self.pop_until_name("caption")
      self.clear_active_formatting_to_marker()
      self.insertion_mode = InTable
      self.dispatch_start_tag(name, raw, self_closing, start)
    }
    return
  }
  self.start_in_body(name, raw, self_closing, start)
}

///|
fn Machine::start_in_column_group(
  self : Machine,
  name : String,
  raw : String,
  self_closing : Bool,
  start : Int,
) -> Unit {
  if name == "col" {
    return // void
  }
  if name == "template" {
    self.start_in_body(name, raw, self_closing, start)
    return
  }
  // Anything else: implicit </colgroup>, reprocess in inTable.
  if self.current_name() == "colgroup" {
    self.open_elements.pop() |> ignore
    self.insertion_mode = InTable
    self.dispatch_start_tag(name, raw, self_closing, start)
    return
  }
  self.tag_not_allowed(Error, start, raw, "colgroup", "ignored")
}

// ─── inTableBody ────────────────────────────────────────────────────────────

///|
fn Machine::start_in_table_body(
  self : Machine,
  name : String,
  raw : String,
  self_closing : Bool,
  start : Int,
) -> Unit {
  if name == "tr" {
    self.clear_stack_back_to_table_body()
    self.push_el(raw, NsHtml)
    self.insertion_mode = InRow
    return
  }
  if table_body_cell_tags.contains(name) {
    self.tag_not_allowed(
      Warn,
      start,
      raw,
      self.current_name(),
      "auto-close-implicit",
    )
    self.clear_stack_back_to_table_body()
    self.push_el("tr", NsHtml)
    self.insertion_mode = InRow
    self.dispatch_start_tag(name, raw, self_closing, start)
    return
  }
  if name is ("caption" | "col" | "colgroup" | "tbody" | "tfoot" | "thead") {
    if self.has_in_table_scope("tbody") ||
      self.has_in_table_scope("thead") ||
      self.has_in_table_scope("tfoot") {
      self.clear_stack_back_to_table_body()
      self.open_elements.pop() |> ignore
      self.insertion_mode = InTable
      self.dispatch_start_tag(name, raw, self_closing, start)
    }
    return
  }
  self.start_in_table(name, raw, self_closing, start)
}

///|
fn Machine::start_in_row(
  self : Machine,
  name : String,
  raw : String,
  self_closing : Bool,
  start : Int,
) -> Unit {
  if table_body_cell_tags.contains(name) {
    self.clear_stack_back_to_table_row()
    self.push_el(raw, NsHtml)
    self.insertion_mode = InCell
    self.active_formatting.push(None)
    return
  }
  if name
    is ("caption" | "col" | "colgroup" | "tbody" | "tfoot" | "thead" | "tr") {
    if self.has_in_table_scope("tr") {
      self.clear_stack_back_to_table_row()
      self.open_elements.pop() |> ignore
      self.insertion_mode = InTableBody
      self.dispatch_start_tag(name, raw, self_closing, start)
    }
    return
  }
  self.start_in_table(name, raw, self_closing, start)
}

///|
fn Machine::start_in_cell(
  self : Machine,
  name : String,
  raw : String,
  self_closing : Bool,
  start : Int,
) -> Unit {
  if caption_cell_breakout_tags.contains(name) {
    if self.has_in_table_scope("td") || self.has_in_table_scope("th") {
      self.close_cell()
      self.dispatch_start_tag(name, raw, self_closing, start)
    }
    return
  }
  self.start_in_body(name, raw, self_closing, start)
}

///|
fn Machine::start_in_select(
  self : Machine,
  name : String,
  raw : String,
  self_closing : Bool,
  start : Int,
) -> Unit {
  if name == "option" {
    if self.current_name() == "option" {
      self.open_elements.pop() |> ignore
    }
    self.push_el(raw, NsHtml)
    return
  }
  if name == "optgroup" {
    if self.current_name() == "option" {
      self.open_elements.pop() |> ignore
    }
    if self.current_name() == "optgroup" {
      self.open_elements.pop() |> ignore
    }
    self.push_el(raw, NsHtml)
    return
  }
  if name == "hr" {
    return
  }
  if select_breakout_tags.contains(name) {
    self.tag_not_allowed(Error, start, raw, "select", "auto-close-implicit")
    if self.has_in_select_scope("select") {
      self.pop_until_name("select")
      self.reset_insertion_mode_appropriately()
    }
    // input/keygen are dropped after closing select; textarea reprocesses;
    // select itself just closes.
    if name == "select" {
      return
    }
    self.dispatch_start_tag(name, raw, self_closing, start)
    return
  }
  if name is ("script" | "template") {
    self.start_in_body(name, raw, self_closing, start)
    return
  }
  self.tag_not_allowed(Error, start, raw, "select", "ignored")
}

// ─── inSelectInTable ────────────────────────────────────────────────────────

///|
fn Machine::start_in_select_in_table(
  self : Machine,
  name : String,
  raw : String,
  self_closing : Bool,
  start : Int,
) -> Unit {
  if name
    is ("caption" | "table" | "tbody" | "tfoot" | "thead" | "tr" | "td" | "th") {
    self.tag_not_allowed(Error, start, raw, "select", "auto-close-implicit")
    self.pop_until_name("select")
    self.reset_insertion_mode_appropriately()
    self.dispatch_start_tag(name, raw, self_closing, start)
    return
  }
  self.start_in_select(name, raw, self_closing, start)
}
