// Machine stack/scope bookkeeping (§13.2.4.2 "the stack of open elements",
// §13.2.6.4.7 implied end tags, the active-formatting list, template
// insertion modes, and "reset the insertion mode appropriately").
// Split from machine.mbt; same package, purely organizational.

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
fn Machine::clear_active_formatting_to_marker(self : Machine) -> Unit {
  while self.active_formatting.length() > 0 {
    if self.active_formatting.pop() is Some(None) {
      return
    }
  }
}

// ─── inColumnGroup ──────────────────────────────────────────────────────────

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
