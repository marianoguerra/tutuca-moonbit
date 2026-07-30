// ANode method surface: the match-based port of the BaseNode class
// hierarchy's virtual dispatch (src/anode.js). See spec.mbt for contracts.

///|
/// Template whitespace (the JS source's explicit ` \t\n\r` set — narrower
/// than the value language's JS-\s set in core and the WHATWG tokenizer set
/// in lint, both deliberate).
fn is_tpl_space(c : Char) -> Bool {
  c is (' ' | '\t' | '\n' | '\r')
}

///|
fn is_whitespace_str(s : String) -> Bool {
  for c in s {
    if !is_tpl_space(c) {
      return false
    }
  }
  true
}

///|
pub fn ANode::is_whitespace(self : ANode) -> Bool {
  match self {
    // Comment inherits TextNode's implementation in JS.
    Text(d) | Comment(d) => is_whitespace_str(d.val)
    _ => false
  }
}

///|
pub fn ANode::has_newline(self : ANode) -> Bool {
  match self {
    Text(d) | Comment(d) => d.val.iter().any(c => c is ('\n' | '\r'))
    _ => false
  }
}

///|
fn ANode::for_each_child(self : ANode, visit : (ANode) -> Unit) -> Unit {
  match self {
    Dom(d) =>
      for child in d.childs {
        visit(child)
      }
    Fragment(d) =>
      for child in d.childs {
        visit(child)
      }
    Show(d) | Hide(d) | PushView(d) | Scope(d) => visit(d.node)
    Slot(d) => visit(d.node)
    Each(d) => visit(d.node)
    MacroCall(d) => if d.node is Some(node) { visit(node) }
    Text(_) | Comment(_) | RenderText(_) | Render(_) | RenderIt(_) => ()
  }
}

///|
fn ANode::condense_whitespace(self : ANode, replacement? : String = "") -> Unit {
  match self {
    Text(d) | Comment(d) => d.val = replacement
    _ => ()
  }
}

///|
fn ANode::set_data_attr(self : ANode, key : String, val : @tutuca.Lit) -> Unit {
  match self {
    Dom(d) => d.attrs.set_data_attr(key, val)
    MacroCall(d) => d.data_attrs[key] = val
    // Text/Comment render to text, RenderText/Render/RenderIt produce no
    // element of their own to carry the attribute. Containers and wrappers
    // pass it to their structural children.
    _ => self.for_each_child(child => child.set_data_attr(key, val))
  }
}

///|
fn ANode::wrap_node(self : ANode, node : ANode) -> Unit {
  match self {
    Show(d) | Hide(d) | PushView(d) => d.node = node
    Scope(d) => {
      d.node = node
      // Emitted so event-path reconstruction can replay this scope's binds.
      if d.node_id is Some(id) {
        node.set_data_attr("data-nid", LNum(id.to_double()))
      }
    }
    Slot(d) => d.node = node
    Each(d) => d.node = node
    _ => @tutuca.warn("wrap_node not supported for \{Repr(self)}")
  }
}

///|
fn maybe_fragment(childs : Array[ANode]) -> ANode {
  if childs.length() == 1 {
    childs[0]
  } else {
    Fragment({ childs, })
  }
}

///|
/// Placeholder used while constructing wrapper nodes before wrap_node runs
/// (JS constructs wrappers with node=null and assigns right after).
fn empty_node() -> ANode {
  Fragment({ childs: [] })
}

///|
/// Mirror of MacroData without the parse-context back-reference (which would
/// cycle: px.nodes can contain this very MacroCall).
priv struct MacroCallRepr {
  name : String
  attrs : Map[String, String]
  slots : Map[String, ANode]
  node : ANode?
  data_attrs : Map[String, @tutuca.Lit]
} derive(Debug)

///|
pub impl Debug for MacroData with fn to_repr(self) {
  Repr(MacroCallRepr::{
    name: self.name,
    attrs: self.attrs,
    slots: self.slots,
    node: self.node,
    data_attrs: self.data_attrs,
  })
}
