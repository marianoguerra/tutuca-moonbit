// ViewResolver helpers shared by the production @component.Components
// implementation and the package's white-box test resolvers.

///|
/// Always unresolved (`<x render*>` sites render nothing): RenderCtx::new's
/// default when no resolver is passed.
priv struct NullViewResolver {}

///|
impl ViewResolver for NullViewResolver with fn resolve_view(
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
pub fn RenderCtx::new(
  view_resolver? : &ViewResolver,
  render_cache? : RenderCache,
  filter? : &@filter.VdomFilter,
) -> RenderCtx {
  {
    view_resolver: match view_resolver {
      Some(r) => r
      None => NullViewResolver::{  }
    },
    render_cache,
    filter,
  }
}
