// ViewRegistry: one registry answering both render-time view resolution and
// reconstruction-time boundary lookups, so emitted §Comp§ cids and later
// (cid, vid, nid|eid) lookups always agree.

///|
priv struct EmptyMacroScope {}

///|
impl @anode.MacroScope for EmptyMacroScope with fn lookup_macro(_self, _name) {
  None
}

///|
pub fn ViewRegistry::new() -> ViewRegistry {
  { by_name: Map([]) }
}

///|
pub fn ViewRegistry::add(
  self : ViewRegistry,
  name : String,
  raw_view : String,
) -> Unit raise {
  let cid = self.by_name.length()
  let v = @anode.View::new(name, raw_view~)
  let px = @anode.ParseContext::new()
  v.compile(px, EmptyMacroScope::{  }, cid=LNum(cid.to_double()))
  guard v.anode is Some(node) else { fail("view \{name} did not compile") }
  self.by_name[name] = { cid, vid: name, node, px }
}

///|
pub impl ViewResolver for ViewRegistry with fn resolve_view(self, names, _value) {
  guard best_name(names, n => self.by_name.contains(n)) is Some(name) else {
    return None
  }
  match self.by_name.get(name) {
    Some(cv) => Some({ node: cv.node, cid: cv.cid, vid: cv.vid })
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
pub impl Boundaries for ViewRegistry with fn node_for(self, cid, vid, nid) {
  match self.view_for(cid, vid) {
    Some(cv) => cv.px.nodes.get(nid)
    None => None
  }
}

///|
pub impl Boundaries for ViewRegistry with fn events_for(self, cid, vid, eid) {
  match self.view_for(cid, vid) {
    Some(cv) => cv.px.events.get(eid)
    None => None
  }
}
