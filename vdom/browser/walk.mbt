// Read-side walk over the real DOM (the js bridge for event-path
// reconstruction).

///|
extern "js" fn char_data_ffi(node : @core.Any) -> String =
  #|(n) => n.data ?? ""

///|
extern "js" fn get_attribute_ffi(node : @core.Any, name : String) -> @core.Any =
  #|(n, name) => (n.getAttribute && n.getAttribute(name)) ?? null

///|
pub impl @vdom.DomWalk for BrowserNode with fn prev_sibling(self) {
  wrap_option(self.0._get("previousSibling"))
}

///|
pub impl @vdom.DomWalk for BrowserNode with fn node_kind(self) {
  self.0._get("nodeType").cast()
}

///|
pub impl @vdom.DomWalk for BrowserNode with fn char_data(self) {
  char_data_ffi(self.0)
}

///|
pub impl @vdom.DomWalk for BrowserNode with fn attribute(self, name) {
  let v = get_attribute_ffi(self.0, name)
  if is_null_ffi(v) {
    None
  } else {
    Some(v.cast())
  }
}
