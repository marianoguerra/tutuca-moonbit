///| The surface: a tree of layout nodes holding component instances, plus a
/// data model.
///
/// Nodes are held in a FLAT table keyed by id, with children referred to by
/// id — the same adjacency-list shape A2UI uses, and for the same reasons. A
/// nested tree makes every edit a rewrite of the path down to it; a flat table
/// makes "set this node's padding" touch one entry, which is what lets a patch
/// be small and a diff be legible.

///|
/// What a node IS. Four kinds, and the split is by what each one DOES rather
/// than by how it looks:
///
/// - `Stack` and `Grid` arrange children. Everything about them is in
///   `LayoutProps`.
/// - `Box` holds exactly one child and gives it surroundings — padding, a
///   border, a background. Separate from the containers because "wrap this in
///   a card" should not require choosing a direction.
/// - `Slot` is where a component instance lives. It is a leaf, and it is the
///   only kind that refers to anything outside the surface.
pub(all) enum NodeKind {
  Stack
  Grid
  Box
  Slot
} derive(Eq, Debug)

///|
pub fn NodeKind::to_string(self : NodeKind) -> String {
  match self {
    Stack => "stack"
    Grid => "grid"
    Box => "box"
    Slot => "slot"
  }
}

///|
pub fn NodeKind::parse(s : String) -> NodeKind? {
  match s {
    "stack" => Some(Stack)
    "grid" => Some(Grid)
    "box" => Some(Box)
    "slot" => Some(Slot)
    _ => None
  }
}

///|
pub fn NodeKind::is_container(self : NodeKind) -> Bool {
  self is (Stack | Grid)
}

///|
/// Everything a container decides about its children, and everything a child
/// decides about its own cell.
///
/// One record for both because a node is usually both — a Grid inside a Stack
/// arranges its own children and occupies a cell of its parent — and two
/// records would mean every node carried an empty one.
pub(all) struct LayoutProps {
  // --- as a container ---
  direction : Direction
  wrap : Bool
  justify : Justify
  align : Align
  gap : Int
  padding : Int
  /// Grid only. Empty is a grid with no declared tracks, which is legal and
  /// means "one column, auto rows".
  columns : Array[Track]
  rows : Array[Track]
  // --- as a cell of its parent ---
  /// 1 is "one cell", which is the default and the overwhelmingly common case.
  col_span : Int
  row_span : Int
  /// 0 = "wherever the flow puts it". Explicit placement is 1-based, matching
  /// CSS's own line numbering rather than introducing a second convention.
  col_start : Int
  row_start : Int
  /// Box only.
  background : String
  border : String
} derive(Eq, Debug)

///|
/// The props a node gets when nothing says otherwise: a column that stretches
/// its children, no gap, no padding, one cell, auto-placed.
pub fn LayoutProps::default() -> LayoutProps {
  {
    direction: Column,
    wrap: false,
    justify: Start,
    align: AStretch,
    gap: 0,
    padding: 0,
    columns: [],
    rows: [],
    col_span: 1,
    row_span: 1,
    col_start: 0,
    row_start: 0,
    background: "",
    border: "",
  }
}

///|
/// One node of the surface.
pub(all) struct Node {
  id : String
  kind : NodeKind
  props : LayoutProps
  /// Child ids, in order. Empty for a Slot; at most one for a Box.
  children : Array[String]
  /// Slot only: what component fills it, and with what. `None` is an empty
  /// slot — a placeholder a person has added and not yet filled, which is a
  /// real state the editor needs to be able to represent.
  bound : Binding?
} derive(Eq, Debug)

///|
/// What fills a Slot. A REFERENCE, resolved by the host when it builds the
/// instance — the surface never holds a live instance, which is what keeps it
/// serializable and what lets the same document be replayed into a different
/// session.
pub(all) struct Binding {
  module_ : String
  name : String
  /// A named init fixture, or "" for the bare constructor.
  init : String
  /// Constructor arguments, already validated against the component's schema
  /// by whoever produced them.
  args : Map[String, @tutuca.Value]
} derive(Eq, Debug)

///|
/// A surface: the node table, the root, and the data model.
pub(all) struct Surface {
  id : String
  root : String
  nodes : Map[String, Node]
  /// Shared state the components on this surface read and write, addressed by
  /// JSON Pointer — the same binding model A2UI uses and the same one AG-UI's
  /// state deltas patch. Held as a `Value` because that is what everything
  /// else here speaks.
  data : @tutuca.Value
  /// Monotonic, for generating node ids. Kept on the surface rather than
  /// globally so two surfaces do not interleave their ids, and so a serialized
  /// surface resumes without colliding with what it already contains.
  next_id : Int
} derive(Eq, Debug)

