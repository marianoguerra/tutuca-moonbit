///| A surface as a document, and back.
///
/// One format for three jobs: what the universal UI exports, what an agent
/// reads back with `ui_read`, and what a session resumes from. They are the
/// same document on purpose — an export a person can hand to a model, and a
/// layout a model built that a person can open and keep editing.
///
/// Only what is not the default is written. A surface of forty nodes is mostly
/// defaults, and a document that spells them all out is one nobody can read
/// and a model wastes its context on.

///|
fn s_(v : String) -> Json {
  Json::string(v)
}

///|
fn n_(v : Int) -> Json {
  Json::number(v.to_double())
}

///|
fn props_json(p : LayoutProps, kind : NodeKind) -> Json {
  let d = LayoutProps::default()
  let m : Map[String, Json] = Map([])
  // Container props are written only for a container, and cell props only when
  // they say something: a Slot with `direction: column` in its document is
  // noise that reads like meaning.
  if kind.is_container() {
    if p.direction != d.direction {
      m["direction"] = s_(p.direction.to_css())
    }
    if p.justify != d.justify {
      m["justify"] = s_(justify_name(p.justify))
    }
    if p.align != d.align {
      m["align"] = s_(align_name(p.align))
    }
    if p.wrap != d.wrap {
      m["wrap"] = Json::boolean(p.wrap)
    }
    if p.gap != d.gap {
      m["gap"] = n_(p.gap)
    }
    if !p.columns.is_empty() {
      m["columns"] = Json::array(p.columns.map(t => s_(t.to_css())))
    }
    if !p.rows.is_empty() {
      m["rows"] = Json::array(p.rows.map(t => s_(t.to_css())))
    }
  }
  if p.padding != d.padding {
    m["padding"] = n_(p.padding)
  }
  if p.background != "" {
    m["background"] = s_(p.background)
  }
  if p.border != "" {
    m["border"] = s_(p.border)
  }
  if p.col_span != d.col_span {
    m["colSpan"] = n_(p.col_span)
  }
  if p.row_span != d.row_span {
    m["rowSpan"] = n_(p.row_span)
  }
  if p.col_start != d.col_start {
    m["colStart"] = n_(p.col_start)
  }
  if p.row_start != d.row_start {
    m["rowStart"] = n_(p.row_start)
  }
  Json::object(m)
}

///|
/// The name a prop is WRITTEN as, which is not the CSS it renders to: a
/// document says `start`, the style says `flex-start`. The document's spelling
/// is the one a caller types, so it is the short one.
fn justify_name(j : Justify) -> String {
  match j {
    Start => "start"
    Center => "center"
    End => "end"
    SpaceBetween => "space-between"
    SpaceAround => "space-around"
    SpaceEvenly => "space-evenly"
  }
}

///|
fn align_name(a : Align) -> String {
  match a {
    AStart => "start"
    ACenter => "center"
    AEnd => "end"
    AStretch => "stretch"
    ABaseline => "baseline"
  }
}

///|
fn binding_json(b : Binding) -> Json {
  let m : Map[String, Json] = { "module": s_(b.module_), "name": s_(b.name) }
  if b.init != "" {
    m["init"] = s_(b.init)
  }
  if !b.args.is_empty() {
    m["args"] = @tutuca.Value::Map(b.args).to_json()
  }
  Json::object(m)
}

///|
/// The surface as a document. Nodes are an ARRAY in document order rather than
/// an object keyed by id: the order is meaningful (it is the tree, walked), and
/// a JSON object's key order is not something to rely on.
pub fn Surface::to_json(self : Surface) -> Json {
  let nodes : Array[Json] = []
  for id in self.walk() {
    guard self.nodes.get(id) is Some(n) else { continue }
    let m : Map[String, Json] = {
      "id": s_(n.id),
      "kind": s_(n.kind.to_string()),
    }
    let props = props_json(n.props, n.kind)
    if props is Object(pm) && !pm.is_empty() {
      m["props"] = props
    }
    if !n.children.is_empty() {
      m["children"] = Json::array(n.children.map(c => s_(c)))
    }
    if n.bound is Some(b) {
      m["bound"] = binding_json(b)
    }
    nodes.push(Json::object(m))
  }
  Json::object({
    "id": s_(self.id),
    "root": s_(self.root),
    "nodes": Json::array(nodes),
    "data": self.data.to_json(),
  })
}

