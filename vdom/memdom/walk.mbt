// Read-side walk over the in-memory DOM (the test substrate for event-path
// reconstruction).

///|
pub impl @vdom.DomWalk for MemNode with fn prev_sibling(self) {
  match self.parent {
    Some(p) =>
      match index_of(p, self) {
        Some(i) => if i > 0 { p.childs.get(i - 1) } else { None }
        None => None
      }
    None => None
  }
}

///|
pub impl @vdom.DomWalk for MemNode with fn node_kind(self) {
  match self.kind {
    Element => 1
    TextNode => 3
    CommentNode => 8
    Document => 9
    FragmentNode => 11
  }
}

///|
pub impl @vdom.DomWalk for MemNode with fn char_data(self) {
  self.data
}

///|
pub impl @vdom.DomWalk for MemNode with fn attribute(self, name) {
  self.attrs.get(name)
}