///|
/// An empty surface: one Stack as its root, nothing in it.
pub fn Surface::new(id : String) -> Surface {
  let root : Node = {
    id: "n0",
    kind: Stack,
    props: LayoutProps::default(),
    children: [],
    bound: None,
  }
  { id, root: "n0", nodes: { "n0": root }, data: Map(Map([])), next_id: 1 }
}

///|
pub fn Surface::node(self : Surface, id : String) -> Node? {
  self.nodes.get(id)
}

///|
/// The parent of `id`, or None for the root (and for an orphan, which the
/// invariant below says cannot exist).
pub fn Surface::parent_of(self : Surface, id : String) -> String? {
  for pid, n in self.nodes {
    if n.children.contains(id) {
      return Some(pid)
    }
  }
  None
}

///|
/// Node ids in document order, depth first — what a serializer, a renderer and
/// a "show me the tree" listing all want.
pub fn Surface::walk(self : Surface) -> Array[String] {
  let out : Array[String] = []
  fn visit(id : String, depth : Int) -> Unit {
    // The depth guard is not paranoia about our own ops — those maintain the
    // tree invariant — but about a surface DESERIALIZED from a document a
    // caller supplied, which can say anything.
    if depth > 64 {
      return
    }
    guard self.nodes.get(id) is Some(n) else { return }
    out.push(id)
    for c in n.children {
      visit(c, depth + 1)
    }
  }

  visit(self.root, 0)
  out
}

///|
/// Every component the surface binds, in document order. What the host needs
/// in order to build the instances, and what a "what does this page use"
/// question is asking.
pub fn Surface::bindings(self : Surface) -> Array[(String, Binding)] {
  let out : Array[(String, Binding)] = []
  for id in self.walk() {
    guard self.nodes.get(id) is Some(n) else { continue }
    if n.bound is Some(b) {
      out.push((id, b))
    }
  }
  out
}

///|
/// The inline style a node renders with, as its CONTAINER.
///
/// Host-generated, which is the point: a surface never carries a CSS string a
/// guest wrote, so none of this passes through the guest-style validator. It
/// follows the `FlexStyle` precedent in the universal demo — a computed style
/// string rather than a generated class, which keeps the class set bounded no
/// matter how many surfaces exist.
pub fn Node::container_style(self : Node) -> String {
  let p = self.props
  let parts : Array[String] = []
  match self.kind {
    Stack => {
      parts.push("display:flex")
      parts.push("flex-direction:\{p.direction.to_css()}")
      parts.push("flex-wrap:\{if p.wrap { "wrap" } else { "nowrap" }}")
      parts.push("justify-content:\{p.justify.to_css()}")
      parts.push("align-items:\{p.align.to_css()}")
    }
    Grid => {
      parts.push("display:grid")
      parts.push("grid-template-columns:\{tracks_to_css(p.columns)}")
      if !p.rows.is_empty() {
        parts.push("grid-template-rows:\{tracks_to_css(p.rows)}")
      }
      parts.push("justify-items:\{p.justify.to_css()}")
      parts.push("align-items:\{p.align.to_css()}")
    }
    Box => {
      if p.background != "" {
        parts.push("background:\{p.background}")
      }
      if p.border != "" {
        parts.push("border:\{p.border}")
      }
    }
    Slot => ()
  }
  if p.gap > 0 && self.kind.is_container() {
    parts.push("gap:\{p.gap}px")
  }
  if p.padding > 0 {
    parts.push("padding:\{p.padding}px")
  }
  parts.join(";")
}

///|
/// The inline style a node renders with, as a CELL of its parent. Empty when
/// it occupies one auto-placed cell, which is almost always.
pub fn Node::cell_style(self : Node) -> String {
  let p = self.props
  let parts : Array[String] = []
  if p.col_start > 0 {
    parts.push("grid-column-start:\{p.col_start}")
  }
  if p.col_span > 1 {
    parts.push("grid-column-end:span \{p.col_span}")
  }
  if p.row_start > 0 {
    parts.push("grid-row-start:\{p.row_start}")
  }
  if p.row_span > 1 {
    parts.push("grid-row-end:span \{p.row_span}")
  }
  parts.join(";")
}
