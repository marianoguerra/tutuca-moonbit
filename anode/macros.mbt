// Macro expansion (src/anode.js MacroNode.compile / Macro).

///|
pub fn Macro::expand(self : Macro, px : ParseContext) -> ANode {
  // Expansion always yields a node (empty raw views become the standard
  // "Empty View" comment), so a None from parse is normalized here.
  ANode::parse(self.raw_view, px).unwrap_or(
    Comment({ val: "Empty View in ANode.parse" }),
  )
}

///|
fn macro_compile(d : MacroData, scope : &MacroScope) -> Unit raise MacroError {
  if d.px.is_inside_macro(d.name) {
    raise RecursiveMacro(d.name)
  }
  match scope.lookup_macro(d.name) {
    None => d.node = Some(Comment({ val: "bad macro: \{d.name}" }))
    Some(m) => {
      let vars : Map[String, String] = Map([])
      for k, v in m.defaults {
        vars[k] = v
      }
      for k, v in d.attrs {
        vars[k] = v
      }
      let node = m.expand(d.px.enter_macro(d.name, vars, d.slots))
      for key, val in d.data_attrs {
        node.set_data_attr(key, val)
      }
      d.node = Some(node)
    }
  }
}
