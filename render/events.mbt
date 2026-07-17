// Event-path reconstruction (JS Path.fromNodeAndEventName in src/path.js):
// walk up from the event target collecting data-eid stamps and §…§ meta
// chains, cross component boundaries, resolve one addressing/frame step per
// crossed component, and find the handlers for the event name. Dynamic-var
// render targets (DynStep/DynEachStep + pendingDyns) ARE handled here: a
// `<x render="*dyn">` teleports the transaction to where the value really
// lives (see app/teleport_test.mbt and examples/dynamic.mbt).

///|
/// One `{nid, si?/sk?}` entry collected between two component boundaries
/// (from Comp/Each/Scope metas), innermost-first.
priv struct NodeRef {
  nid : Int?
  key : @tutuca.PathKey?
}

///|
/// Events whose handlers bubble across component boundaries to ancestors.
fn event_bubbles(event_name : String) -> Bool {
  event_name == "drop"
}

///|
fn parse_int_attr(s : String) -> Int? {
  let n : Int = @strconv.from_str(s) catch { _ => return None }
  Some(n)
}

///|
fn find_handlers(
  comps : &Boundaries,
  cid : Int,
  vid : String,
  event_ids : Array[Int],
  event_name : String,
) -> Array[@anode.NodeEvent]? {
  for eid in event_ids {
    match comps.events_for(cid, vid, eid) {
      Some(ne) => {
        let matched = ne.handlers.filter(h => h.name == event_name)
        if !matched.is_empty() {
          return Some(matched)
        }
      }
      None => ()
    }
  }
  None
}

///|
/// The base ANode.toPathStep: the node's value as a path item, keyed by the
/// meta's si/sk when present.
fn base_step(val : @tutuca.Val, key : @tutuca.PathKey?) -> @tutuca.Step? {
  match val.to_path_item() {
    Some(step) =>
      Some(
        match key {
          Some(k) => @tutuca.step_with_key(step, k)
          None => step
        },
      )
    None => None
  }
}

///|
fn plain_of(step : @tutuca.Step?, cid : Int) -> @tutuca.DispatchStep? {
  match step {
    Some(s) => Some(Plain(step=s, origin=Some(cid)))
    None => None
  }
}

///|
/// Resolve the dispatch item one collected NodeRef contributes (JS
/// StepCtx.resolveNode().toPathStep(ctx)). Dynamic render targets produce
/// Dyn/DynEach markers whose `interior` arrays start empty — the caller
/// seeds and grows them while walking (JS pendingDyns).
fn ref_step(
  comps : &Boundaries,
  cid : Int,
  vid : String,
  refs : Array[NodeRef],
  i : Int,
) -> @tutuca.DispatchStep? {
  guard refs[i].nid is Some(nid) else { return None } // root Comp meta: no render site
  guard comps.node_for(cid, vid, nid) is Some(anode) else { return None }
  match anode {
    // `<x render-it>` pairs its keyless Comp meta with the NEXT entry, which
    // must be the enclosing @each's keyed Each meta (JS RenderItNode).
    RenderIt(_) => {
      guard i + 1 < refs.length() &&
        refs[i + 1].key is Some(key) &&
        refs[i + 1].nid is Some(each_nid) else {
        return None
      }
      guard comps.node_for(cid, vid, each_nid) is Some(Each(ed)) else {
        return None
      }
      match ed.iter_info.val {
        Field(f) => plain_of(Some(EachRenderItStep(field=f, key~)), cid)
        // iterated dynamic target: the item lives at the producer's seq field
        Dyn(name) =>
          match comps.dyn_producer(cid, name) {
            Some(dp) =>
              Some(
                DynEach(producer=dp.producer, steps=dp.steps, interior=[], key~),
              )
            None => None
          }
        _ => None
      }
    }
    Render(d) =>
      match d.val {
        // dynamic render target: the data lives at the producer
        Dyn(name) =>
          match comps.dyn_producer(cid, name) {
            Some(dp) =>
              Some(Dyn(producer=dp.producer, steps=dp.steps, interior=[]))
            None => None
          }
        _ => plain_of(base_step(d.val, refs[i].key), cid)
      }
    RenderText(d) => plain_of(base_step(d.val, refs[i].key), cid)
    Show(w) | Hide(w) => plain_of(base_step(w.val, refs[i].key), cid)
    Scope(w) => plain_of(Some(ScopeBindStep(val=w.val)), cid)
    Each(ed) =>
      match refs[i].key {
        Some(key) =>
          plain_of(
            Some(
              EachBindStep(
                val=ed.iter_info.val,
                when_val=ed.iter_info.when_val,
                enrich_with_val=ed.iter_info.enrich_with_val,
                loop_with_val=ed.iter_info.loop_with_val,
                key~,
              ),
            ),
            cid,
          )
        None => None
      }
    _ => None
  }
}

