// Fragment parsing over moonbit-community/html. Wrapping the
// input in a <template> element makes the WHATWG parser use the
// template-contents insertion mode, where content models are not enforced,
// so bare <tr>, <option>,
// <col> and friends survive unwrapped instead of being dropped or
// foster-parented the way they would be in a <body> context.

///|
/// Parse `html` as a template fragment. Returns the backing document and the
/// node ids of the fragment's root nodes.
///
/// Known divergence: input containing a literal `</template>`
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

///|
/// Parse `svg` as a fragment in the SVG namespace. Returns the backing document
/// and the node ids of the fragment's root nodes, which are the children of an
/// `<svg>` element this adds and does not return.
///
/// The wrapper is what makes the namespace happen. `<circle/>` on its own is an
/// unknown HTML element; inside `<svg>` the tree builder switches to foreign
/// content and every descendant lands in the SVG namespace with its source case
/// adjusted through the HTML5 table (`linearGradient`, `animateTransform`).
/// That is the same mechanism a browser uses, not an approximation of it —
/// `anode_namespace_test.mbt` and `html_adapter_test.mbt` pin both halves.
///
/// It also means the caller gets the namespace as a GUARANTEE rather than as
/// whatever the payload asked for: the only way back into HTML is
/// `<foreignObject>`, which is the integration point the spec provides and
/// which the sanitizer judges as HTML because the parser labels it that way.
///
/// Known divergence, the SVG twin of the `</template>` one above: a payload
/// containing a literal `</svg>` closes the wrapper early, and everything after
/// it is dropped rather than returned. Truncating is the safe direction — the
/// alternative would be content that escaped the namespace it was promised.
pub fn parse_fragment_svg(svg : String) -> (@html5.Document, Array[Int]) {
  let (doc, roots) = parse_fragment("<svg>" + svg + "</svg>")
  for id in roots {
    if doc.get_node(id) is Some(ElementNode(el)) &&
      el.tag_name == "svg" &&
      el.ns is SVG {
      return (doc, doc.get_children(id))
    }
  }
  (doc, [])
}