///|
/// Read a surface back.
///
/// Deliberately TOLERANT of what it does not understand and strict about what
/// it must: an unknown prop name or an unparseable track is dropped with the
/// rest of the node kept, because a document written by a newer version should
/// degrade rather than refuse. What it will not do is produce a broken tree —
/// a missing root or a node claiming a child that does not exist is a document
/// nothing downstream can walk, so it is refused.
pub fn Surface::from_json(j : Json) -> Surface? {
  guard j is Object(root_obj) else { return None }
  guard root_obj.get("root") is Some(String(root)) else { return None }
  guard root_obj.get("nodes") is Some(Array(node_list)) else { return None }
  let id = match root_obj.get("id") {
    Some(String(s)) => s
    _ => "surface"
  }
  let nodes : Map[String, Node] = Map([])
  let mut max_n = 0
  for nj in node_list {
    guard nj is Object(nm) else { continue }
    guard nm.get("id") is Some(String(nid)) else { continue }
    guard nm.get("kind") is Some(String(kind_s)) else { continue }
    guard NodeKind::parse(kind_s) is Some(kind) else { continue }
    let props = match nm.get("props") {
      Some(pj) => read_props(pj)
      None => LayoutProps::default()
    }
    let children : Array[String] = []
    if nm.get("children") is Some(Array(cs)) {
      for c in cs {
        if c is String(cid) {
          children.push(cid)
        }
      }
    }
    let bound = match nm.get("bound") {
      Some(bj) => read_binding(bj)
      None => None
    }
    nodes[nid] = { id: nid, kind, props, children, bound }
    // Resume the id counter past anything the document already used, so a
    // reopened surface does not mint an id it is already holding.
    if nid.has_prefix("n") {
      let tail = nid[1:]
      let mut v = 0
      let mut numeric = tail != ""
      for c in tail {
        if c < '0' || c > '9' {
          numeric = false
        } else {
          v = v * 10 + (c.to_int() - '0'.to_int())
        }
      }
      if numeric && v > max_n {
        max_n = v
      }
    }
  }
  if !nodes.contains(root) {
    return None
  }
  // Every named child must exist: a dangling id is a tree that cannot be
  // walked, and dropping it silently would move a component somewhere the
  // document did not say.
  for _, n in nodes {
    for c in n.children {
      if !nodes.contains(c) {
        return None
      }
    }
  }
  let data = match root_obj.get("data") {
    Some(dj) => @tutuca.Value::from_json(dj)
    None => Map(Map([]))
  }
  Some({ id, root, nodes, data, next_id: max_n + 1 })
}

///|
/// Props from a document, dropping what this version does not understand.
/// Reuses the op path's decoder so a document and a patch can never disagree
/// about what `gap: "3"` means.
fn read_props(j : Json) -> LayoutProps {
  guard j is Object(m) else { return LayoutProps::default() }
  let props : Map[String, @tutuca.Value] = Map([])
  for k, v in m {
    props[k] = @tutuca.Value::from_json(v)
  }
  let dropped : Array[OpError] = []
  apply_props(LayoutProps::default(), props, 0, "", dropped)
}

///|
fn read_binding(j : Json) -> Binding? {
  guard j is Object(m) else { return None }
  guard m.get("module") is Some(String(module_)) else { return None }
  guard m.get("name") is Some(String(name)) else { return None }
  let init = match m.get("init") {
    Some(String(s)) => s
    _ => ""
  }
  let args : Map[String, @tutuca.Value] = match m.get("args") {
    Some(Object(a)) => {
      let out : Map[String, @tutuca.Value] = Map([])
      for k, v in a {
        out[k] = @tutuca.Value::from_json(v)
      }
      out
    }
    _ => Map([])
  }
  Some({ module_, name, init, args })
}
