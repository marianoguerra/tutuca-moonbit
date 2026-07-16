// ViewResolver implementations. TEMPORARY: this whole seam is replaced by
// component/view resolution when the component layer lands (render-plan.md).

///|
pub impl ViewResolver for NullViewResolver with fn resolve_view(
  _self,
  _names,
  _value,
) {
  None
}

///|
/// First trail hit wins, then the "main" fallback (JS lookupBestView).
fn best_name(names : Array[String], has : (String) -> Bool) -> String? {
  for n in names {
    if has(n) {
      return Some(n)
    }
  }
  if has("main") {
    Some("main")
  } else {
    None
  }
}

///|
/// Component ids are the map's insertion order — stable per registry, so
/// §Comp§ metas and Boundaries lookups agree.
pub impl ViewResolver for ViewMap with fn resolve_view(self, names, _value) {
  guard best_name(names, n => self.views.contains(n)) is Some(name) else {
    return None
  }
  let mut cid = 0
  for k, node in self.views {
    if k == name {
      return Some(ResolvedView::{ node, cid, vid: name })
    }
    cid += 1
  }
  None
}

///|
pub fn RenderCtx::new(
  view_resolver? : &ViewResolver,
  render_once? : Map[Int, @vdom.Vdom] = {},
  render_cache? : RenderCache,
) -> RenderCtx {
  {
    view_resolver: match view_resolver {
      Some(r) => r
      None => NullViewResolver::{  }
    },
    render_once,
    render_cache,
  }
}
