// Insertion-mode prediction machine (tools/core/htmllinter.js LinterCtx).
// Implements WHATWG §13.2.6 tree construction at the fidelity needed to
// predict where the real parser would silently rearrange the DOM: no DOM is
// built, only the algorithm's bookkeeping (open-elements stack,
// active-formatting list, insertion mode, template modes, form pointer via
// the stack, framesetOk). A finding is emitted wherever the spec says "parse
// error" or describes a silent reparenting.

///|
priv enum FNs {
  NsHtml
  NsSvg
  NsMath
} derive(Eq)

///|
priv enum Mode {
  InBody
  InTable
  InCaption
  InColumnGroup
  InTableBody
  InRow
  InCell
  InSelect
  InSelectInTable
  InTemplate
}

///|
fn Mode::to_name(self : Mode) -> String {
  match self {
    InBody => "inBody"
    InTable => "inTable"
    InCaption => "inCaption"
    InColumnGroup => "inColumnGroup"
    InTableBody => "inTableBody"
    InRow => "inRow"
    InCell => "inCell"
    InSelect => "inSelect"
    InSelectInTable => "inSelectInTable"
    InTemplate => "inTemplate"
  }
}

///|
/// Open-elements stack entry. `name` is lowercase for all matching; `id`
/// gives reference identity between the stack and the active-formatting
/// list.
priv struct Frame {
  id : Int
  name : String
  ns : FNs
  mut html_integration : Bool
}

///|
/// Raw-scanned attribute (case-preserved name + offset; values from source).
priv struct RawAttr {
  name : String
  raw_name : String
  name_start : Int
  value : String
  has_value : Bool
}

///|
priv struct Machine {
  chars : Array[Char]
  line_starts : Array[Int]
  out : Array[Finding]
  open_elements : Array[Frame]
  mut insertion_mode : Mode
  template_insertion_modes : Array[Mode]
  active_formatting : Array[Frame?] // None = marker
  transparent_tag_prefixes : Array[String]
  mut current_attrs : Array[RawAttr]
  mut frame_counter : Int
}

///|
fn compute_line_starts(chars : Array[Char]) -> Array[Int] {
  let arr = [0]
  for i in 0..<chars.length() {
    if chars[i] == '\n' {
      arr.push(i + 1)
    }
  }
  arr
}

///|
fn Machine::new(
  chars : Array[Char],
  fragment_context : String,
  transparent_tag_prefixes : Array[String],
) -> Machine {
  let m = Machine::{
    chars,
    line_starts: compute_line_starts(chars),
    out: [],
    open_elements: [],
    insertion_mode: InBody,
    template_insertion_modes: [],
    active_formatting: [],
    transparent_tag_prefixes: transparent_tag_prefixes.map(p => p.to_lower()),
    current_attrs: [],
    frame_counter: 0,
  }
  // §13.2.4.4 fragment context: seed the stack + pick the initial mode.
  fn seed(name : String, ns : FNs) {
    m.open_elements.push(m.mk_frame(name, ns))
  }
  match fragment_context {
    "tr" => {
      seed("table", NsHtml)
      seed("tbody", NsHtml)
      m.insertion_mode = InRow
    }
    "tbody" | "thead" | "tfoot" => {
      seed("table", NsHtml)
      m.insertion_mode = InTableBody
    }
    "td" | "th" => {
      seed("table", NsHtml)
      seed("tbody", NsHtml)
      seed("tr", NsHtml)
      m.insertion_mode = InCell
    }
    "caption" => {
      seed("table", NsHtml)
      m.insertion_mode = InCaption
    }
    "colgroup" => {
      seed("table", NsHtml)
      m.insertion_mode = InColumnGroup
    }
    "svg" => seed("svg", NsSvg)
    "math" => seed("math", NsMath)
    "select" => {
      seed("select", NsHtml)
      m.insertion_mode = InSelect
    }
    "table" => m.insertion_mode = InTable
    "template" => {
      m.insertion_mode = InTemplate
      m.template_insertion_modes.push(InTemplate)
    }
    // "body" / "div" / anything else: inBody.
    _ => ()
  }
  m
}

