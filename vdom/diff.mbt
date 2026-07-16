///|
/// Diff two attribute maps. Outer `None` = no difference; an inner `None`
/// value marks a removed attribute (the JS `undefined` marker). Two-pass in
/// the same order as the JS source so the diff map preserves application
/// order.
pub fn diff_props(
  a : Map[String, AttrValue],
  b : Map[String, AttrValue],
) -> Map[String, AttrValue?]? {
  if physical_equal(a, b) {
    return None
  }
  let diff : Map[String, AttrValue?] = {}
  for name, av in a {
    match b.get(name) {
      None => diff[name] = None
      Some(bv) => if av != bv { diff[name] = Some(bv) }
    }
  }
  for name, bv in b {
    if !a.contains(name) {
      diff[name] = Some(bv)
    }
  }
  if diff.length() == 0 {
    None
  } else {
    Some(diff)
  }
}

///|
/// Morph `dom_node` (currently rendering `source`) into `target`. Returns the
/// node representing `target` — the same node patched in place when the kinds
/// match, or a replacement created via `to_dom`.
pub fn[N : DomNode] morph_node(
  dom_node : N,
  source : Vdom,
  target : Vdom,
  opts : RenderOpts[N],
) -> N {
  if source.is_equal_to(target) {
    return dom_node
  }
  match (source, target) {
    (Text(_), Text(t)) | (Comment(_), Comment(t)) => {
      dom_node.set_data(t)
      dom_node
    }
    (Node(s), Node(t)) if s.is_same_kind(t) => {
      let diff = match diff_props(s.attrs, t.attrs) {
        Some(d) => d
        None => {}
      }
      let has_value = diff.contains("value")
      let has_checked = diff.contains("checked")
      if diff.length() > 0 {
        let namespaced = is_namespaced(dom_node)
        for name, value in diff {
          if name != "value" && name != "checked" {
            set_prop(dom_node, name, value, namespaced)
          }
        }
      }
      if !t.attrs.contains("dangerouslySetInnerHTML") {
        let ns = effective_ns(t, opts)
        morph_children(dom_node, s.childs, t.childs, child_opts(t, ns, opts))
      }
      if has_value {
        guard diff.get("value") is Some(v)
        apply_value_last(dom_node, v)
      } else if s.tag == "SELECT" && t.attrs.get("value") is Some(v) {
        // For <select>, re-apply value even when not in the diff: changing
        // the <option> children can silently shift dom.value to "".
        apply_value_last(dom_node, Some(v))
      }
      if has_checked {
        guard diff.get("checked") is Some(c)
        set_prop(dom_node, "checked", c, false)
      }
      dom_node
    }
    (Fragment(sc), Fragment(tc)) => {
      morph_children(dom_node, sc, tc, opts)
      dom_node
    }
    _ => {
      let new_node = to_dom(target, opts)
      if dom_node.parent_node() is Some(p) {
        p.replace_child(new_node, dom_node)
      }
      new_node
    }
  }
}

///|
/// Reconcile `parent`'s DOM children (currently rendering `old_childs`) with
/// `new_childs`: unkeyed equal-length lists morph pairwise in place; anything
/// else goes through key-map matching with an unkeyed cursor, positional
/// insert_before, and a backward removal pass.
pub fn[N : DomNode] morph_children(
  parent : N,
  old_childs : Array[Vdom],
  new_childs : Array[Vdom],
  opts : RenderOpts[N],
) -> Unit {
  if old_childs.length() == 0 {
    append_child_nodes(parent, new_childs, opts)
    return
  }
  if new_childs.length() == 0 {
    parent.replace_children()
    return
  }
  if old_childs.length() == new_childs.length() {
    let mut has_key = false
    for i in 0..<old_childs.length() {
      if old_childs[i].key() is Some(_) || new_childs[i].key() is Some(_) {
        has_key = true
        break
      }
    }
    if !has_key {
      let mut dom = parent.first_child()
      for i in 0..<old_childs.length() {
        guard dom is Some(d)
        // Grab the sibling before morphing: a replacement detaches `d`.
        let next = d.next_sibling()
        let _ = morph_node(d, old_childs[i], new_childs[i], opts)
        dom = next
      }
      return
    }
  }
  let dom_nodes = parent.child_nodes()
  let old_key_map : Map[String, Int] = {}
  for i in 0..<old_childs.length() {
    if old_childs[i].key() is Some(k) {
      old_key_map[k] = i
    }
  }
  let used = FixedArray::make(old_childs.length(), false)
  let mut unkeyed_cursor = 0
  for j in 0..<new_childs.length() {
    let new_child = new_childs[j]
    let mut old_idx = -1
    match new_child.key() {
      Some(k) => if old_key_map.get(k) is Some(i) && !used[i] { old_idx = i }
      None =>
        while unkeyed_cursor < old_childs.length() {
          if !used[unkeyed_cursor] && old_childs[unkeyed_cursor].key() is None {
            old_idx = unkeyed_cursor
            unkeyed_cursor += 1
            break
          }
          unkeyed_cursor += 1
        }
    }
    if old_idx >= 0 {
      used[old_idx] = true
      let new_dom = morph_node(
        dom_nodes[old_idx],
        old_childs[old_idx],
        new_child,
        opts,
      )
      let ref_node = parent.child_node_at(j)
      let in_place = ref_node is Some(r) && r.is_same_node(new_dom)
      if !in_place {
        parent.insert_before(new_dom, ref_node)
      }
    } else {
      parent.insert_before(to_dom(new_child, opts), parent.child_node_at(j))
    }
  }
  for i = old_childs.length() - 1; i >= 0; i = i - 1 {
    if !used[i] &&
      dom_nodes[i].parent_node() is Some(p) &&
      p.is_same_node(parent) {
      parent.remove_child(dom_nodes[i])
    }
  }
}

///|
/// State returned by `render`, passed back as `prev` on the next render for
/// incremental morphing. For fragment roots `dom` is the container itself.
pub(all) struct RenderResult[N] {
  vnode : Vdom
  dom : N
}

///|
/// Render `vnode` into `container`. With a `prev` result whose root kind
/// matches (fragment vs non-fragment), morphs incrementally; otherwise
/// clears the container and renders fresh.
///
/// # Example (with the memdom implementation)
/// ```mbt nocheck
/// let doc = @memdom.document()
/// let container = @vdom.DomNode::create_element(doc, "DIV", None, None)
/// let opts = @vdom.RenderOpts::new(doc)
/// let prev = @vdom.render(view_v1, container, opts)
/// let _ = @vdom.render(view_v2, container, opts, prev~) // incremental morph
/// ```
pub fn[N : DomNode] render(
  vnode : Vdom,
  container : N,
  opts : RenderOpts[N],
  prev? : RenderResult[N],
) -> RenderResult[N] {
  let is_fragment = vnode is Fragment(_)
  if prev is Some(p) && (p.vnode is Fragment(_)) == is_fragment {
    let old_dom = if is_fragment { container } else { p.dom }
    let new_dom = morph_node(old_dom, p.vnode, vnode, opts)
    return { vnode, dom: if is_fragment { container } else { new_dom } }
  }
  let dom_node = to_dom(vnode, opts)
  container.replace_children()
  container.append_child(dom_node)
  { vnode, dom: if is_fragment { container } else { dom_node } }
}

///|
pub fn[N : DomNode] unmount(container : N) -> Unit {
  container.replace_children()
}
