// Serializing a mounted DOM the way a person reads it.
//
// `MemNode::to_html` prints everything, which is right for a renderer test and
// wrong for anything a person or a second mount compares: a rendered tree
// carries a `data-cid` per component, a `data-eid` per handler and a `§…§`
// comment at every subtree boundary, and a reader looking for
// `<li class="done">` has to find it among them.
//
// Worse, they MOVE. A component id comes from a process-global counter, so the
// same app mounted twice renders the same page with different numbers in it —
// which makes raw HTML the wrong thing to hold two mounts against, and that is
// exactly what a card's report and a replayed recording both want to do.
//
// The predicates are `render`'s own, which is the point: `clean_vdom` strips
// the same set from a `Vdom`, and a caller here holds a serialized DOM
// instead. Two lists would be one list plus a stamp that stops being stripped
// the day a new one is added to the other.

///|
/// A mounted DOM as HTML, without the renderer's own bookkeeping.
pub fn clean_html(node : @memdom.MemNode) -> String {
  let sb = StringBuilder()
  write_clean(node, sb)
  sb.to_string()
}

///|
fn write_clean(node : @memdom.MemNode, sb : StringBuilder) -> Unit {
  match node.kind {
    Document | FragmentNode =>
      for c in node.childs {
        write_clean(c, sb)
      }
    TextNode => sb.write_string(node.data)
    CommentNode =>
      if !@render.is_meta_comment(node.data) {
        sb.write_string("<!--\{node.data}-->")
      }
    Element => {
      let tag = if node.ns is None { node.tag.to_lower() } else { node.tag }
      sb.write_string("<\{tag}")
      for name, value in node.attrs {
        if !@render.is_internal_attr(name) {
          sb.write_string(" \{name}=\"\{value}\"")
        }
      }
      sb.write_string(">")
      match node.dangerous_html {
        Some(html) => sb.write_string(html)
        None =>
          for c in node.childs {
            write_clean(c, sb)
          }
      }
      sb.write_string("</\{tag}>")
    }
  }
}

///|
/// This harness's DOM, without the renderer's bookkeeping.
///
/// The right thing to compare two mounts with, and `html()` is the right thing
/// to debug ONE with: component ids come from a process-global counter, so the
/// same app mounted twice renders identical pages that differ in every
/// `data-cid`.
pub fn Harness::clean_html(self : Harness[@memdom.MemNode]) -> String {
  clean_html(self.container)
}
