// Which component is under this element.
//
// `from_node_and_event_name` answers "where would a click go", and that is a
// different question from "what is this": it stops at the first component with
// a handler for the event, and it CLEARS the steps it collected when a handler
// bubbles, because a dispatch has to resolve to the component that will run it.
//
// What a picker wants is the whole ancestry, handlers or no handlers — the
// chain of components from the root down to the thing somebody clicked, so it
// can offer each of them as somewhere to cut a recording down to. Same DOM
// markers, same walk, no handler resolution at all.

///|
/// One component the walk crossed, outermost first.
pub(all) struct Crossing {
  /// The component's id, as the renderer stamped it. A PROCESS-GLOBAL counter,
  /// so it means something now and nothing tomorrow — for showing a name and
  /// for looking one up in the registry that is running, never for storing.
  cid : Int
  /// The view it was rendered through.
  vid : String
  /// Where this component sits, from the root.
  path : @tutuca.DispatchPath
} derive(Eq, @debug.Debug)

///|
/// The component ancestry under `node`, outermost first.
///
/// Empty when the node is outside the app, or when nothing between it and the
/// root carries a component marker — which is a real answer and not a failure:
/// a click on the page's own chrome is a click on nothing the app rendered.
///
/// Each entry carries the path to the component ITSELF, so the last one is the
/// innermost component containing the node.
pub fn[N : @vdom.DomWalk] components_at(
  node : N,
  root_node : N,
  comps : &Boundaries,
  max_depth? : Int = 1000000,
) -> Array[Crossing] {
  // leaf→root while walking, reversed at the end — the same shape the event
  // walk uses, for the same reason: the DOM is walked upward and a path reads
  // downward.
  let items : Array[@tutuca.DispatchStep] = []
  let refs : Array[NodeRef] = []
  let pending : Array[(Int, Array[Int])] = []
  let crossings : Array[(Int, String, Int)] = []
  fn cross(cid : Int, vid : String) -> Unit {
    for p in pending {
      p.1.push(cid)
    }
    match resolve_path_step(comps, cid, vid, refs) {
      Some(item) => {
        items.push(item)
        match item {
          Dyn(producer~, interior~, ..) => {
            interior.push(cid)
            pending.push((producer, interior))
          }
          _ => ()
        }
      }
      None => ()
    }
    for i = pending.length() - 1; i >= 0; i = i - 1 {
      if pending[i].0 == cid {
        let _ = pending.remove(i)
      }
    }
    // How many steps had been collected BELOW this component. A component's
    // own path is everything above it, which is everything collected after
    // this point — so the count is what turns a leaf→root list into one path
    // per crossing, once the walk is done.
    crossings.push((cid, vid, items.length()))
    refs.clear()
  }

  let mut cur = node
  let mut depth = 0
  while !@vdom.DomNode::is_same_node(cur, root_node) && depth < max_depth {
    if cur.node_kind() == 1 {
      let mut saw_comp = false
      let mut sib = cur.prev_sibling()
      while sib is Some(m) && m.node_kind() == 8 {
        let text = m.char_data()
        if !(text.length() > 0 && text[0] is '§') {
          break
        }
        match Meta::parse(text) {
          Some(Comp(nid~, cid~, vid~)) => {
            saw_comp = true
            cross(cid, vid)
            refs.push({ nid, key: None, })
          }
          Some(Each(nid~, key~)) =>
            refs.push({ nid: Some(nid), key: Some(key), })
          Some(Scope(nid~)) => refs.push({ nid: Some(nid), key: None, })
          None => ()
        }
        sib = m.prev_sibling()
      }
      // A fragment-rooted component stamps data-cid on every child and emits a
      // single Comp meta before the first, so a later child carries the
      // boundary only on the element.
      if !saw_comp && cur.attribute("data-cid") is Some(cid_s) {
        match parse_int_attr(cid_s) {
          Some(cid) => cross(cid, cur.attribute("data-vid").unwrap_or("main"))
          None => ()
        }
      }
    }
    depth += 1
    match @vdom.DomNode::parent_node(cur) {
      Some(p) => cur = p
      None => break
    }
  }
  // `items` is leaf→root; a component's own path is the steps ABOVE it,
  // reversed. `below` is how many were collected under it, so the rest is its
  // ancestry.
  let out : Array[Crossing] = []
  for c in crossings {
    let (cid, vid, below) = c
    let own = items[below:].to_owned()
    own.rev_in_place()
    out.push({ cid, vid, path: @tutuca.DispatchPath::new(items=own), })
  }
  out.rev_in_place()
  out
}
