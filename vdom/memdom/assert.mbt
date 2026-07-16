///|
/// Structural DOM equality, the contract from the JS suite's assertEqualDom:
/// kind, tag, namespace, character data, attribute count + values, children
/// recursively (plus memdom's raw dangerous_html). Live `props` are
/// intentionally NOT compared — a morph that removes an attribute leaves a
/// cleared property behind, exactly like a real DOM node keeps live IDL
/// state; the JS contract compares attributes only.
pub fn dom_equal(a : MemNode, b : MemNode) -> Bool {
  if a.kind != b.kind ||
    a.tag != b.tag ||
    a.ns != b.ns ||
    a.data != b.data ||
    a.dangerous_html != b.dangerous_html {
    return false
  }
  if a.attrs != b.attrs {
    return false
  }
  if a.childs.length() != b.childs.length() {
    return false
  }
  for i in 0..<a.childs.length() {
    if !dom_equal(a.childs[i], b.childs[i]) {
      return false
    }
  }
  true
}
