///|
pub let html_ns : String = "http://www.w3.org/1999/xhtml"

///|
pub let svg_uri : String = "http://www.w3.org/2000/svg"

///|
pub let math_uri : String = "http://www.w3.org/1998/Math/MathML"

///|
/// Element namespace. `None` at use sites means HTML (the null namespace).
/// URI strings only appear at the DOM boundary via `to_uri` / `from_uri`.
pub(all) enum Ns {
  Svg
  MathMl
  Other(String)
} derive(Eq, Debug)

///|
pub fn Ns::to_uri(self : Ns) -> String {
  match self {
    Svg => svg_uri
    MathMl => math_uri
    Other(uri) => uri
  }
}

///|
/// Classify a raw namespace URI. Total: unknown URIs become `Other`.
pub fn Ns::from_uri(uri : String) -> Ns {
  if uri == svg_uri {
    Svg
  } else if uri == math_uri {
    MathMl
  } else {
    Other(uri)
  }
}

///|
/// Namespace of a live DOM node as reported by `namespaceURI`. Real DOM gives
/// HTML elements the XHTML namespace (not null), and vdom treats both as
/// "not namespaced" — so null and the HTML namespace both map to `None`.
pub fn ns_from_dom_uri(uri : String?) -> Ns? {
  match uri {
    None => None
    Some(u) => if u == html_ns { None } else { Some(Ns::from_uri(u)) }
  }
}

///|
/// A virtual DOM tree.
pub(all) enum Vdom {
  Text(String)
  Comment(String)
  Fragment(Array[Vdom])
  Node(VElem)
} derive(Eq, Debug)

///|
/// An element virtual node. `tag` is uppercase for HTML elements and
/// spec-cased under a namespace (see `h`); `ns : None` means HTML.
pub(all) struct VElem {
  tag : String
  attrs : Map[String, AttrValue]
  childs : Array[Vdom]
  key : String?
  ns : Ns?
} derive(Eq, Debug)

///|
/// DOM nodeType parity with the JS classes: Element 1, Text 3, Comment 8,
/// DocumentFragment 11.
pub fn Vdom::node_type(self : Vdom) -> Int {
  match self {
    Text(_) => 3
    Comment(_) => 8
    Fragment(_) => 11
    Node(_) => 1
  }
}

///|
/// The reconciliation key: only element nodes carry one (JS `getKey`).
pub fn Vdom::key(self : Vdom) -> String? {
  match self {
    Node(el) => el.key
    _ => None
  }
}

///|
/// Same tag, namespace and key — morphing may patch in place (JS
/// `isSameKind`).
pub fn VElem::is_same_kind(self : VElem, other : VElem) -> Bool {
  self.tag == other.tag && self.ns == other.ns && self.key == other.key
}

///|
/// Structural equality, identical to the JS `isEqualTo` contract: attrs
/// compare by content (order-insensitive), children recursively. Alias for
/// `==`; kept for API parity with the JS source.
pub fn Vdom::is_equal_to(self : Vdom, other : Vdom) -> Bool {
  // physical_equal short-circuits a shared subtree (e.g. a RenderOnce-cached
  // node reused across render passes) in O(1) before the deep compare — the
  // same fast path diff_props already uses on attr maps.
  physical_equal(self, other) || self == other
}
