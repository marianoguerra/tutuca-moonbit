// View (src/anode.js View, parse side only — render is out of scope).

///|
pub fn View::new(
  name : String,
  raw_view? : String = "No View Defined",
  style? : String = "",
) -> View {
  { name, raw_view, style, anode: None, ctx: None, ir: false }
}

///|
pub fn View::compile(
  self : View,
  ctx : ParseContext,
  scope : &MacroScope,
  cid? : @tutuca.Lit,
) -> Unit raise MacroError {
  // Ahead-of-time compiled (View::from_ir): the tree, its registration
  // context, the data-vid stamp and the optimization all already exist. Only
  // the adopting component's id is left, which makes this idempotent.
  if self.ir {
    if cid is Some(c) && self.anode is Some(node) {
      node.set_data_attr("data-cid", c)
    }
    return
  }
  self.ctx = Some(ctx)
  let anode = ANode::parse(self.raw_view, ctx)
  self.anode = anode
  guard anode is Some(node) else { return }
  if cid is Some(c) {
    node.set_data_attr("data-cid", c)
  }
  node.set_data_attr("data-vid", LStr(self.name))
  ctx.compile(scope)
  if ctx.cache_const_nodes {
    self.anode = Some(optimize_node(node))
  }
}
