// <x> special ops (src/anode.js parseXOp / processXExtras / parseRenderEach /
// the X_OPS table).

///|
priv enum XOp {
  OpSlot
  OpText
  OpRender
  OpRenderIt
  OpRenderEach
  OpShow
  OpHide
}

///|
fn XOp::from_name(name : String) -> XOp? {
  match name {
    "slot" => Some(OpSlot)
    "text" => Some(OpText)
    "render" => Some(OpRender)
    "render-it" => Some(OpRenderIt)
    "render-each" => Some(OpRenderEach)
    "show" => Some(OpShow)
    "hide" => Some(OpHide)
    _ => None
  }
}

///|
/// Attr names the op handles itself (skipped by process_x_extras). The bare
/// when/loop-with spellings on render-each are TEMPORARY (deprecated, see
/// BareXDirective).
fn XOp::consumed(self : XOp, name : String) -> Bool {
  match self {
    OpRender | OpRenderIt => name == "as"
    OpRenderEach =>
      name is ("as" | "when" | "loop-with" | "@when" | "@loop-with")
    _ => false
  }
}

///|
fn XOp::wrappable(self : XOp) -> Bool {
  self is (OpText | OpRender | OpRenderIt | OpRenderEach)
}

///|
fn XOp::ignores_children(self : XOp) -> Bool {
  self is (OpText | OpRender | OpRenderIt | OpRenderEach)
}

///|
/// Ops usable as wrapper attrs on other <x> ops (JS X_OPS[..].wrapper).
fn xop_wrapper_kind(name : String) -> WrapperKind? {
  match name {
    "show" => Some(Show)
    "hide" => Some(Hide)
    _ => None
  }
}

///|
/// A child an <x> op may carry even when it ignores its body: comments and
/// insignificant whitespace (childs are not yet condensed here).
fn is_ignorable_x_child(c : ANode) -> Bool {
  c is Comment(_) || c.is_whitespace()
}

///|
fn has_meaningful_childs(childs : Array[ANode]) -> Bool {
  childs.iter().any(c => !is_ignorable_x_child(c))
}

///|
fn parse_x_op_val(
  op_name : String,
  value : String,
  px : ParseContext,
  parser : (String, @tutuca.ParseCtx) -> @tutuca.Val?,
) -> @tutuca.Val? {
  let val = px.pval(value, parser)
  if val is None {
    px.issue(BadValue(role=XOp(op=op_name), value~))
  }
  val
}

///|
/// `as=` view selector: a dynamic text value like `@push-view`, but a bare
/// identifier (which parses as a NameVal outside the text grammar and so
/// yields None) falls back to a literal const view name for backward compat.
fn parse_view_name(s : String, px : ParseContext) -> @tutuca.Val {
  px.pval(s, @tutuca.parse_text).unwrap_or(Const(lit=LStr(s), from_macro=false))
}

///|
fn parse_x_op(
  attrs : Array[(String, String)],
  childs : Array[ANode],
  op_idx : Int,
  px : ParseContext,
) -> ANode? {
  // `<X>` with no attrs or a bare `@x` with no op attr: plain fragment.
  if attrs.length() <= op_idx {
    return Some(maybe_fragment(childs))
  }
  let (name, value) = attrs[op_idx]
  let op = XOp::from_name(name)
  if op is Some(o) && o.ignores_children() && has_meaningful_childs(childs) {
    px.issue(XOpIgnoresChildren(op=name))
  }
  let as_val : @tutuca.Val? = match get_named_item(attrs, "as") {
    Some(s) => Some(parse_view_name(s, px))
    None => None
  }
  let node : ANode? = match op {
    Some(OpSlot) => Some(Slot({ name: value, node: maybe_fragment(childs) }))
    Some(OpText) =>
      px.add_node_if(parse_x_op_val(name, value, px, @tutuca.parse_text), (
        id,
        val,
      ) => RenderText({ node_id: Some(id), val }))
    Some(OpRender) =>
      px.add_node_if(parse_x_op_val(name, value, px, @tutuca.parse_component), (
        id,
        val,
      ) => Render({ node_id: id, val, view_val: as_val }))
    Some(OpRenderIt) =>
      Some(px.add_node(id => RenderIt({ node_id: id, view_val: as_val })))
    Some(OpRenderEach) => parse_render_each(px, value, as_val, attrs)
    Some(OpShow) =>
      px.add_node_if(parse_x_op_val(name, value, px, @tutuca.parse_bool), (
        id,
        val,
      ) => Show({ node_id: Some(id), val, node: maybe_fragment(childs) }))
    Some(OpHide) =>
      px.add_node_if(parse_x_op_val(name, value, px, @tutuca.parse_bool), (
        id,
        val,
      ) => Hide({ node_id: Some(id), val, node: maybe_fragment(childs) }))
    None => {
      px.issue(UnknownXOp(name~, value~))
      return Some(
        Comment({ val: "Error: InvalidSpecialTagOp \{name}=\{value}" }),
      )
    }
  }
  process_x_extras(node, attrs, name, op.unwrap(), op_idx + 1, px)
}

