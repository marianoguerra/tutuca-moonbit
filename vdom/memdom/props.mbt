///|
/// IDL properties whose value reflects to an attribute (className → class,
/// htmlFor → for, everything else same-named). Curated from the names the
/// ported test-suites and generators exercise; grow as tests demand.
fn is_reflected_prop(name : String) -> Bool {
  name
  is ("id"
  | "className"
  | "htmlFor"
  | "title"
  | "lang"
  | "dir"
  | "slot"
  | "style"
  | "type"
  | "name"
  | "src"
  | "alt"
  | "placeholder"
  | "min"
  | "max"
  | "step"
  | "hidden"
  // NEVER_ASSIGN members that are still real IDL properties — the core
  // routes them to set_attribute, but `has_property` should stay truthful.
  | "width"
  | "height"
  | "href"
  | "list"
  | "form"
  | "tabIndex"
  | "download"
  | "rowSpan"
  | "colSpan"
  | "role"
  | "popover")
}

///|
/// Live element state that exists as an IDL property but never reflects to
/// an attribute.
fn is_state_prop(name : String) -> Bool {
  name
  is ("value"
  | "checked"
  | "selected"
  | "multiple"
  | "disabled"
  | "readOnly"
  | "required"
  | "indeterminate")
}

///|
/// The JS `name in node` check. Deliberately excludes the all-lowercase
/// spellings whose IDL property is camelCase (`readonly`, `tabindex`,
/// `contenteditable`, `maxlength`, …) and `data-*` / `aria-*`, which fail
/// the `in` test in a real browser and must fall through to set_attribute.
/// Tag-independent on purpose: memdom aims for morph ≡ fresh-render
/// consistency, not per-element IDL accuracy.
pub impl @vdom.DomNode for MemNode with fn has_property(self, name) {
  // Once assigned, a property exists (`el.items = x` makes `"items" in el`
  // true in a real browser too) — this is what lets a later morph clear a
  // structured custom-element property through the uses_prop path.
  is_reflected_prop(name) || is_state_prop(name) || self.props.contains(name)
}

///|
/// Store the property; reflected names also write their attribute (that is
/// what keeps attribute-level DOM comparison in agreement between a morphed
/// tree and a fresh render, mirroring reflected-IDL behavior). memdom
/// deviation from a real browser: reflected *boolean* IDL props (`hidden`,
/// `disabled`) serialize as "true"/"false" instead of presence/absence —
/// consistent on both render paths, which is what the tests compare.
/// `throwingProp` is a test-only sentinel for the JS `catch {}` fallback.
pub impl @vdom.DomNode for MemNode with fn set_property(self, name, value) {
  if name == "throwingProp" {
    return false
  }
  if self.tag == "SELECT" && name == "value" {
    select_set_value(self, value)
    return true
  }
  self.props[name] = value
  if is_reflected_prop(name) {
    self.attrs[reflected_attr_name(name)] = value.to_attr_string()
  }
  true
}

///|
/// Minimal <select> semantics: assigning `value` selects the first child
/// option whose value matches; with no match the select's value becomes ""
/// and nothing is selected. This is what makes the renderer's
/// value-after-children ordering and morph-time value re-application
/// observable without a browser. No `selected` attribute is ever written.
fn select_set_value(sel : MemNode, value : @vdom.AttrValue) -> Unit {
  let target = value.to_attr_string()
  let mut found = false
  for c in sel.childs {
    if c.tag == "OPTION" {
      let ov = match c.props.get("value") {
        Some(v) => v.to_attr_string()
        None => ""
      }
      let matches = !found && ov == target
      c.props["selected"] = Bool(matches)
      if matches {
        found = true
      }
    }
  }
  sel.props["value"] = Str(if found { target } else { "" })
}

///|
fn reflected_attr_name(name : String) -> String {
  match name {
    "className" => "class"
    "htmlFor" => "for"
    _ => name
  }
}
