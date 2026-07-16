// Fragment parsing over moonbit-community/html, replacing jsdom's
// `template.innerHTML` (src/anode.js ParseContext.parseHTML). Wrapping the
// input in a <template> element makes the WHATWG parser use the
// template-contents insertion mode, which is what innerHTML on a template
// gives jsdom: content models are not enforced, so bare <tr>, <option>,
// <col> and friends survive unwrapped instead of being dropped or
// foster-parented the way they would be in a <body> context.

///|
/// Parse `html` as a template fragment. Returns the backing document and the
/// node ids of the fragment's root nodes.
///
/// Known divergence from jsdom: input containing a literal `</template>`
/// closes the wrapper early, truncating the fragment.
pub fn parse_fragment(html : String) -> (@html5.Document, Array[Int]) {
  let doc = @html5.parse("<template>" + html + "</template>")
  // The wrapper is the FIRST template element in document order (a template
  // with no surrounding markup typically lands in <head>, so don't assume a
  // body placement; and templates inside the fragment come later).
  for i, node in doc.nodes {
    if node is ElementNode(el) && el.tag_name == "template" && el.ns is HTML {
      let content = doc.get_template_content(i)
      if content != @html5.NO_NODE {
        return (doc, doc.get_children(content))
      }
    }
  }
  (doc, [])
}
