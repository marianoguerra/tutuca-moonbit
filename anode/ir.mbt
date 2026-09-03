// Loading an ahead-of-time compiled view (viewgen / `tutuca gen`).
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
/// needed.
fn collect_registered(node : ANode, into : Array[ANode?]) -> Unit {
  fn put(id : Int) {
    while into.length() <= id {
      into.push(None)
    }
    into[id] = Some(node)
  }

  match node {
    RenderText(d) =>
      match d.node_id {
        Some(id) => put(id)
        None => ()
      }
    Render(d) => put(d.node_id)
    RenderIt(d) => put(d.node_id)
    Show(d) | Hide(d) | PushView(d) | Scope(d) =>
      match d.node_id {
        Some(id) => put(id)
        None => ()
      }
    Each(d) => put(d.node_id)
    Text(_) | Comment(_) | Dom(_) | Fragment(_) | Slot(_) | MacroCall(_) => ()
  }
  node.for_each_child(child => collect_registered(child, into))
}

///|
/// Rebuild the compile context of an ahead-of-time compiled view: `nodes` is
/// recovered from `root`, `events` is the generator's table in registration
/// order (its positions ARE the ids elements carry in `data-eid`).
fn ParseContext::from_ir(
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
      None => Fragment({ childs: [], })
    }
  })
  {
    nodes,
    events,
    macro_nodes: [],
    parent: None,
    frame: None,
    // Nothing left to resolve: an ahead-of-time tree was parsed by the
    // generator, so every `host.name` in it is already the literal it became.
    config_vars: Map([]),
    val_ctx: None,
    current_tag: None,
    handler: WarnHandler::{ },
  }
}

///|
/// The event table as the generator writes it: one handler list per element
/// that registered any, IN registration order. `register_events` hands out
/// `id = events.length()`, so a NodeEvents id IS its position — emitting the
/// ids would only be a chance to disagree with the array.
pub fn events_of(handlers : Array[Array[NodeEvent]]) -> Array[NodeEvents] {
  handlers.mapi((id, handlers) => { id, handlers, })
}

///|
/// A view whose tree was compiled ahead of time. Everything `View::compile`
/// would do EXCEPT stamping the component id happens here — the data-vid
/// stamp — because that depends only on the view, while data-cid depends on
/// which component instance adopts it.
///
/// `compile` on such a view therefore only stamps data-cid, and is idempotent.
pub fn View::from_ir(
  name : String,
  root : ANode,
  handlers : Array[Array[NodeEvent]],
  style? : String = "",
) -> View {
  let ctx = ParseContext::from_ir(root, events_of(handlers))
  root.set_data_attr("data-vid", LStr(name))
  {
    name,
    raw_view: "",
    style,
    config_vars: Map([]),
    anode: Some(root),
    ctx: Some(ctx),
    parse: None,
  }
}
