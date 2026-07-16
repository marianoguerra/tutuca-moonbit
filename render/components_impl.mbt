// The component registry as the render/reconstruction seam: value → its
// component's views (ViewResolver) and (cid, vid, nid|eid) lookups
// (Boundaries). Implemented here — the traits' package — so the component
// package stays free of render dependencies.

///|
pub impl ViewResolver for @component.Components with fn resolve_view(
  self,
  names,
  value,
) {
  guard self.get_comp_for(value) is Some(comp) else { return None }
  guard best_name(names, n => comp.views.contains(n)) is Some(name) else {
    return None
  }
  match comp.views.get(name) {
    Some(view) =>
      match view.anode {
        Some(node) => Some(ResolvedView::{ node, cid: comp.id, vid: name })
        None => None // not compiled
      }
    None => None
  }
}

///|
fn view_ctx(
  comps : @component.Components,
  cid : Int,
  vid : String,
) -> @anode.ParseContext? {
  match comps.get_component_for_id(cid) {
    Some(comp) =>
      match comp.views.get(vid) {
        Some(view) => view.ctx
        None => None
      }
    None => None
  }
}

///|
pub impl Boundaries for @component.Components with fn node_for(
  self,
  cid,
  vid,
  nid,
) {
  match view_ctx(self, cid, vid) {
    Some(px) => px.nodes.get(nid)
    None => None
  }
}

///|
pub impl Boundaries for @component.Components with fn events_for(
  self,
  cid,
  vid,
  eid,
) {
  match view_ctx(self, cid, vid) {
    Some(px) => px.events.get(eid)
    None => None
  }
}

///|
pub impl Boundaries for @component.Components with fn dyn_producer(
  self,
  cid,
  name,
) {
  match self.get_component_for_id(cid) {
    Some(comp) => @component.resolve_dyn_producer(comp, name)
    None => None
  }
}
