// Small `tdom` FFI + helpers for the wasm-gc DOM adapter. These cover the parts
// @core.Any cannot express on wasm-gc: reading a typed Int out of a JS value,
// the `name in obj` membership test, and the try/catch property write. Strings
// come back through @core (Any::to_string); node handles through @core.Any.
// The JS side of `tdom` lives in the demo's loader.mjs.

///|
extern "wasm" fn tdom_node_type(node : @core.Any) -> Int = "tdom" "node_type"

///|
extern "wasm" fn tdom_has_prop(obj : @core.Any, name : String) -> Bool = "tdom" "has_prop"

///|
extern "wasm" fn tdom_try_set_prop(
  obj : @core.Any,
  name : String,
  value : @core.Any,
) -> Bool = "tdom" "try_set_prop"

///|
/// Null/undefined-safe string read.
fn to_str(v : @core.Any) -> String {
  if @core.is_nullish(v) {
    ""
  } else {
    v.to_string()
  }
}

///|
/// Wrap a possibly null/undefined JS node as an optional WasmNode.
fn wrap_option(v : @core.Any) -> WasmNode? {
  if @core.is_nullish(v) {
    None
  } else {
    Some(WasmNode(v))
  }
}

///|
fn attr_to_any(v : @vdom.AttrValue) -> @core.Any {
  // `@core.any` is a raw %identity cast — only sound for types already
  // represented as externref (String, under js-string-builtins). Double/Bool
  // must go through ToAny's wasm-gc impls (wasm_from_double / wasm_from_bool).
  match v {
    Str(s) => @core.any(s)
    Num(d) => @core.ToAny::to_any(d)
    Bool(b) => @core.ToAny::to_any(b)
    Html(s) => @core.any(s)
    // Structured custom-element property: JSON.parse on the JS side of tdom.
    Data(j) => tdom_json_parse(j.stringify())
  }
}

///|
extern "wasm" fn tdom_json_parse(s : String) -> @core.Any = "tdom" "json_parse"
