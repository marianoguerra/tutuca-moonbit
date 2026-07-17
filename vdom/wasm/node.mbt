// The wasm-gc DOM node wrapper and its DomNode trait impl. TWIN of
// vdom/browser/browser.mbt: mirrors it method-for-method, but every DOM call
// goes through @core.Any's wasm-gc reflection (_get/_set/_call, backed by the
// `jscore` imports). A fix to any DomNode method there almost certainly
// applies here too.

///|
/// A real DOM node (or document) reached from wasm-gc. Wraps the raw JS handle.
pub struct WasmNode(@core.Any)

///|
/// Wrap a raw JS handle (document, element, event target) as a node.
pub fn WasmNode::of_any(v : @core.Any) -> WasmNode {
  WasmNode(v)
}

///|
/// The underlying JS handle (for the app glue: listeners, style injection).
pub fn WasmNode::as_any(self : WasmNode) -> @core.Any {
  self.0
}

///|
fn obj_with_is(is_attr : String) -> @core.Any {
  let o = @core.new_object()
  o._set("is", @core.any(is_attr))
  o
}

///|
pub impl @vdom.DomNode for WasmNode with fn create_element(
  self,
  tag,
  ns,
  is_attr,
) {
  let doc = self.0
  let node = match (ns, is_attr) {
    (None, None) => doc._call("createElement", [@core.any(tag)])
    (None, Some(i)) =>
      doc._call("createElement", [@core.any(tag), obj_with_is(i)])
    (Some(n), None) =>
      doc._call("createElementNS", [@core.any(n.to_uri()), @core.any(tag)])
    (Some(n), Some(i)) =>
      doc._call("createElementNS", [
        @core.any(n.to_uri()),
        @core.any(tag),
        obj_with_is(i),
      ])
  }
  WasmNode(node)
}

///|
pub impl @vdom.DomNode for WasmNode with fn create_text(self, s) {
  WasmNode(self.0._call("createTextNode", [@core.any(s)]))
}

///|
pub impl @vdom.DomNode for WasmNode with fn create_comment(self, s) {
  WasmNode(self.0._call("createComment", [@core.any(s)]))
}

///|
pub impl @vdom.DomNode for WasmNode with fn create_fragment(self) {
  WasmNode(self.0._call("createDocumentFragment", []))
}

///|
pub impl @vdom.DomNode for WasmNode with fn append_child(self, child) {
  let _ = self.0._call("appendChild", [child.0])
}

///|
pub impl @vdom.DomNode for WasmNode with fn insert_before(
  self,
  new_node,
  ref_node,
) {
  let ref_any = match ref_node {
    Some(r) => r.0
    None => @core.null()
  }
  let _ = self.0._call("insertBefore", [new_node.0, ref_any])
}

///|
pub impl @vdom.DomNode for WasmNode with fn remove_child(self, child) {
  let _ = self.0._call("removeChild", [child.0])
}

///|
pub impl @vdom.DomNode for WasmNode with fn replace_child(
  self,
  new_node,
  old_node,
) {
  let _ = self.0._call("replaceChild", [new_node.0, old_node.0])
}

///|
pub impl @vdom.DomNode for WasmNode with fn replace_children(self) {
  let _ = self.0._call("replaceChildren", [])
}

///|
pub impl @vdom.DomNode for WasmNode with fn parent_node(self) {
  wrap_option(self.0._get("parentNode"))
}

///|
pub impl @vdom.DomNode for WasmNode with fn first_child(self) {
  wrap_option(self.0._get("firstChild"))
}

///|
pub impl @vdom.DomNode for WasmNode with fn next_sibling(self) {
  wrap_option(self.0._get("nextSibling"))
}

///|
pub impl @vdom.DomNode for WasmNode with fn child_nodes(self) {
  @core.array_from(self.0._get("childNodes")).map(fn(n) { WasmNode(n) })
}

///|
pub impl @vdom.DomNode for WasmNode with fn child_node_at(self, i) {
  wrap_option(self.0._get("childNodes")._get_by_index(i))
}

///|
/// Satisfies the DomNode contract (compare the underlying node, not the
/// wrapper): @core.equal is the jscore `equal` import, which is JS `===` —
/// the same semantics as the browser twin's isSameNode-style check.
pub impl @vdom.DomNode for WasmNode with fn is_same_node(self, other) {
  @core.equal(self.0, other.0)
}

///|
pub impl @vdom.DomNode for WasmNode with fn set_attribute(self, name, value) {
  let _ = self.0._call("setAttribute", [@core.any(name), @core.any(value)])
}

///|
pub impl @vdom.DomNode for WasmNode with fn remove_attribute(self, name) {
  let _ = self.0._call("removeAttribute", [@core.any(name)])
}

///|
pub impl @vdom.DomNode for WasmNode with fn has_property(self, name) {
  tdom_has_prop(self.0, name)
}

///|
pub impl @vdom.DomNode for WasmNode with fn set_property(self, name, value) {
  tdom_try_set_prop(self.0, name, attr_to_any(value))
}

///|
pub impl @vdom.DomNode for WasmNode with fn set_inner_html(self, html) {
  self.0._set("innerHTML", @core.any(html))
}

///|
pub impl @vdom.DomNode for WasmNode with fn get_inner_html(self) {
  to_str(self.0._get("innerHTML"))
}

///|
pub impl @vdom.DomNode for WasmNode with fn set_data(self, s) {
  self.0._set("data", @core.any(s))
}

///|
pub impl @vdom.DomNode for WasmNode with fn tag_name(self) {
  to_str(self.0._get("tagName"))
}

///|
pub impl @vdom.DomNode for WasmNode with fn namespace_uri(self) {
  let v = self.0._get("namespaceURI")
  if @core.is_nullish(v) {
    None
  } else {
    @vdom.ns_from_dom_uri(Some(v.to_string()))
  }
}
