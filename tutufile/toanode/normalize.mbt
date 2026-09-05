// Comparing a tree this package built with a tree the HTML parser built.
//
// The two disagree about whitespace and always will: one takes the text the
// file wrote, the other takes what a tokenizer made of the file's LAYOUT and
// then repairs it with a block/inline table. Neither is wrong about anything
// except the other, so a comparison that means something has to look past it.
//
// This is that comparison, and it is a normalizer rather than a bespoke `Eq`
// so that the thing it ignores is written down and reviewable. It is used by
// the equivalence tests and by `tutufile/equiv`, which is the acceptance check
// for converting a view file — the same question in both places.

///|
/// A copy of the tree with whitespace-only text dropped and the rest collapsed
/// to single spaces.
///
/// A COPY, not a mutation: the tree is shared and the caller usually wants to
/// keep the original to render.
pub fn strip_ws(node : @anode.ANode) -> @anode.ANode {
  match node {
    Text(d) => @anode.text(collapse_ws(d.val))
    Comment(d) => @anode.comment(collapse_ws(d.val))
    Dom(d) =>
      Dom({
        tag: d.tag,
        attrs: d.attrs,
        childs: strip_kids(d.childs),
        ns: d.ns,
        // A memo `render` fills, and never a fact about the source. Dropping it
        // keeps two trees from differing over which of them has been rendered.
        sink_hints: None,
        bind: d.bind,
      })
    Fragment(d) => Fragment({ childs: strip_kids(d.childs), })
    Show(d) => Show({ node_id: d.node_id, val: d.val, node: strip_ws(d.node), })
    Hide(d) => Hide({ node_id: d.node_id, val: d.val, node: strip_ws(d.node), })
    PushView(d) =>
      PushView({ node_id: d.node_id, val: d.val, node: strip_ws(d.node), })
    Scope(d) =>
      Scope({ node_id: d.node_id, val: d.val, node: strip_ws(d.node), })
    Slot(d) => Slot({ name: d.name, node: strip_ws(d.node), })
    Each(d) =>
      Each({
        node_id: d.node_id,
        iter_info: d.iter_info,
        node: strip_ws(d.node),
        from_render_each: d.from_render_each,
      })
    other => other
  }
}

///|
fn strip_kids(cs : Array[@anode.ANode]) -> Array[@anode.ANode] {
  let out = []
  for c in cs {
    let k = strip_ws(c)
    if k is (Text(d) | Comment(d)) && d.val == "" {
      continue
    }
    out.push(k)
  }
  out
}

///|
/// Runs of whitespace to one space, ends trimmed.
pub fn collapse_ws(s : String) -> String {
  let words = []
  let cur = StringBuilder()
  for c in s {
    if c is (' ' | '\t' | '\n' | '\r') {
      if cur.to_string() != "" {
        words.push(cur.to_string())
        cur.reset()
      }
    } else {
      cur.write_char(c)
    }
  }
  if cur.to_string() != "" {
    words.push(cur.to_string())
  }
  words.join(" ")
}
