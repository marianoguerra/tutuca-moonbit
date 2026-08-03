// Both value rules in one traversal.
//
// This is the filter a host wants unless it has a reason to want otherwise:
// the URL-scheme rule and the event-handler rule are the two things that must
// be decided after render, and neither is configurable because neither has
// anything to configure — a view has no legitimate `javascript:` URL and no
// legitimate `onclick`.
//
// One walk rather than `Chain::new([UrlFilter, HandlerFilter])`, which would
// traverse the tree twice for two rules that both only read `attrs`. That
// difference is worth a type once the filter is installed by default, which is
// the change this exists for — see docs/sanitizer.md, "Order of work".

///|
/// The URL-scheme rule and the event-handler rule, applied together.
///
/// Raw markup is NOT in here. `vdom/filter/markup` drags an HTML parser and the
/// config model behind it, and a host that wants these two should not pay for
/// either; it is also the one filter that must run before the others, since it
/// builds a subtree they would otherwise never inspect. Compose it with
/// `Chain`, markup first.
pub struct Baseline {
  url : UrlFilter
  handlers : HandlerFilter
}

///|
pub fn Baseline::new(max_reports? : Int = 64) -> Baseline {
  {
    url: UrlFilter::new(max_reports~),
    handlers: HandlerFilter::new(max_reports~),
  }
}

///|
/// Everything either rule dropped since the last call, and clears both logs.
///
/// URL drops first, then handler drops. Within each the order is the order they
/// happened; across the two it is not, and nothing should read meaning into it.
pub fn Baseline::take_reports(self : Baseline) -> Array[Dropped] {
  let out = self.url.take_reports()
  out.append(self.handlers.take_reports())
  out
}

///|
pub impl VdomFilter for Baseline with fn filter_tree(self, tree) {
  walk_elems(tree, el => {
    self.url.filter_elem(el)
    self.handlers.filter_elem(el)
  })
}
