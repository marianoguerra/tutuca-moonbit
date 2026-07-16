// ANode method surface: the match-based port of the BaseNode class
// hierarchy's virtual dispatch (src/anode.js). See spec.mbt for contracts.

///|
fn is_whitespace_str(s : String) -> Bool {
  for c in s {
    if !(c is (' ' | '\n' | '\t' | '\r')) {
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
pub fn ANode::condense_whitespace(
  self : ANode,
  replacement? : String = "",
) -> Unit {
  match self {
    Text(d) | Comment(d) => d.val = replacement
    _ => ()
  }
}

///|
pub fn ANode::is_constant(self : ANode) -> Bool {
  match self {
    Text(_) | Comment(_) => true
    Dom(d) => d.attrs.is_constant() && d.childs.iter().all(c => c.is_constant())
    Fragment(d) => d.childs.iter().all(c => c.is_constant())
    // Delegates to the compiled expansion; never asked before compile
    // (JS would crash on the null node, we answer false defensively).
    MacroCall(d) =>
      match d.node {
        Some(n) => n.is_constant()
        None => false
      }
    _ => false
  }
}

///|
pub fn ANode::set_data_attr(
  self : ANode,
  key : String,
  val : @tutuca.Lit,
) -> Unit {
  match self {
    Dom(d) => d.attrs.set_data_attr(key, val)
    Fragment(d) =>
      for child in d.childs {
        child.set_data_attr(key, val)
      }
    Show(d) | Hide(d) | PushView(d) | Scope(d) => d.node.set_data_attr(key, val)
    Slot(d) => d.node.set_data_attr(key, val)
    Each(d) => d.node.set_data_attr(key, val)
    MacroCall(d) => d.data_attrs[key] = val
    // Text/Comment render to text, RenderText/Render/RenderIt produce no
    // element of their own to carry the attribute: explicit no-ops in JS.
    Text(_) | Comment(_) | RenderText(_) | Render(_) | RenderIt(_) => ()
    // JS RenderOnceNode inherits the warn-only base method; delegating to the
    // wrapped node is safe (the marker wraps a constant Dom/Fragment) and
    // keeps optimized subtrees stampable.
    RenderOnce(d) => d.node.set_data_attr(key, val)
  }
}

///|
pub fn ANode::wrap_node(self : ANode, node : ANode) -> Unit {
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
    _ => println("wrap_node not supported for \{to_repr(self)}")
  }
}

///|
pub fn maybe_fragment(childs : Array[ANode]) -> ANode {
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
  to_repr(MacroCallRepr::{
    name: self.name,
    attrs: self.attrs,
    slots: self.slots,
    node: self.node,
    data_attrs: self.data_attrs,
  })
}
