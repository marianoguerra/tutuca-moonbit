///|
/// Abstract DOM surface the renderer drives. The document is itself a node:
/// creation methods are only ever invoked on `RenderOpts::document`.
///
/// `set_property` models the JS `try { node[name] = value } catch {}` —
/// returning `false` makes `set_prop` fall through to the attribute path.
/// `is_same_node` is JS `===`; adapters whose wrapper values are re-created
/// per call must compare the underlying node, so the core never uses
/// `physical_equal` on trait values.
pub(open) trait DomNode {
  fn create_element(Self, tag : String, ns : Ns?, is_attr : String?) -> Self
  fn create_text(Self, String) -> Self
  fn create_comment(Self, String) -> Self
  fn create_fragment(Self) -> Self
  fn append_child(Self, Self) -> Unit
  fn insert_before(Self, new_node : Self, ref_node : Self?) -> Unit
  fn remove_child(Self, Self) -> Unit
  fn replace_child(Self, new_node : Self, old_node : Self) -> Unit
  fn replace_children(Self) -> Unit // clear-all form only
  fn parent_node(Self) -> Self?
  fn first_child(Self) -> Self?
  fn next_sibling(Self) -> Self?
  fn child_nodes(Self) -> Array[Self] // snapshot, not a live collection
  fn child_node_at(Self, Int) -> Self? // live childNodes[i]
  fn is_same_node(Self, Self) -> Bool
  fn set_attribute(Self, name : String, value : String) -> Unit
  fn remove_attribute(Self, String) -> Unit
  fn has_property(Self, String) -> Bool // JS `name in node`
  fn set_property(Self, name : String, value : AttrValue) -> Bool
  fn set_inner_html(Self, String) -> Unit
  fn get_inner_html(Self) -> String
  fn set_data(Self, String) -> Unit // text/comment character data
  fn tag_name(Self) -> String
  fn namespace_uri(Self) -> Ns? // None = HTML (adapters map null and the HTML ns)
}

///|
/// Options threaded through rendering. `ns` is the namespace inherited from
/// the nearest namespaced ancestor; callers only set `document`.
pub(all) struct RenderOpts[N] {
  document : N
  ns : Ns?
}

///|
pub fn[N] RenderOpts::new(document : N) -> RenderOpts[N] {
  { document, ns: None }
}

///|
/// SVG / MathML elements expose their attributes as read-only IDL properties
/// (`cx`, `viewBox`, …), so on a namespaced node every attribute must go
/// through set_attribute rather than the property path.
fn[N : DomNode] is_namespaced(node : N) -> Bool {
  node.namespace_uri() is Some(_)
}

///|
/// Per SVG spec, <foreignObject> is itself an SVG element but its children
/// are HTML — every descent into a foreignObject must switch the inherited
/// namespace back to HTML.
fn is_foreign_object(tag : String) -> Bool {
  tag.length() == 13 && tag.to_lower() == "foreignobject"
}

///|
/// Namespace inherited from the nearest namespaced ancestor: vnodes get their
/// own namespace from `h()`, but children created via the `h()` API don't
/// know about their parent — `opts.ns` threads the inherited value through
/// `to_dom` and `morph_children`.
fn[N] effective_ns(el : VElem, opts : RenderOpts[N]) -> Ns? {
  match el.ns {
    Some(n) => Some(n)
    None => opts.ns
  }
}

///|
/// Compute the namespace to pass to this element's children.
fn[N] child_opts(el : VElem, ns : Ns?, opts : RenderOpts[N]) -> RenderOpts[N] {
  let target = if ns is Some(Svg) && is_foreign_object(el.tag) {
    None
  } else {
    ns
  }
  if target == opts.ns {
    opts
  } else {
    { ..opts, ns: target }
  }
}
