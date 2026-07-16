// Read-side DOM access for event-path reconstruction: walk backward
// (prev_sibling — collecting the renderer's `§…§` meta comment chains) and
// read node kind / character data / attributes. Extends DomNode (write-side
// renderer ops) so parent_node / is_same_node are inherited; upward walking
// uses those. Methods mention Self in return position, so consumers take a
// generic bound (fn[N : DomWalk]) — trait objects are not possible here.

///|
pub(open) trait DomWalk: DomNode {
  fn prev_sibling(Self) -> Self?
  fn node_kind(Self) -> Int // DOM nodeType: 1 element, 3 text, 8 comment, 9 document, 11 fragment
  fn char_data(Self) -> String // comment/text character data; "" for elements
  fn attribute(Self, name : String) -> String?
}
