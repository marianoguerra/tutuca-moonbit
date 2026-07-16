///|
pub(all) enum MemKind {
  Document
  Element
  TextNode
  CommentNode
  FragmentNode
} derive(Eq, Debug)

///|
/// An in-memory DOM node. `attrs` is the serialized attribute map (what
/// assert-equal-DOM compares); `props` is the live IDL property bag (where
/// `value` / `checked` state lives). `dangerous_html` holds markup written
/// via set_inner_html — memdom stores it raw instead of parsing it.
///
/// Never derive Debug/ToJson here: the `parent` back-pointer makes the
/// derived printer recurse forever. Use `to_html` for output.
pub(all) struct MemNode {
  kind : MemKind
  tag : String
  ns : @vdom.Ns?
  attrs : Map[String, String]
  props : Map[String, @vdom.AttrValue]
  childs : Array[MemNode]
  mut parent : MemNode?
  mut data : String
  mut created_is : String? // `is` option passed at creation time
  mut dangerous_html : String?
  mut inner_html_sets : Int // counts real set_inner_html writes (skip test)
}

///|
fn MemNode::make(
  kind : MemKind,
  tag? : String = "",
  ns? : @vdom.Ns? = None,
  data? : String = "",
) -> MemNode {
  {
    kind,
    tag,
    ns,
    attrs: {},
    props: {},
    childs: [],
    parent: None,
    data,
    created_is: None,
    dangerous_html: None,
    inner_html_sets: 0,
  }
}

///|
/// A fresh document node — the value to put in `RenderOpts::document`.
pub fn document() -> MemNode {
  MemNode::make(Document)
}

///|
/// Detach a node from its current parent, if any. DOM insertion primitives
/// move nodes: inserting a node that already has a parent removes it from
/// the old position first.
fn detach(node : MemNode) -> Unit {
  if node.parent is Some(p) {
    for i, c in p.childs {
      if physical_equal(c, node) {
        let _ = p.childs.remove(i)
        break
      }
    }
    node.parent = None
  }
}

///|
/// Insert `node` under `parent` at `index`. Splices document fragments like
/// the real DOM: the fragment's children move in and the fragment empties.
fn insert_at(parent : MemNode, node : MemNode, index : Int) -> Unit {
  if node.kind is FragmentNode {
    let moving = node.childs.copy()
    node.childs.clear()
    let mut at = index
    for c in moving {
      c.parent = Some(parent)
      parent.childs.insert(at, c)
      at += 1
    }
  } else {
    detach(node)
    node.parent = Some(parent)
    parent.childs.insert(index, node)
  }
}

///|
fn index_of(parent : MemNode, node : MemNode) -> Int? {
  for i, c in parent.childs {
    if physical_equal(c, node) {
      return Some(i)
    }
  }
  None
}

///|
pub impl @vdom.DomNode for MemNode with fn create_element(
  _self,
  tag,
  ns,
  is_attr,
) {
  // Explicit HTML-namespace requests behave like plain HTML elements
  // (JS isNamespaced excludes HTML_NS), so normalize at creation.
  let ns = match ns {
    Some(Other(u)) if u == @vdom.html_ns => None
    other => other
  }
  let el = MemNode::make(Element, tag~, ns~)
  el.created_is = is_attr
  el
}

///|
pub impl @vdom.DomNode for MemNode with fn create_text(_self, s) {
  MemNode::make(TextNode, data=s)
}

///|
pub impl @vdom.DomNode for MemNode with fn create_comment(_self, s) {
  MemNode::make(CommentNode, data=s)
}

///|
pub impl @vdom.DomNode for MemNode with fn create_fragment(_self) {
  MemNode::make(FragmentNode)
}

///|
pub impl @vdom.DomNode for MemNode with fn append_child(self, child) {
  insert_at(self, child, self.childs.length())
}

///|
pub impl @vdom.DomNode for MemNode with fn insert_before(
  self,
  new_node,
  ref_node,
) {
  match ref_node {
    None => insert_at(self, new_node, self.childs.length())
    Some(ref_) => {
      // A moved node changes indices when it leaves its old slot, so detach
      // first, then locate the reference.
      if !(new_node.kind is FragmentNode) {
        detach(new_node)
      }
      match index_of(self, ref_) {
        Some(i) => insert_at(self, new_node, i)
        None => insert_at(self, new_node, self.childs.length())
      }
    }
  }
}

///|
pub impl @vdom.DomNode for MemNode with fn remove_child(self, child) {
  match index_of(self, child) {
    Some(i) => {
      let _ = self.childs.remove(i)
      child.parent = None
    }
    None => ()
  }
}

///|
pub impl @vdom.DomNode for MemNode with fn replace_child(
  self,
  new_node,
  old_node,
) {
  match index_of(self, old_node) {
    Some(i) => {
      let _ = self.childs.remove(i)
      old_node.parent = None
      insert_at(self, new_node, i)
    }
    None => ()
  }
}

///|
pub impl @vdom.DomNode for MemNode with fn replace_children(self) {
  for c in self.childs {
    c.parent = None
  }
  self.childs.clear()
  self.dangerous_html = None
}

///|
pub impl @vdom.DomNode for MemNode with fn parent_node(self) {
  self.parent
}

///|
pub impl @vdom.DomNode for MemNode with fn first_child(self) {
  self.childs.get(0)
}

///|
pub impl @vdom.DomNode for MemNode with fn next_sibling(self) {
  match self.parent {
    Some(p) =>
      match index_of(p, self) {
        Some(i) => p.childs.get(i + 1)
        None => None
      }
    None => None
  }
}

///|
pub impl @vdom.DomNode for MemNode with fn child_nodes(self) {
  self.childs.copy()
}

///|
pub impl @vdom.DomNode for MemNode with fn child_node_at(self, i) {
  self.childs.get(i)
}

///|
pub impl @vdom.DomNode for MemNode with fn is_same_node(self, other) {
  physical_equal(self, other)
}

///|
pub impl @vdom.DomNode for MemNode with fn set_attribute(self, name, value) {
  self.attrs[name] = value
}

///|
pub impl @vdom.DomNode for MemNode with fn remove_attribute(self, name) {
  self.attrs.remove(name)
}

///|
pub impl @vdom.DomNode for MemNode with fn set_inner_html(self, html) {
  for c in self.childs {
    c.parent = None
  }
  self.childs.clear()
  self.dangerous_html = Some(html)
  self.inner_html_sets += 1
}

///|
pub impl @vdom.DomNode for MemNode with fn get_inner_html(self) {
  match self.dangerous_html {
    Some(html) => html
    None => {
      let sb = StringBuilder()
      for c in self.childs {
        sb.write_string(c.to_html())
      }
      sb.to_string()
    }
  }
}

///|
pub impl @vdom.DomNode for MemNode with fn set_data(self, s) {
  self.data = s
}

///|
pub impl @vdom.DomNode for MemNode with fn tag_name(self) {
  self.tag
}

///|
pub impl @vdom.DomNode for MemNode with fn namespace_uri(self) {
  self.ns
}

///|
/// Live IDL property state, for assertions real attributes can't cover
/// (`value` / `checked` / `selected` never reflect).
pub fn MemNode::get_property(self : MemNode, name : String) -> @vdom.AttrValue? {
  self.props.get(name)
}

///|
pub fn MemNode::get_attribute(self : MemNode, name : String) -> String? {
  self.attrs.get(name)
}
