// Minimal DOM externs the adapter needs beyond @core's generic _get/_set/
// _call: creation with the `is` option, null-aware navigation, the `in`
// membership test, the try/catch property write, and replaceChildren
// (not bound by js_browser as of 0.12.1).

///|
extern "js" fn is_null_ffi(v : @core.Any) -> Bool =
  #|(v) => v == null

///|
extern "js" fn create_element_ffi(doc : @core.Any, tag : String) -> @core.Any =
  #|(d, t) => d.createElement(t)

///|
extern "js" fn create_element_is_ffi(
  doc : @core.Any,
  tag : String,
  is_attr : String,
) -> @core.Any =
  #|(d, t, i) => d.createElement(t, { is: i })

///|
extern "js" fn create_element_ns_ffi(
  doc : @core.Any,
  ns : String,
  tag : String,
) -> @core.Any =
  #|(d, n, t) => d.createElementNS(n, t)

///|
extern "js" fn create_element_ns_is_ffi(
  doc : @core.Any,
  ns : String,
  tag : String,
  is_attr : String,
) -> @core.Any =
  #|(d, n, t, i) => d.createElementNS(n, t, { is: i })

///|
extern "js" fn insert_before_ffi(
  parent : @core.Any,
  node : @core.Any,
  ref_node : @core.Any,
) -> Unit =
  #|(p, n, r) => { p.insertBefore(n, r) }

///|
extern "js" fn replace_children_ffi(node : @core.Any) -> Unit =
  #|(n) => { n.replaceChildren() }

///|
extern "js" fn is_same_node_ffi(a : @core.Any, b : @core.Any) -> Bool =
  #|(a, b) => a === b

///|
extern "js" fn has_prop_ffi(obj : @core.Any, name : String) -> Bool =
  #|(o, n) => n in o

///|
extern "js" fn try_set_prop_ffi(
  obj : @core.Any,
  name : String,
  value : @core.Any,
) -> Bool =
  #|(o, n, v) => { try { o[n] = v; return true } catch (e) { return false } }

///|
extern "js" fn tag_name_ffi(node : @core.Any) -> String =
  #|(n) => n.tagName || ""

///|
extern "js" fn namespace_uri_ffi(node : @core.Any) -> @core.Any =
  #|(n) => n.namespaceURI ?? null
