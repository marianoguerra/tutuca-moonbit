// ParseContext implementation (src/anode.js ParseContext). Subclass hooks are
// the ParseHandler trait (spec.mbt); DOM plumbing (document/Text/Comment) is
// replaced by html_adapter.mbt.

///|
pub fn ParseContext::new(handler? : &ParseHandler) -> ParseContext {
  let h : &ParseHandler = match handler {
    Some(h) => h
    None => WarnHandler::{  }
  }
  {
    nodes: [],
    events: [],
    macro_nodes: [],
    parent: None,
    frame: None,
    val_ctx: None,
    current_tag: None,
    cache_const_nodes: true,
    handler: h,
  }
}

///|
pub fn ParseContext::enter_macro(
  self : ParseContext,
  name : String,
  vars : Map[String, String],
  slots : Map[String, ANode],
) -> ParseContext {
  {
    nodes: self.nodes,
    events: self.events,
    macro_nodes: self.macro_nodes,
    parent: Some(self),
    frame: Some({ macro_name: name, macro_vars: vars, macro_slots: slots }),
    val_ctx: None,
    current_tag: None,
    cache_const_nodes: true,
    handler: self.handler,
  }
}

///|
pub fn ParseContext::is_inside_macro(
  self : ParseContext,
  name : String,
) -> Bool {
  if self.frame is Some(f) && f.macro_name == name {
    return true
  }
  match self.parent {
    Some(p) => p.is_inside_macro(name)
    None => false
  }
}

///|
pub fn ParseContext::register_events(self : ParseContext) -> NodeEvents {
  let events = NodeEvents::{ id: self.events.length(), handlers: [] }
  self.events.push(events)
  events
}

///|
/// The value-layer parse context, created on first use with this frame's
/// macro vars.
fn ParseContext::value_ctx(self : ParseContext) -> @tutuca.ParseCtx {
  match self.val_ctx {
    Some(ctx) => ctx
    None => {
      let ctx = match self.frame {
        Some(f) => @tutuca.ParseCtx::new(macro_vars=f.macro_vars)
        None => @tutuca.ParseCtx::new()
      }
      self.val_ctx = Some(ctx)
      ctx
    }
  }
}

///|
/// Forward value-layer parse issues collected in val_ctx to the handler
/// (the JS value parsers call px.onParseIssue directly; the MoonBit value
/// layer records into ParseCtx.issues instead).
fn ParseContext::drain_value_issues(self : ParseContext) -> Unit {
  guard self.val_ctx is Some(ctx) else { return }
  for issue in ctx.issues {
    self.handler.on_parse_issue(
      BadValue(role=ValueIssue(issue.role), value=issue.value),
      self.current_tag,
    )
  }
  ctx.issues.clear()
}

///|
/// Run a value-layer parser and surface any issues it recorded.
fn ParseContext::pval(
  self : ParseContext,
  s : String,
  f : (String, @tutuca.ParseCtx) -> @tutuca.Val?,
) -> @tutuca.Val? {
  let r = f(s, self.value_ctx())
  self.drain_value_issues()
  r
}

///|
fn ParseContext::issue(self : ParseContext, issue : ParseIssue) -> Unit {
  self.handler.on_parse_issue(issue, self.current_tag)
}

///|
/// Register a node built from a successfully parsed value; None val means the
/// parse failed and no node is created (JS addNodeIf).
fn ParseContext::add_node_if(
  self : ParseContext,
  val : @tutuca.Val?,
  make : (Int, @tutuca.Val) -> ANode,
) -> ANode? {
  match val {
    Some(v) => {
      let node = make(self.nodes.length(), v)
      self.nodes.push(node)
      Some(node)
    }
    None => None
  }
}

///|
/// Register a node that carries no value (JS addNode; e.g. RenderItNode).
fn ParseContext::add_node(self : ParseContext, make : (Int) -> ANode) -> ANode {
  let node = make(self.nodes.length())
  self.nodes.push(node)
  node
}

///|
pub fn ParseContext::new_macro_node(
  self : ParseContext,
  name : String,
  m_attrs : Map[String, String],
  childs : Array[ANode],
) -> ANode {
  // The default slot's array is shared with the Fragment BEFORE filling, so
  // late pushes are visible through slots["_"] (matches the JS aliasing).
  let any_slot : Array[ANode] = []
  let slots : Map[String, ANode] = { "_": Fragment({ childs: any_slot }) }
  for child in childs {
    match child {
      Slot(d) => slots[d.name] = d.node
      _ => if !child.is_whitespace() { any_slot.push(child) }
    }
  }
  let node = ANode::MacroCall({
    name,
    attrs: m_attrs,
    slots,
    px: self,
    node: None,
    data_attrs: {},
  })
  self.macro_nodes.push(node)
  node
}

///|
pub fn ParseContext::compile(
  self : ParseContext,
  scope : &MacroScope,
) -> Unit raise MacroError {
  // macro_nodes grows while nested macros expand — no iterator here.
  let mut i = 0
  while i < self.macro_nodes.length() {
    match self.macro_nodes[i] {
      MacroCall(d) => macro_compile(d, scope)
      _ => ()
    }
    i = i + 1
  }
}