///|
fn Machine::mk_frame(self : Machine, name : String, ns : FNs) -> Frame {
  self.frame_counter = self.frame_counter + 1
  { id: self.frame_counter, name, ns, html_integration: false }
}

///|
fn Machine::report(
  self : Machine,
  code : LintCode,
  level : LintLevel,
  offset : Int,
  info : Array[(String, String)],
  suggestion? : Suggestion,
) -> Unit {
  // Binary search the line table (JS offsetToLineCol).
  let ls = self.line_starts
  let mut lo = 0
  let mut hi = ls.length() - 1
  while lo < hi {
    let mid = (lo + hi + 1) / 2
    if ls[mid] <= offset {
      lo = mid
    } else {
      hi = mid - 1
    }
  }
  self.out.push({
    code,
    level,
    info,
    location: Some({ line: lo + 1, column: offset - ls[lo] + 1, offset }),
    suggestion,
  })
}

///|
fn Machine::current_node(self : Machine) -> Frame? {
  self.open_elements.get(self.open_elements.length() - 1)
}

///|
fn Machine::current_namespace(self : Machine) -> FNs {
  match self.current_node() {
    Some(f) => f.ns
    None => NsHtml
  }
}

///|
fn Machine::current_name(self : Machine) -> String {
  match self.current_node() {
    Some(f) => f.name
    None => "(root)"
  }
}

///|
fn Machine::push_el(self : Machine, raw : String, ns : FNs) -> Unit {
  self.open_elements.push(self.mk_frame(raw.to_lower(), ns))
}

///|
fn truncate_frames(xs : Array[Frame], len : Int) -> Unit {
  while xs.length() > len {
    xs.pop() |> ignore
  }
}

///|
/// "have an element in scope" (§13.2.4.2): integration points and MathML
/// annotation-xml bound the walk; other foreign frames are walked past.
fn Machine::has_in_scope(
  self : Machine,
  target : String,
  scope_set : Set[String],
) -> Bool {
  for i = self.open_elements.length() - 1; i >= 0; i = i - 1 {
    let f = self.open_elements[i]
    if f.name == target && f.ns == NsHtml {
      return true
    }
    if f.ns == NsHtml {
      if scope_set.contains(f.name) {
        return false
      }
    } else if is_scope_boundary(f) {
      return false
    }
  }
  false
}

///|
/// Foreign frames that bound scope walks: every MathML text integration
/// point and annotation-xml (regardless of encoding), plus SVG HTML
/// integration points.
fn is_scope_boundary(frame : Frame) -> Bool {
  match frame.ns {
    NsMath =>
      mathml_text_integration_point_names.contains(frame.name) ||
      frame.name == "annotation-xml"
    NsSvg => svg_html_integration_point_names.contains(frame.name)
    NsHtml => false
  }
}

///|
/// Frames that re-enter HTML token dispatch — annotation-xml only when its
/// encoding is text/html or application/xhtml+xml.
fn is_integration_point(frame : Frame) -> Bool {
  match frame.ns {
    NsMath =>
      mathml_text_integration_point_names.contains(frame.name) ||
      (frame.name == "annotation-xml" && frame.html_integration)
    NsSvg => svg_html_integration_point_names.contains(frame.name)
    NsHtml => false
  }
}

///|
fn Machine::has_in_default_scope(self : Machine, target : String) -> Bool {
  self.has_in_scope(target, scope_default)
}

///|
fn Machine::has_in_button_scope(self : Machine, target : String) -> Bool {
  self.has_in_scope(target, scope_button)
}

///|
fn Machine::has_in_table_scope(self : Machine, target : String) -> Bool {
  self.has_in_scope(target, scope_table)
}

///|
fn Machine::has_in_select_scope(self : Machine, target : String) -> Bool {
  // Inverted: only optgroup/option are NOT boundaries.
  for i = self.open_elements.length() - 1; i >= 0; i = i - 1 {
    let f = self.open_elements[i]
    if f.ns != NsHtml {
      return false
    }
    if f.name == target {
      return true
    }
    if f.name != "optgroup" && f.name != "option" {
      return false
    }
  }
  false
}

