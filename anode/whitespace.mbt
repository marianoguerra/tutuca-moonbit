// Whitespace condensing between element children (src/anode.js
// condenseChildsWhites and friends). Tag names are lowercase here (the HTML
// parser lowercases; the JS original compared uppercase jsdom names).

///|
let html_block_tags : Set[String] = Set::from_array([
  "address", "article", "aside", "blockquote", "caption", "col", "colgroup", "details",
  "dialog", "div", "dd", "dl", "dt", "fieldset", "figcaption", "figure", "footer",
  "form", "h1", "h2", "h3", "h4", "h5", "h6", "header", "hgroup", "hr", "legend",
  "li", "main", "menu", "nav", "ol", "p", "pre", "section", "summary", "table", "tbody",
  "td", "tfoot", "th", "thead", "tr", "ul",
])

///|
fn is_block_dom_node(n : ANode) -> Bool {
  let node = match n {
    Fragment(d) => d.childs.get(0)
    _ => Some(n)
  }
  node is Some(Dom(d)) && html_block_tags.contains(d.tag)
}

///|
/// Empty Text/Comment produced by condensing (JS isEmptyText matches
/// CommentNode too via instanceof TextNode).
fn is_empty_text(c : ANode) -> Bool {
  c is (Text(d) | Comment(d)) && d.val == ""
}

///|
/// Collapse a leading/trailing whitespace child to nothing; returns whether it
/// became an empty node that the final filter should drop.
fn trim_edge_white(node : ANode) -> Bool {
  if !node.is_whitespace() {
    return false
  }
  node.condense_whitespace()
  true
}

///|
pub fn condense_childs_whites(childs : Array[ANode]) -> Array[ANode] {
  if childs.length() == 0 {
    return childs
  }
  let last = childs.length() - 1
  let mut emptied = trim_edge_white(childs[0])
  if last > 0 && trim_edge_white(childs[last]) {
    emptied = true
  }
  for i in 1..<last {
    let cur = childs[i]
    if !(cur.is_whitespace() && cur.has_newline()) {
      continue
    }
    let both_block = is_block_dom_node(childs[i - 1]) &&
      is_block_dom_node(childs[i + 1])
    cur.condense_whitespace(replacement=if both_block { "" } else { " " })
    if both_block {
      emptied = true
    }
  }
  if emptied {
    childs.filter(c => !is_empty_text(c))
  } else {
    childs
  }
}
