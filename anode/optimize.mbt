// Constant-subtree caching markers (src/anode.js optimizeChilds /
// optimizeNode / per-class optimize methods). Parse-only: RenderOnce is a
// plain marker wrapper; the render-result memoization lives with the renderer.

///|
/// Process-global RenderOnce marker id source (JS uses the RenderOnceNode
/// instance identity; the port keys the renderer's cache on this int).
let render_once_id_counter : Ref[Int] = { val: 0 }

///|
fn next_render_once_id() -> Int {
  render_once_id_counter.val = render_once_id_counter.val + 1
  render_once_id_counter.val
}

///|
/// Process-global attribute-memo id source. Separate counter from the
/// RenderOnce one only so each reads as its own sequence in a debug dump;
/// they are both "an int the renderer keys a per-app cache on".
let attrs_id_counter : Ref[Int] = { val: 0 }

///|
/// Mint this element's attribute memo key, if its attributes are constant.
///
/// A `RenderOnce`-wrapped subtree is never reached by `optimize` — the whole
/// subtree's rendered Vdom is memoized instead, which subsumes this. So the
/// elements that get an id are exactly the ones inside a DYNAMIC subtree with
/// static attributes: `<li class="row"><x text=".name"></x></li>`, the shape
/// of every list row.
fn mint_attrs_id(d : DomData) -> Unit {
  if d.attrs is ConstAttrs(_) && d.attrs_id == 0 {
    attrs_id_counter.val = attrs_id_counter.val + 1
    d.attrs_id = attrs_id_counter.val
  }
}

///|
fn optimize_childs(childs : Array[ANode]) -> Unit {
  for i in 0..<childs.length() {
    let child = childs[i]
    if child.is_constant() {
      childs[i] = RenderOnce({ node: child, id: next_render_once_id() })
    } else {
      child.optimize()
    }
  }
}

///|
pub fn optimize_node(node : ANode) -> ANode {
  if node.is_constant() {
    return RenderOnce({ node, id: next_render_once_id() })
  }
  node.optimize()
  node
}

///|
fn ANode::optimize(self : ANode) -> Unit {
  match self {
    Dom(d) => {
      mint_attrs_id(d)
      optimize_childs(d.childs)
    }
    Fragment(d) => optimize_childs(d.childs)
    Show(d) | Hide(d) | PushView(d) | Scope(d) => d.node = optimize_node(d.node)
    // JS SlotNode.optimize only recurses; it never wraps its own node.
    Slot(d) => d.node.optimize()
    Each(d) => d.node = optimize_node(d.node)
    MacroCall(d) =>
      match d.node {
        Some(n) => d.node = Some(optimize_node(n))
        None => ()
      }
    Text(_)
    | Comment(_)
    | RenderText(_)
    | Render(_)
    | RenderIt(_)
    | RenderOnce(_) => ()
  }
}