///|
fn Machine::pop_until_name(self : Machine, name : String) -> Unit {
  while self.open_elements.length() > 0 {
    match self.open_elements.pop() {
      Some(f) => if f.name == name { return }
      None => return
    }
  }
}

///|
fn Machine::generate_implied_end_tags(self : Machine, except? : String) -> Unit {
  while self.open_elements.length() > 0 {
    guard self.current_node() is Some(top) else { return }
    if top.ns != NsHtml {
      return
    }
    if !implied_end_tags.contains(top.name) {
      return
    }
    if except is Some(e) && top.name == e {
      return
    }
    self.open_elements.pop() |> ignore
  }
}

///|
fn Machine::is_transparent_tag(self : Machine, name : String) -> Bool {
  for prefix in self.transparent_tag_prefixes {
    if name == prefix || name.has_prefix(prefix + ":") {
      return true
    }
  }
  false
}

///|
fn Machine::get_attr(self : Machine, name : String) -> String? {
  for a in self.current_attrs {
    if a.name == name && a.has_value {
      return Some(a.value)
    }
  }
  None
}

///|
fn Machine::has_attr(self : Machine, name : String) -> Bool {
  self.current_attrs.iter().any(a => a.name == name)
}

// ─── Start tag entry ────────────────────────────────────────────────────────

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
fn Machine::open_elements_has(self : Machine, name : String) -> Bool {
  for i = self.open_elements.length() - 1; i >= 0; i = i - 1 {
    let f = self.open_elements[i]
    if f.ns == NsHtml && f.name == name {
      return true
    }
  }
  false
}

///|
fn Machine::active_formatting_has(self : Machine, name : String) -> Bool {
  for i = self.active_formatting.length() - 1; i >= 0; i = i - 1 {
    match self.active_formatting[i] {
      None => return false // marker
      Some(e) => if e.name == name { return true }
    }
  }
  false
}

///|
/// Simplified adoption agency: pop the open-elements entry, KEEP the
/// active-formatting entry (mirrors the real algorithm's bookkeeping shape,
/// so a subsequent same-name tag still triggers the lint).
fn Machine::run_adoption_agency(self : Machine, name : String) -> Unit {
  for i = self.active_formatting.length() - 1; i >= 0; i = i - 1 {
    match self.active_formatting[i] {
      None => return
      Some(e) =>
        if e.name == name {
          for j in 0..<self.open_elements.length() {
            if self.open_elements[j].id == e.id {
              self.open_elements.remove(j) |> ignore
              return
            }
          }
          return
        }
    }
  }
}

///|
fn Machine::implicitly_close(self : Machine, name : String) -> Unit {
  self.pop_until_name(name)
}

// ─── inTemplate ─────────────────────────────────────────────────────────────

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
fn Machine::pop_template_mode(self : Machine) -> Unit {
  if self.template_insertion_modes.length() > 0 {
    self.template_insertion_modes.pop() |> ignore
  }
}

///|
fn Machine::push_template_mode(self : Machine, mode : Mode) -> Unit {
  self.template_insertion_modes.push(mode)
}

// ─── inTable ────────────────────────────────────────────────────────────────

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
fn Machine::clear_stack_back_to_table(self : Machine) -> Unit {
  while self.open_elements.length() > 0 {
    guard self.current_node() is Some(top) else { return }
    if top.name is ("table" | "template") {
      return
    }
    self.open_elements.pop() |> ignore
  }
}

// ─── inCaption ──────────────────────────────────────────────────────────────

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
fn Machine::clear_active_formatting_to_marker(self : Machine) -> Unit {
  while self.active_formatting.length() > 0 {
    if self.active_formatting.pop() is Some(None) {
      return
    }
  }
}

