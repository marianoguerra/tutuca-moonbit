// Component ancestry under an element. Unlike event dispatch this never stops
// at a handler: it returns every crossed component and its continuation.

///|
pub(all) struct Crossing {
  cid : Int
  vid : String
  path : @tutuca.DispatchPath
} derive(Eq, @debug.Debug)

///|
pub fn[N : @vdom.DomWalk] components_at(
  node : N,
  root_node : N,
  comps : &Boundaries,
  max_depth? : Int = 1000000,
) -> Array[Crossing] {
  let parts : Array[PathPart] = []
  let refs : Array[NodeRef] = []
  let crossings : Array[(Int, String, Int)] = []

  fn cross(cid : Int, vid : String) -> Unit {
    match resolve_path_part(comps, cid, vid, refs) {
      Some(part) => parts.push(part)
      None => ()
    }
    crossings.push((cid, vid, parts.length()))
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
          Some(Comp(nid~, cid~, vid~, base~)) => {
            saw_comp = true
            cross(cid, vid)
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
            cross(cid, cur.attribute("data-vid").unwrap_or("main"))
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

  let out : Array[Crossing] = []
  for crossing in crossings {
    let (cid, vid, below) = crossing
    let own = parts[below:].to_owned()
    own.rev_in_place()
    out.push({ cid, vid, path: path_of_parts(own), })
  }
  out.rev_in_place()
  out
}
