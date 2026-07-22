// Loading an ahead-of-time compiled view (viewgen / `tutuca gen-views`).
//
// The generator emits the ANode tree and the NodeEvents table as MoonBit
// literals; this is the seam that turns them back into the pair the renderer
// indexes — a View plus the ParseContext whose `nodes` / `events` arrays the
// boundary lookups address by id (render/components_impl.mbt).
//
// `nodes` is NOT emitted: every registered node already carries its own
// node_id, so the array is recovered from the tree here rather than trusted
// from the generator, which removes a whole class of index-drift bugs.
// `events` has no home in the tree — elements reference it through their
// `data-eid` attribute — so that one IS emitted.

///|
/// Place every value-bearing node at its own node_id, growing `into` as
/// needed. RenderOnce ids belong to the renderer's memo table, not to this
/// array, so they are not collected (and cannot occur before optimization
/// anyway).
fn collect_registered(node : ANode, into : Array[ANode?]) -> Unit {
  fn put(id : Int) {
    while into.length() <= id {
      into.push(None)
    }
    into[id] = Some(node)
  }

  match node {
    Text(_) | Comment(_) => ()
    Dom(d) =>
      for c in d.childs {
        collect_registered(c, into)
      }
    Fragment(d) =>
      for c in d.childs {
        collect_registered(c, into)
      }
    RenderText(d) =>
      match d.node_id {
        Some(id) => put(id)
        None => ()
      }
    Render(d) => put(d.node_id)
    RenderIt(d) => put(d.node_id)
    Show(d) | Hide(d) | PushView(d) | Scope(d) => {
      match d.node_id {
        Some(id) => put(id)
        None => ()
      }
      collect_registered(d.node, into)
    }
    Slot(d) => collect_registered(d.node, into)
    Each(d) => {
      put(d.node_id)
      collect_registered(d.node, into)
    }
    MacroCall(d) =>
      match d.node {
        Some(n) => collect_registered(n, into)
        None => ()
      }
    RenderOnce(d) => collect_registered(d.node, into)
  }
}

///|
/// Rebuild the compile context of an ahead-of-time compiled view: `nodes` is
/// recovered from `root`, `events` is the generator's table in registration
/// order (its positions ARE the ids elements carry in `data-eid`).
///
/// Call before the tree is optimized — `View::from_ir` does.
pub fn ParseContext::from_ir(
  root : ANode,
  events : Array[NodeEvents],
) -> ParseContext {
  let slots : Array[ANode?] = []
  collect_registered(root, slots)
  // A gap would mean the generator dropped a node the renderer may still
  // address; a Fragment is inert in every position a node is looked up for.
  let nodes = slots.map(s => {
    match s {
      Some(n) => n
      None => Fragment({ childs: [] })
    }
  })
  {
    nodes,
    events,
    macro_nodes: [],
    parent: None,
    frame: None,
    val_ctx: None,
    current_tag: None,
    cache_const_nodes: true,
    handler: WarnHandler::{  },
  }
}

///|
/// A view whose tree was compiled ahead of time. Everything `View::compile`
/// would do EXCEPT stamping the component id happens here — the data-vid
/// stamp and the constant-subtree optimization — because those depend only on
/// the view, while data-cid depends on which component instance adopts it.
///
/// `compile` on such a view therefore only stamps data-cid, and is idempotent.
pub fn View::from_ir(
  name : String,
  root : ANode,
  ctx : ParseContext,
  style? : String = "",
) -> View {
  root.set_data_attr("data-vid", LStr(name))
  let anode = if ctx.cache_const_nodes { optimize_node(root) } else { root }
  { name, raw_view: "", style, anode: Some(anode), ctx: Some(ctx), ir: true }
}