///|
fn process_x_extras(
  node : ANode?,
  attrs : Array[(String, String)],
  op_name : String,
  op : XOp,
  start_idx : Int,
  px : ParseContext,
) -> ANode? {
  let wrappers : Array[(WrapperKind, @tutuca.Val?)] = []
  for i in start_idx..<attrs.length() {
    let (a_name, a_value) = attrs[i]
    if op.consumed(a_name) {
      continue
    }
    // `@show`/`@hide` directives — and their legacy bare spelling — wrap the
    // op's output node; the bare form gets a deprecation nudge.
    let at_prefixed = a_name is ['@', ..]
    let base_name = if at_prefixed { a_name[1:].to_owned() } else { a_name }
    let wrapper = if op.wrappable() {
      xop_wrapper_kind(base_name)
    } else {
      None
    }
    match wrapper {
      Some(kind) => {
        if !at_prefixed {
          px.handler.on_deprecated_syntax(
            BareXDirective(op=op_name, name=base_name),
            px.current_tag,
          )
        }
        // Surface a bad-value issue when the wrapper's bool fails to parse, so
        // the wrapper being dropped below (add_node_if → None) is not silent —
        // matching the regular directive path (AttrParser::directive_value).
        // JS drops these silently (anode.js:274 parseBool doesn't report, the
        // TODO at anode.js:317 acknowledges it); the port surfaces it instead.
        let wrapper_val = px.pval(a_value, @tutuca.parse_bool)
        if wrapper_val is None {
          px.issue(BadValue(role=Directive(name=base_name), value=a_value))
        }
        wrappers.push((kind, wrapper_val))
      }
      None => px.issue(UnknownXAttr(op=op_name, name=a_name, value=a_value))
    }
  }
  // Divergence: JS would wrap even a null op node (rendering later crashes);
  // here a failed op stays None after its extras reported their issues.
  guard node is Some(inner) else { return None }
  let mut result = inner
  for i = wrappers.length() - 1; i >= 0; i = i - 1 {
    let (kind, val) = wrappers[i]
    let wrapper = px.add_node_if(val, (id, v) => {
      match kind {
        Show => Show({ node_id: Some(id), val: v, node: empty_node() })
        _ => Hide({ node_id: Some(id), val: v, node: empty_node() })
      }
    })
    if wrapper is Some(w) {
      w.wrap_node(result)
      result = w
    }
  }
  Some(result)
}

///|
/// `<x render-each="seq">` is sugar for `@each="seq"` wrapping `<x render-it>`
/// so there is exactly one iteration mechanism (JS parseRenderEach).
/// `@when`/`@loop-with` are read through the directive parser and lifted onto
/// the EachNode's iter_info.
fn parse_render_each(
  px : ParseContext,
  value : String,
  as_val : @tutuca.Val?,
  attrs : Array[(String, String)],
) -> ANode? {
  let seq_val = parse_x_op_val("render-each", value, px, @tutuca.parse_sequence)
  guard seq_val is Some(_) else { return None }
  let render_it = px.add_node(id => RenderIt({ node_id: id, view_val: as_val }))
  let attr_parser = AttrParser::new(px)
  let each_attr = attr_parser.push_wrapper(Each, value, seq_val)
  attr_parser.each_attr = Some(each_attr)
  // an `@`-prefixed or bare render-each directive attribute; the bare form
  // works but gets a deprecation nudge
  fn directive_attr(name : String, parse : (String) -> Unit) {
    let pair : (String, String)? = match get_named_item(attrs, "@" + name) {
      Some(v) => Some(("@" + name, v))
      None =>
        match get_named_item(attrs, name) {
          Some(v) => Some((name, v))
          None => None
        }
    }
    match pair {
      Some((a_name, a_value)) => {
        if !(a_name is ['@', ..]) {
          px.handler.on_deprecated_syntax(
            BareXDirective(op="render-each", name~),
            px.current_tag,
          )
        }
        parse(a_value)
      }
      None => ()
    }
  }

  directive_attr("when", v => attr_parser.parse_when(v))
  directive_attr("loop-with", v => attr_parser.parse_loop_with(v))
  px.add_node_if(seq_val, (id, val) => {
    Each({
      node_id: id,
      iter_info: {
        val,
        when_val: each_attr.when_val,
        loop_with_val: each_attr.loop_with_val,
        enrich_with_val: None,
      },
      node: render_it,
      // Marker so the linter checks this Each's @when/@loop-with in the node
      // loop — render-each sugar has no wrapper-attr record to check instead.
      from_render_each: true,
    })
  })
}
