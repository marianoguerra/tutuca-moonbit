// Event-path reconstruction: walk from an event target toward the app root,
// crossing component boundaries and collecting the continuation each render
// site recorded. Ordinary sites contribute one step to the active frame;
// resumed sites contribute an absolute base and therefore push a frame.

///|
priv struct NodeRef {
  nid : Int?
  key : @tutuca.PathKey?
  base : @tutuca.Path?
}

///|
priv enum PathPart {
  Item(@tutuca.DispatchStep)
  Frame(@tutuca.Path)
}

///|
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
fn item_part(step : @tutuca.Step?, cid : Int) -> PathPart? {
  match step {
    Some(s) => Some(Item(Plain(step=s, origin=Some(cid))))
    None => None
  }
}

///|
fn ref_part(
  comps : &Boundaries,
  cid : Int,
  vid : String,
  refs : Array[NodeRef],
  i : Int,
) -> PathPart? {
  match refs[i].base {
    Some(path) => return Some(Frame(path))
    None => ()
  }
  guard refs[i].nid is Some(nid) else { return None }
  guard comps.node_for(cid, vid, nid) is Some(anode) else { return None }
  match anode {
    RenderIt(_) => {
      guard i + 1 < refs.length() &&
        refs[i + 1].key is Some(key) &&
        refs[i + 1].nid is Some(each_nid) else {
        return None
      }
      guard comps.node_for(cid, vid, each_nid) is Some(Each(ed)) else {
        return None
      }
      match ed.iter_info.val.as_field() {
        Some(field) => item_part(Some(EachRenderItStep(field~, key~)), cid)
        None => None
      }
    }
    Render(d) =>
      match d.val {
        EDyn(..) => None
        _ => item_part(base_step(d.val, refs[i].key), cid)
      }
    RenderText(d) => item_part(base_step(d.val, refs[i].key), cid)
    Show(w) | Hide(w) => item_part(base_step(w.val, refs[i].key), cid)
    Scope(w) => item_part(Some(ScopeBindStep(val=w.val)), cid)
    Each(ed) =>
      match refs[i].key {
        Some(key) =>
          item_part(
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
fn resolve_path_part(
  comps : &Boundaries,
  cid : Int,
  vid : String,
  refs : Array[NodeRef],
) -> PathPart? {
  for i in 0..<refs.length() {
    match ref_part(comps, cid, vid, refs, i) {
      Some(part) => return Some(part)
      None => ()
    }
  }
  None
}

///|
fn path_of_parts(parts : Array[PathPart]) -> @tutuca.DispatchPath {
  let mut path = @tutuca.DispatchPath::new()
  for part in parts {
    path = match part {
      Item(item) => path.push_item(item)
      Frame(base) => path.push_frame(base)
    }
  }
  path
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
  let parts : Array[PathPart] = []
  let bubbles = event_bubbles(event_name)
  let event_ids : Array[Int] = []
  let refs : Array[NodeRef] = []
  let mut handlers : Array[@anode.NodeEvent]? = None
  let mut is_leaf_component = true

  fn cross_component(cid : Int, vid : String) -> Bool {
    let mut push_part = true
    if handlers is None && (is_leaf_component || bubbles) {
      match find_handlers(comps, cid, vid, event_ids, event_name) {
        None =>
          if is_leaf_component && stop_on_no_event && !bubbles {
            return false
          }
        Some(h) => {
          handlers = Some(h)
          if !is_leaf_component {
            parts.clear()
            push_part = false
          }
        }
      }
    }
    is_leaf_component = false
    if push_part {
      match resolve_path_part(comps, cid, vid, refs) {
        Some(part) => parts.push(part)
        None => ()
      }
    }
    event_ids.clear()
    refs.clear()
    true
  }

  let mut cur = node
  let mut depth = 0
  while !@vdom.DomNode::is_same_node(cur, root_node) && depth < max_depth {
    if cur.node_kind() == 1 {
      match cur.attribute("data-eid") {
        Some(s) =>
          match parse_int_attr(s) {
            Some(eid) => event_ids.push(eid)
            None => ()
          }
        None => ()
      }
      let mut saw_comp = false
      let mut sib = cur.prev_sibling()
      while sib is Some(m) && m.node_kind() == 8 {
        let text = m.char_data()
        if !(text.length() > 0 && text[0] is '§') {
          break
        }
        match Meta::parse(text) {
          Some(Comp(nid~, cid~, vid~, base~)) => {
            saw_comp = true
            if !cross_component(cid, vid) {
              return None
            }
            refs.push({ nid, key: None, base, })
          }
          Some(Each(nid~, key~)) =>
            refs.push({ nid: Some(nid), key: Some(key), base: None, })
          Some(Scope(nid~)) =>
            refs.push({ nid: Some(nid), key: None, base: None, })
          None => ()
        }
        sib = m.prev_sibling()
      }
      if !saw_comp && cur.attribute("data-cid") is Some(cid_s) {
        match parse_int_attr(cid_s) {
          Some(cid) => {
            let vid = cur.attribute("data-vid").unwrap_or("main")
            if !cross_component(cid, vid) {
              return None
            }
            match cur.attribute("data-rp") {
              Some(text) =>
                match parse_render_path_text(text) {
                  Some(base) =>
                    refs.push({ nid: None, key: None, base: Some(base), })
                  None => ()
                }
              None => ()
            }
          }
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
  parts.rev_in_place()
  Some({ path: path_of_parts(parts), handlers: handlers.unwrap_or([]), })
}
