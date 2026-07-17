// TWIN: vdom/wasm/node.mbt mirrors this file method-for-method (same logic,
// different FFI seam — extern "js" here, @core.Any reflection + tdom there).
// A fix to any DomNode method here almost certainly applies there too.

///|
/// A real DOM node (or document) for the js backend. Wraps the raw JS value;
/// the orphan rule prevents implementing the vdom trait directly on
/// @dom.Node, and going through @core.Any keeps one uniform representation
/// for documents, elements, text and fragments — exactly like the JS source.
pub struct BrowserNode(@core.Any)

///|
fn wrap_option(v : @core.Any) -> BrowserNode? {
  if is_null_ffi(v) {
    None
  } else {
    Some(BrowserNode(v))
  }
}

///|
pub fn BrowserNode::from_document(doc : @dom.Document) -> BrowserNode {
  BrowserNode(@core.identity(doc))
}

///|
pub fn BrowserNode::from_element(el : @dom.Element) -> BrowserNode {
  BrowserNode(el.as_any())
}

///|
pub fn BrowserNode::as_any(self : BrowserNode) -> @core.Any {
  self.0
}

///|
/// Render options for the current window's document.
pub fn window_opts() -> @vdom.RenderOpts[BrowserNode] {
  @vdom.RenderOpts::new(BrowserNode::from_document(@dom.window().document()))
}

///|
/// Render options for an explicit document (e.g. a happy-dom window in
/// tests).
pub fn opts_for(doc : @dom.Document) -> @vdom.RenderOpts[BrowserNode] {
  @vdom.RenderOpts::new(BrowserNode::from_document(doc))
}

///|
fn attr_to_any(v : @vdom.AttrValue) -> @core.Any {
  match v {
    Str(s) => @core.any(s)
    Num(d) => @core.any(d)
    Bool(b) => @core.any(b)
    Html(s) => @core.any(s)
    // Structured custom-element property: rebuild the real JS object.
    Data(j) => json_parse_ffi(j.stringify())
  }
}

///|
extern "js" fn json_parse_ffi(s : String) -> @core.Any =
  #|(s) => JSON.parse(s)

///|
pub impl @vdom.DomNode for BrowserNode with fn create_element(
  self,
  tag,
  ns,
  is_attr,
) {
  let doc = self.0
  let node = match (ns, is_attr) {
    (None, None) => create_element_ffi(doc, tag)
    (None, Some(i)) => create_element_is_ffi(doc, tag, i)
    (Some(n), None) => create_element_ns_ffi(doc, n.to_uri(), tag)
    (Some(n), Some(i)) => create_element_ns_is_ffi(doc, n.to_uri(), tag, i)
  }
  BrowserNode(node)
}

///|
pub impl @vdom.DomNode for BrowserNode with fn create_text(self, s) {
  BrowserNode(self.0._call("createTextNode", [@core.any(s)]))
}

///|
pub impl @vdom.DomNode for BrowserNode with fn create_comment(self, s) {
  BrowserNode(self.0._call("createComment", [@core.any(s)]))
}

///|
pub impl @vdom.DomNode for BrowserNode with fn create_fragment(self) {
  BrowserNode(self.0._call("createDocumentFragment", []))
}

///|
pub impl @vdom.DomNode for BrowserNode with fn append_child(self, child) {
  let _ = self.0._call("appendChild", [child.0])
}

///|
pub impl @vdom.DomNode for BrowserNode with fn insert_before(
  self,
  new_node,
  ref_node,
) {
  let ref_any = match ref_node {
    Some(r) => r.0
    None => @core.null()
  }
  insert_before_ffi(self.0, new_node.0, ref_any)
}

///|
pub impl @vdom.DomNode for BrowserNode with fn remove_child(self, child) {
  let _ = self.0._call("removeChild", [child.0])
}

///|
pub impl @vdom.DomNode for BrowserNode with fn replace_child(
  self,
  new_node,
  old_node,
) {
  let _ = self.0._call("replaceChild", [new_node.0, old_node.0])
}

///|
pub impl @vdom.DomNode for BrowserNode with fn replace_children(self) {
  replace_children_ffi(self.0)
}

///|
pub impl @vdom.DomNode for BrowserNode with fn parent_node(self) {
  wrap_option(self.0._get("parentNode"))
}

///|
pub impl @vdom.DomNode for BrowserNode with fn first_child(self) {
  wrap_option(self.0._get("firstChild"))
}

///|
pub impl @vdom.DomNode for BrowserNode with fn next_sibling(self) {
  wrap_option(self.0._get("nextSibling"))
}

///|
pub impl @vdom.DomNode for BrowserNode with fn child_nodes(self) {
  @core.array_from(self.0._get("childNodes")).map(n => BrowserNode(n))
}

///|
pub impl @vdom.DomNode for BrowserNode with fn child_node_at(self, i) {
  wrap_option(self.0._get("childNodes")._get_by_index(i))
}

///|
pub impl @vdom.DomNode for BrowserNode with fn is_same_node(self, other) {
  is_same_node_ffi(self.0, other.0)
}

///|
pub impl @vdom.DomNode for BrowserNode with fn set_attribute(self, name, value) {
  let _ = self.0._call("setAttribute", [@core.any(name), @core.any(value)])
}

///|
pub impl @vdom.DomNode for BrowserNode with fn remove_attribute(self, name) {
  let _ = self.0._call("removeAttribute", [@core.any(name)])
}

///|
pub impl @vdom.DomNode for BrowserNode with fn has_property(self, name) {
  has_prop_ffi(self.0, name)
}

///|
pub impl @vdom.DomNode for BrowserNode with fn set_property(self, name, value) {
  try_set_prop_ffi(self.0, name, attr_to_any(value))
}

///|
pub impl @vdom.DomNode for BrowserNode with fn set_inner_html(self, html) {
  self.0._set("innerHTML", @core.any(html))
}

///|
pub impl @vdom.DomNode for BrowserNode with fn get_inner_html(self) {
  self.0._get("innerHTML").cast()
}

///|
pub impl @vdom.DomNode for BrowserNode with fn set_data(self, s) {
  self.0._set("data", @core.any(s))
}

///|
pub impl @vdom.DomNode for BrowserNode with fn tag_name(self) {
  tag_name_ffi(self.0)
}

///|
pub impl @vdom.DomNode for BrowserNode with fn namespace_uri(self) {
  let v = namespace_uri_ffi(self.0)
  if is_null_ffi(v) {
    None
  } else {
    @vdom.ns_from_dom_uri(Some(v.cast()))
  }
}

///|
/// Wrap a raw JS value (e.g. an event target) as a node. The caller
/// guarantees it is a DOM node.
pub fn BrowserNode::of_any(v : @core.Any) -> BrowserNode {
  BrowserNode(v)
}
