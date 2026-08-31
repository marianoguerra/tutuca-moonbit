// Builders for the AST: hyperscript-shaped constructors over the pub(all)
// node types, with every rarely-set field as an optional argument. They add no
// representation of their own — each one returns exactly the value the parser
// builds for the same markup, which is what lets `tutuca gen-views` emit
// `h("div", [attr("class", "x")], [text("hi")])` instead of the full struct
// literal, and what lets a test write a tree by hand and compare it to a
// parsed one.
//
// See spec.mbt for the contracts.

// ---------------------------------------------------------------------------
// Constant values

///|
pub fn const_str(s : String) -> @tutuca.Val {
  Const(lit=LStr(s), from_macro=false)
}

///|
pub fn const_num(n : Double) -> @tutuca.Val {
  Const(lit=LNum(n), from_macro=false)
}

///|
pub fn const_bool(b : Bool) -> @tutuca.Val {
  Const(lit=LBool(b), from_macro=false)
}

///|
pub fn const_null() -> @tutuca.Val {
  Const(lit=LNull, from_macro=false)
}

// ---------------------------------------------------------------------------
// Attributes

///|
pub fn attr(name : String, value : String) -> AttrItem {
  ConstA(name~, val=const_str(value))
}

///|
pub fn attr_num(name : String, value : Double) -> AttrItem {
  ConstA(name~, val=const_num(value))
}

///|
pub fn attr_bool(name : String, value : Bool) -> AttrItem {
  ConstA(name~, val=const_bool(value))
}

///|
pub fn attr_val(name : String, val : @tutuca.Val) -> AttrItem {
  ConstA(name~, val~)
}

///|
pub fn eid(id : Int) -> AttrItem {
  attr_num("data-eid", id.to_double())
}

///|
pub fn dyn_attr(name : String, val : @tutuca.Val) -> AttrItem {
  Plain(name~, val~)
}

///|
pub fn if_attr(
  name : String,
  cond : @tutuca.Val,
  then_val? : @tutuca.Val,
  else_val? : @tutuca.Val,
) -> AttrItem {
  If({ name, cond_val: cond, then_val, else_val, })
}

///|
pub fn raw_html(val? : @tutuca.Val) -> AttrItem {
  RawHtml(val~)
}

///|
pub fn set_inner_md(val? : @tutuca.Val) -> AttrItem {
  RawMarkdown(val~)
}

///|
pub fn set_inner_html(val? : @tutuca.Val) -> AttrItem {
  SafeHtml(val~)
}

///|
pub fn set_inner_svg(val? : @tutuca.Val) -> AttrItem {
  SafeSvg(val~)
}

// ---------------------------------------------------------------------------
// Nodes

///|
pub fn h(
  tag : String,
  attrs : Array[AttrItem],
  childs : Array[ANode],
  ns? : Ns,
) -> ANode {
  Dom({
    tag,
    attrs: attrs_of_items(attrs),
    childs,
    ns,
    sink_hints: None,
    bind: None,
  })
}

///|
pub fn text(val : String) -> ANode {
  Text({ val, })
}

///|
pub fn comment(val : String) -> ANode {
  Comment({ val, })
}

///|
pub fn frag(childs : Array[ANode]) -> ANode {
  Fragment({ childs, })
}

///|
pub fn dyn_text(val : @tutuca.Val, id? : Int) -> ANode {
  RenderText({ node_id: id, val, })
}

///|
pub fn render(id : Int, val : @tutuca.Val, view? : @tutuca.Val) -> ANode {
  Render({ node_id: id, val, view_val: view, })
}

///|
pub fn render_it(id : Int, view? : @tutuca.Val) -> ANode {
  RenderIt({ node_id: id, view_val: view, })
}

///|
pub fn show(val : @tutuca.Val, node : ANode, id? : Int) -> ANode {
  Show({ node_id: id, val, node, })
}

///|
pub fn hide(val : @tutuca.Val, node : ANode, id? : Int) -> ANode {
  Hide({ node_id: id, val, node, })
}

///|
pub fn push_view(val : @tutuca.Val, node : ANode, id? : Int) -> ANode {
  PushView({ node_id: id, val, node, })
}

///|
pub fn scope(id : Int, val : @tutuca.Val, node : ANode) -> ANode {
  Scope({ node_id: Some(id), val, node, })
}

///|
pub fn slot(name : String, node : ANode) -> ANode {
  Slot({ name, node, })
}

///|
pub fn each(
  id : Int,
  val : @tutuca.Val,
  node : ANode,
  when_val? : @tutuca.Val,
  loop_with_val? : @tutuca.Val,
  enrich_with_val? : @tutuca.Val,
  from_render_each? : Bool = false,
) -> ANode {
  Each({
    node_id: id,
    iter_info: { val, when_val, loop_with_val, enrich_with_val, },
    node,
    from_render_each,
  })
}

// ---------------------------------------------------------------------------
// Events

///|
pub fn on(
  name : String,
  handler : @tutuca.Val,
  args? : Array[@tutuca.Val] = [],
  modifiers? : Array[String] = [],
  binding? : BindCoercion,
  action? : @tscript.PropertyAction,
) -> NodeEvent {
  { name, handler: { handler, args, action, }, modifiers, binding, }
}

///|
/// Build an event action that assigns a component property. Kept in `anode`
/// so generated view modules need no direct dependency on the script parser.
pub fn set_property_action(
  name : String,
  value : @tutuca.Val,
) -> @tscript.PropertyAction {
  PropertySet(name~, value~)
}

///|
pub fn reset_property_action(name : String) -> @tscript.PropertyAction {
  PropertyReset(name)
}

///|
pub fn call_property_action(
  name : String,
  operation : String,
  args : Array[@tutuca.Val],
) -> @tscript.PropertyAction {
  PropertyCall(name~, operation~, args~)
}
