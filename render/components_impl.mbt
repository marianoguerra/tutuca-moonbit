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
  let resolved_names : Array[String] = []
  for requested in names {
    let parts : Array[String] = requested
      .split("::")
      .map(x => x.to_owned())
      .collect()
    if parts.length() == 2 && value.schema() is Some(schema) {
      match
        schema.view_bindings
        .iter()
        .find_first(b => b.protocol_id == parts[0] && b.member_name == parts[1]) {
        Some(binding) => resolved_names.push(binding.source)
        None => {
          resolved_names.push(parts[1]) // same-name gradual fallback
          @tutuca.protocol_mismatch({
            code: ProtocolViewMissing,
            protocol_id: parts[0],
            member_name: parts[1],
            operation: "resolve view",
            detail: "semantic view has no implementation binding",
            component: schema.name,
            path: @tutuca.Path::new(),
            state: value,
            resolution: UsedMainView,
          })
        }
      }
    } else {
      resolved_names.push(requested)
    }
  }
  // The final main fallback keeps a partially loaded UI visible.
  if !resolved_names.contains("main") {
    resolved_names.push("main")
  }
  guard best_name(resolved_names, n => comp.views.contains(n)) is Some(name) else {
    return None
  }
  match comp.views.get(name) {
    Some(view) =>
      match view.anode {
        Some(node) => Some({ node, cid: comp.id, vid: name, })
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
