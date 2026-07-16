// Read-side walk over the real DOM (the wasm bridge for event-path
// reconstruction), mirroring vdom/browser/walk.mbt.

///|
pub impl @vdom.DomWalk for WasmNode with fn prev_sibling(self) {
  wrap_option(self.0._get("previousSibling"))
}

///|
pub impl @vdom.DomWalk for WasmNode with fn node_kind(self) {
  tdom_node_type(self.0)
}

///|
pub impl @vdom.DomWalk for WasmNode with fn char_data(self) {
  to_str(self.0._get("data"))
}

///|
pub impl @vdom.DomWalk for WasmNode with fn attribute(self, name) {
  if tdom_has_prop(self.0, "getAttribute") {
    let v = self.0._call("getAttribute", [@core.any(name)])
    if @core.is_nullish(v) {
      None
    } else {
      Some(v.to_string())
    }
  } else {
    None
  }
}