// ─── inColumnGroup ──────────────────────────────────────────────────────────

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
fn Machine::clear_stack_back_to_table_body(self : Machine) -> Unit {
  while self.open_elements.length() > 0 {
    guard self.current_node() is Some(top) else { return }
    if top.name is ("tbody" | "thead" | "tfoot" | "template" | "table") {
      return
    }
    self.open_elements.pop() |> ignore
  }
}

// ─── inRow ──────────────────────────────────────────────────────────────────

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
fn Machine::clear_stack_back_to_table_row(self : Machine) -> Unit {
  while self.open_elements.length() > 0 {
    guard self.current_node() is Some(top) else { return }
    if top.name is ("tr" | "template" | "table") {
      return
    }
    self.open_elements.pop() |> ignore
  }
}

// ─── inCell ─────────────────────────────────────────────────────────────────

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
fn Machine::close_cell(self : Machine) -> Unit {
  self.generate_implied_end_tags()
  while self.open_elements.length() > 0 {
    match self.open_elements.pop() {
      Some(popped) => if popped.name is ("td" | "th") { break }
      None => break
    }
  }
  self.clear_active_formatting_to_marker()
  self.insertion_mode = InRow
}

// ─── inSelect ───────────────────────────────────────────────────────────────

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

///|
fn Machine::reset_insertion_mode_appropriately(self : Machine) -> Unit {
  for i = self.open_elements.length() - 1; i >= 0; i = i - 1 {
    let f = self.open_elements[i]
    if f.ns != NsHtml {
      continue
    }
    let last = i == 0
    match f.name {
      "select" => {
        self.insertion_mode = InSelect
        return
      }
      "td" | "th" =>
        if !last {
          self.insertion_mode = InCell
          return
        }
      "tr" => {
        self.insertion_mode = InRow
        return
      }
      "tbody" | "thead" | "tfoot" => {
        self.insertion_mode = InTableBody
        return
      }
      "caption" => {
        self.insertion_mode = InCaption
        return
      }
      "colgroup" => {
        self.insertion_mode = InColumnGroup
        return
      }
      "table" => {
        self.insertion_mode = InTable
        return
      }
      "template" => {
        self.insertion_mode = self.template_insertion_modes
          .get(self.template_insertion_modes.length() - 1)
          .unwrap_or(InBody)
        return
      }
      _ => ()
    }
  }
  self.insertion_mode = InBody
}

// ─── End tag dispatch ───────────────────────────────────────────────────────

