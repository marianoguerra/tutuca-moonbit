// White-box render-test resolvers. ViewRegistry answers both view resolution and
// reconstruction-time boundary lookups, so emitted §Comp§ cids and later
// (cid, vid, nid|eid) lookups always agree.
//
// TEST SUPPORT. It takes view SOURCE and parses it, which is what lets the
// white-box render tests state a view and a stack in one place and read the
// result. A component-less render in production goes through @component,
// where a view arrives already compiled.

///|
priv struct ViewMap {
  views : Map[String, @anode.ANode]
}

///|
impl ViewResolver for ViewMap with fn resolve_view(self, names, _value) {
  guard best_name(names, n => self.views.contains(n)) is Some(name) else {
    return None
  }
  let mut cid = 0
  for key, node in self.views {
    if key == name {
      return Some({ node, cid, vid: name, })
    }
    cid += 1
  }
  None
}

///|
priv struct CompiledView {
  cid : Int
  vid : String
  node : @anode.ANode
  px : @anode.ParseContext
}

///|
priv struct ViewRegistry {
  by_name : Map[String, CompiledView]
}

///|
priv struct EmptyMacroScope {}

///|
impl @anode.MacroScope for EmptyMacroScope with fn lookup_macro(_self, _name) {
  None
}

///|
fn ViewRegistry::new() -> ViewRegistry {
  { by_name: Map([]), }
}

///|
fn ViewRegistry::add(
  self : ViewRegistry,
  name : String,
  raw_view : String,
) -> Unit raise {
  let cid = self.by_name.length()
  let v = @anode.View::new(name, raw_view~)
  let px = @anode.ParseContext::new()
  v.compile(px, EmptyMacroScope::{ }, cid=LNum(cid.to_double()))
  guard v.anode is Some(node) else { fail("view \{name} did not compile") }
  self.by_name[name] = { cid, vid: name, node, px, }
}

///|
impl ViewResolver for ViewRegistry with fn resolve_view(self, names, _value) {
  guard best_name(names, n => self.by_name.contains(n)) is Some(name) else {
    return None
  }
  match self.by_name.get(name) {
    Some(cv) => Some({ node: cv.node, cid: cv.cid, vid: cv.vid, })
    None => None
  }
}

///|
fn ViewRegistry::view_for(
  self : ViewRegistry,
  cid : Int,
  vid : String,
) -> CompiledView? {
  match self.by_name.get(vid) {
    Some(cv) => if cv.cid == cid { Some(cv) } else { None }
    None => None
  }
}

///|
impl Boundaries for ViewRegistry with fn node_for(self, cid, vid, nid) {
  match self.view_for(cid, vid) {
    Some(cv) => cv.px.nodes.get(nid)
    None => None
  }
}

///|
impl Boundaries for ViewRegistry with fn events_for(self, cid, vid, eid) {
  match self.view_for(cid, vid) {
    Some(cv) => cv.px.events.get(eid)
    None => None
  }
}
