// View (src/anode.js View, parse side only — render is out of scope).

///|
/// A view from SOURCE, parsed when `compile` runs.
///
/// This is the only function in the package that names `ANode::parse`, which
/// is what lets a program that never builds a view from source drop the whole
/// parse subtree — the HTML tokenizer included. See `View.parse`.
pub fn View::new(
  name : String,
  raw_view? : String = "No View Defined",
  style? : String = "",
  config_vars? : Map[String, String],
) -> View {
  {
    name,
    raw_view,
    style,
    config_vars: config_vars.unwrap_or(Map([])),
    anode: None,
    ctx: None,
    parse: Some(parse_source),
  }
}

///|
/// The parse step `View::new` installs.
fn parse_source(
  v : View,
  ctx : ParseContext,
  scope : &MacroScope,
  cid : @tutuca.Lit?,
) -> Unit raise MacroError {
  v.ctx = Some(ctx)
  // Before the parse rather than at construction: the context is the caller's
  // (`Component::compile` builds one per component), and this is the only
  // moment both it and the view are in hand.
  if !v.config_vars.is_empty() {
    ctx.config_vars = v.config_vars
  }
  let anode = ANode::parse(v.raw_view, ctx)
  v.anode = anode
  guard anode is Some(node) else { return }
  if cid is Some(c) {
    node.set_data_attr("data-cid", c)
  }
  node.set_data_attr("data-vid", LStr(v.name))
  ctx.compile(scope)
}

///|
pub fn View::compile(
  self : View,
  ctx : ParseContext,
  scope : &MacroScope,
  cid? : @tutuca.Lit,
) -> Unit raise MacroError {
  match self.parse {
    // Ahead-of-time compiled (View::from_ir): the tree, its registration
    // context, the data-vid stamp and the optimization all already exist. Only
    // the adopting component's id is left, which makes this idempotent.
    None =>
      if cid is Some(c) && self.anode is Some(node) {
        node.set_data_attr("data-cid", c)
      }
    Some(f) => f(self, ctx, scope, cid)
  }
}
