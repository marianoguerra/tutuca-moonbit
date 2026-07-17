// ANode::parse / from_dom (src/anode.js ANode.parse / ANode.fromDOM).

///|
pub fn ANode::parse(html : String, px : ParseContext) -> ANode? {
  let (doc, roots) = parse_fragment(html)
  if roots.length() == 0 {
    return Some(Comment({ val: "Empty View in ANode.parse" }))
  }
  if roots.length() == 1 {
    return ANode::from_dom(doc, roots[0], px)
  }
  let childs : Array[ANode] = []
  for root in roots {
    match ANode::from_dom(doc, root, px) {
      Some(child) => childs.push(child)
      None => ()
    }
  }
  let trimmed = condense_childs_whites(childs)
  if trimmed.length() == 0 {
    return Some(Comment({ val: "Empty View in ANode.parse" }))
  }
  Some(maybe_fragment(trimmed))
}

///|
fn is_valid_tag_name(tag : String) -> Bool {
  // JS: /^[a-zA-Z][a-zA-Z0-9-]*$/
  guard tag.get_char(0) is Some('a'..='z' | 'A'..='Z') else { return false }
  for c in tag {
    if !(c is ('a'..='z' | 'A'..='Z' | '0'..='9' | '-')) {
      return false
    }
  }
  true
}

///|
/// Convert one DOM node (JS ANode.fromDOM) — ANode::parse's recursion
/// worker. None when the node contributes nothing (unsupported node kinds,
/// failed <x> ops).
fn ANode::from_dom(
  doc : @html5.Document,
  node_id : Int,
  px : ParseContext,
) -> ANode? {
  match doc.get_node(node_id) {
    Some(TextNode(s)) => Some(Text({ val: s }))
    Some(CommentNode(s)) => Some(Comment({ val: s }))
    Some(ElementNode(el)) => from_element(doc, node_id, el, px)
    // Doctypes etc. cannot appear in template content; drop defensively.
    _ => None
  }
}

///|
fn from_element(
  doc : @html5.Document,
  node_id : Int,
  el : @html5.Element,
  px : ParseContext,
) -> ANode? {
  // Children first, with their own current_tag save/restore cycles; this
  // element's tag is only current for its own attribute / x-op parsing.
  let childs : Array[ANode] = []
  for child_id in doc.get_children(node_id) {
    match ANode::from_dom(doc, child_id, px) {
      Some(child) => childs.push(child)
      None => ()
    }
  }
  let tag = el.tag_name
  let attrs = el.attributes
  let prev_tag = px.current_tag
  px.current_tag = Some(tag)
  let result : ANode? = if tag is ("x" | "X") ||
    (attrs.length() > 0 && attrs[0].0 == "@x") {
    // <X> op, or pseudo-x: any element carrying a leading bare `@x`.
    let is_pseudo_x = !(tag is ("x" | "X"))
    parse_x_op(attrs, childs, if is_pseudo_x { 1 } else { 0 }, px)
  } else if tag is ['x' | 'X', ':', .. macro_rest] {
    // Foreign (SVG/MathML) content keeps source case, hence the X: variants.
    let macro_name = macro_rest.to_owned().to_lower()
    if macro_name == "slot" {
      let slot_name = get_named_item(attrs, "name").unwrap_or("_")
      let from_frame = match px.frame {
        Some(f) => f.macro_slots.get(slot_name)
        None => None
      }
      Some(from_frame.unwrap_or_else(() => maybe_fragment(childs)))
    } else {
      let result = parse_attributes(attrs, px, parse_all=true)
      px.handler.on_attributes(result, true, tag)
      Some(
        wrap(
          px.new_macro_node(macro_name, result.attrs.to_macro_vars(), childs),
          px,
          result.wrappers,
        ),
      )
    }
  } else if is_valid_tag_name(tag) {
    let result = parse_attributes(attrs, px)
    px.handler.on_attributes(result, false, tag)
    if result.text_child is Some(tc) {
      childs.insert(0, RenderText({ node_id: None, val: tc }))
    }
    let dom_childs = if tag != "pre" {
      condense_childs_whites(childs)
    } else {
      childs
    }
    let ns : Ns? = match el.ns {
      HTML => None
      SVG => Some(Svg)
      MathML => Some(MathML)
    }
    Some(
      wrap(
        Dom({ tag, attrs: result.attrs, childs: dom_childs, ns }),
        px,
        result.wrappers,
      ),
    )
  } else {
    Some(Comment({ val: "Error: InvalidTagName \{tag}" }))
  }
  px.current_tag = prev_tag
  result
}

///|
fn get_named_item(attrs : Array[(String, String)], name : String) -> String? {
  for pair in attrs {
    if pair.0 == name {
      return Some(pair.1)
    }
  }
  None
}

///|
/// Apply directive wrappers around `node`, last wrapper innermost so the
/// FIRST directive in source order ends up outermost (JS wrap()).
fn wrap(
  node : ANode,
  px : ParseContext,
  wrappers : Array[WrapperAttr],
) -> ANode {
  let mut node = node
  for i = wrappers.length() - 1; i >= 0; i = i - 1 {
    match make_wrapper_node(wrappers[i], px) {
      Some(wrapper) => {
        wrapper.wrap_node(node)
        node = wrapper
      }
      // A dropped wrapper here means its directive value failed to parse, which
      // AttrParser::directive_value already reported as BadValue(Directive) when
      // it built the WrapperAttr — so no second issue is surfaced (the JS TODO
      // at anode.js:317 exists because JS never reported it at all; the port
      // does, upstream). The one path that lacked a report — `@show`/`@hide`
      // used as wrapper attrs on an <x> op — is handled in build_x_wrappers.
      None => ()
    }
  }
  node
}

///|
/// Build the wrapper node for a directive descriptor (JS makeWrapperNode):
/// Each/Scope register in px.nodes, Show/Hide/PushView stay unregistered.
fn make_wrapper_node(data : WrapperAttr, px : ParseContext) -> ANode? {
  let node : ANode? = match data.kind {
    Each =>
      px.add_node_if(data.val, (id, val) => {
        Each({
          node_id: id,
          iter_info: {
            val,
            when_val: None,
            loop_with_val: None,
            enrich_with_val: None,
          },
          node: empty_node(),
          from_render_each: false,
        })
      })
    Scope =>
      px.add_node_if(data.val, (id, val) => {
        Scope({ node_id: Some(id), val, node: empty_node() })
      })
    Show =>
      data.val.map(val => Show({ node_id: None, val, node: empty_node() }))
    Hide =>
      data.val.map(val => Hide({ node_id: None, val, node: empty_node() }))
    PushView =>
      data.val.map(val => PushView({ node_id: None, val, node: empty_node() }))
  }
  if node is Some(Each(d)) {
    d.iter_info.enrich_with_val = data.enrich_with_val
    d.iter_info.when_val = data.when_val
    d.iter_info.loop_with_val = data.loop_with_val
  }
  node
}