///|
fn Machine::handle_end_tag(self : Machine, name : String, start : Int) -> Unit {
  if self.is_transparent_tag(name) {
    return
  }
  let ns = self.current_namespace()

  // Foreign-content end tag: walk down, case-insensitive match against
  // foreign frames; the first HTML frame after a non-matching foreign top
  // falls through to HTML dispatch without popping anything.
  if ns != NsHtml {
    let mut stack_idx = self.open_elements.length() - 1
    let mut first = true
    while stack_idx > 0 {
      let f = self.open_elements[stack_idx]
      if !first && f.ns == NsHtml {
        break // fall through to HTML dispatch
      }
      if f.ns != NsHtml && f.name.to_lower() == name {
        truncate_frames(self.open_elements, stack_idx)
        return
      }
      if first {
        self.report(HtmlUnexpectedEndTag, Warn, start, [
          ("tag", name),
          ("mode", self.insertion_mode.to_name()),
        ])
        first = false
      }
      stack_idx = stack_idx - 1
    }
    // Fall through: HTML mode dispatch.
  }
  if void_elements.contains(name) {
    self.report(
      HtmlVoidElementHasCloseTag,
      Warn,
      start,
      [("tag", name), ("mode", self.insertion_mode.to_name())],
      suggestion=Remove(what="the </" + name + ">"),
    )
    return
  }

  // Misnested formatting elements trigger adoption-agency detection.
  if formatting_elements.contains(name) {
    if self.current_node() is Some(top) && top.ns == NsHtml && top.name == name {
      // Well-nested.
      self.open_elements.pop() |> ignore
      self.remove_from_active_formatting_by_id(top.id)
      return
    }
    if self.active_formatting_has(name) || self.open_elements_has(name) {
      self.report(HtmlMisnestedFormatting, Warn, start, [
        ("tag", name),
        ("mode", self.insertion_mode.to_name()),
      ])
      self.run_adoption_agency(name)
      return
    }
    self.report(HtmlUnexpectedEndTag, Warn, start, [
      ("tag", name),
      ("mode", self.insertion_mode.to_name()),
    ])
    return
  }

  // "any other end tag": walk the stack; a special element before the match
  // means parse error + ignore. Frames implicitly closed on the way out are
  // flagged unless implied-closable (or table-structural closed by a
  // table-structural end tag).
  let end_is_table_structural = table_scope_tags.contains(name)
  for i = self.open_elements.length() - 1; i >= 0; i = i - 1 {
    let f = self.open_elements[i]
    if f.ns == NsHtml && f.name == name {
      for j = self.open_elements.length() - 1; j > i; j = j - 1 {
        let popped = self.open_elements[j]
        if popped.ns == NsHtml &&
          popped.name != name &&
          !implied_end_tags.contains(popped.name) &&
          !(end_is_table_structural && table_scope_tags.contains(popped.name)) {
          self.report(HtmlUnclosedBeforeEnd, Warn, start, [
            ("tag", name),
            ("unclosed", popped.name),
            ("mode", self.insertion_mode.to_name()),
          ])
          break
        }
      }
      truncate_frames(self.open_elements, i)
      if table_scope_tags.contains(name) || name is ("select" | "template") {
        self.reset_insertion_mode_appropriately()
      }
      return
    }
    if f.ns == NsHtml &&
      special_elements.contains(f.name) &&
      !implied_end_tags.contains(f.name) &&
      !(end_is_table_structural && table_scope_tags.contains(f.name)) {
      self.report(HtmlUnexpectedEndTag, Warn, start, [
        ("tag", name),
        ("mode", self.insertion_mode.to_name()),
      ])
      return
    }
  }
  // No match anywhere in the stack — silently ignore (browsers do).
}

///|
fn Machine::remove_from_active_formatting_by_id(
  self : Machine,
  id : Int,
) -> Unit {
  for i in 0..<self.active_formatting.length() {
    if self.active_formatting[i] is Some(e) && e.id == id {
      self.active_formatting.remove(i) |> ignore
      return
    }
  }
}

// ─── Text dispatch ──────────────────────────────────────────────────────────

///|
/// Tokenizer-level text entry: foreign non-integration frames allow any text.
fn Machine::on_text(self : Machine, start : Int, end : Int) -> Unit {
  if start >= end {
    return
  }
  if self.current_node() is Some(top) &&
    top.ns != NsHtml &&
    !is_integration_point(top) {
    return
  }
  self.handle_text(start, end)
}

///|
fn Machine::slice(self : Machine, start : Int, end : Int) -> String {
  let buf = StringBuilder::new()
  for i in start..<end {
    buf.write_char(self.chars[i])
  }
  buf.to_string()
}

///|
fn Machine::has_non_ws(self : Machine, start : Int, end : Int) -> Bool {
  for i in start..<end {
    if !is_space(self.chars[i]) {
      return true
    }
  }
  false
}

///|
fn Machine::handle_text(self : Machine, start : Int, end : Int) -> Unit {
  if self.insertion_mode is (InTable | InTableBody | InRow) {
    if self.has_non_ws(start, end) {
      let s = self.slice(start, end)
      let snippet = if s.length() > 40 { s[0:40].to_owned() + "…" } else { s }
      self.report(HtmlTextNotAllowedInParent, Error, start, [
        ("mode", self.insertion_mode.to_name()),
        ("snippet", snippet),
      ])
    }
    return
  }
  if self.insertion_mode is InColumnGroup {
    if self.has_non_ws(start, end) && self.current_name() == "colgroup" {
      // Implicit </colgroup> + reprocess as inTable.
      self.open_elements.pop() |> ignore
      self.insertion_mode = InTable
      self.handle_text(start, end)
    }
    return
  }
  // inSelect/inSelectInTable: text is allowed (just doesn't render).
  // Other modes: text is fine.
}
