///|
/// Debug/snapshot HTML serialization. Attribute order is preserved; HTML
/// tags print lowercase like outerHTML; no entity escaping (this is a test
/// aid, not a sanitizer).
pub fn MemNode::to_html(self : MemNode) -> String {
  let sb = StringBuilder()
  self.write_html(sb)
  sb.to_string()
}

///|
fn MemNode::write_html(self : MemNode, sb : StringBuilder) -> Unit {
  match self.kind {
    Document | FragmentNode =>
      for c in self.childs {
        c.write_html(sb)
      }
    TextNode => sb.write_string(self.data)
    CommentNode => sb.write_string("<!--\{self.data}-->")
    Element => {
      let tag = if self.ns is None { self.tag.to_lower() } else { self.tag }
      sb.write_string("<\{tag}")
      for name, value in self.attrs {
        sb.write_string(" \{name}=\"\{value}\"")
      }
      sb.write_string(">")
      match self.dangerous_html {
        Some(html) => sb.write_string(html)
        None =>
          for c in self.childs {
            c.write_html(sb)
          }
      }
      sb.write_string("</\{tag}>")
    }
  }
}
