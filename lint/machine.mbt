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