///|
fn resolve_path_step(
  comps : &Boundaries,
  cid : Int,
  vid : String,
  refs : Array[NodeRef],
) -> @tutuca.DispatchStep? {
  for i in 0..<refs.length() {
    match ref_step(comps, cid, vid, refs, i) {
      Some(s) => return Some(s)
      None => ()
    }
  }
  None
}

///|
pub fn[N : @vdom.DomWalk] from_node_and_event_name(
  node : N,
  event_name : String,
  root_node : N,
  comps : &Boundaries,
  max_depth? : Int = 1000000,
  stop_on_no_event? : Bool = true,
) -> EventDispatch? {
  let items : Array[@tutuca.DispatchStep] = [] // leaf→root, reversed at the end
  let bubbles = event_bubbles(event_name)
  let event_ids : Array[Int] = []
  let refs : Array[NodeRef] = []
  // Dyn markers still walking up toward their producer (JS pendingDyns):
  // (producer cid, the SAME interior array stored inside the pushed marker —
  // mutations are visible through it).
  let pending : Array[(Int, Array[Int])] = []
  let mut handlers : Array[@anode.NodeEvent]? = None
  let mut is_leaf_component = true
  // Cross one component boundary: resolve the handlers (once) and the path
  // step that leaves this component. Returns false to signal "no handler on
  // the leaf component" — the caller aborts (JS NO_EVENT_INFO).
  fn cross_component(cid : Int, vid : String) -> Bool {
    let mut push_step = true
    if handlers is None && (is_leaf_component || bubbles) {
      match find_handlers(comps, cid, vid, event_ids, event_name) {
        None =>
          if is_leaf_component && stop_on_no_event && !bubbles {
            return false
          }
        Some(h) => {
          handlers = Some(h)
          if !is_leaf_component {
            // handler bubbled up to an ancestor component: the returned path
            // must resolve to that component's value, so drop the steps that
            // descend below it
            items.clear()
            pending.clear()
            push_step = false
          }
        }
      }
    }
    is_leaf_component = false
    // every crossing is interior to the still-pending teleports — including
    // the producer's own (its render-site step must be rewound too)
    for p in pending {
      p.1.push(cid)
    }
    if push_step {
      match resolve_path_step(comps, cid, vid, refs) {
        Some(item) => {
          items.push(item)
          match item {
            Dyn(producer~, interior~, ..) | DynEach(producer~, interior~, ..) => {
              interior.push(cid) // seed with the consumer cid
              pending.push((producer, interior))
            }
            _ => ()
          }
        }
        None => ()
      }
    }
    // reached a producer: its teleport stops accumulating
    for i = pending.length() - 1; i >= 0; i = i - 1 {
      if pending[i].0 == cid {
        let _ = pending.remove(i)
      }
    }
    event_ids.clear()
    refs.clear()
    true
  }

  let mut cur = node
  let mut depth = 0
  while !cur.is_same_node(root_node) && depth < max_depth {
    if cur.node_kind() == 1 {
      match cur.attribute("data-eid") {
        Some(s) =>
          match parse_int_attr(s) {
            Some(eid) => event_ids.push(eid)
            None => ()
          }
        None => ()
      }
      // Meta comments before the element, innermost-first. A non-§ comment
      // ends the chain; a malformed § meta is skipped (JS warns + skips).
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
            if !cross_component(cid, vid) {
              return None
            }
            refs.push({ nid, key: None })
          }
          Some(Each(nid~, key~)) =>
            refs.push({ nid: Some(nid), key: Some(key) })
          Some(Scope(nid~)) => refs.push({ nid: Some(nid), key: None })
          None => ()
        }
        sib = m.prev_sibling()
      }
      // A fragment-rooted component stamps data-cid on every child but emits
      // a single Comp meta before the first; later children carry the
      // boundary only on the element itself.
      if !saw_comp && cur.attribute("data-cid") is Some(cid_s) {
        match parse_int_attr(cid_s) {
          Some(cid) => {
            let vid = cur.attribute("data-vid").unwrap_or("main")
            if !cross_component(cid, vid) {
              return None
            }
          }
          None => ()
        }
      }
    }
    depth += 1
    match cur.parent_node() {
      Some(p) => cur = p
      None => break
    }
  }
  items.rev_in_place()
  Some({
    path: @tutuca.DispatchPath::new(items~),
    handlers: handlers.unwrap_or([]),
  })
}
