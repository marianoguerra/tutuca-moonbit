// End-tag handling (§13.2.6.4: "any other end tag", the per-mode end-tag
// steps, and the parse errors they surface).
// Split from machine.mbt; same package, purely organizational.

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
