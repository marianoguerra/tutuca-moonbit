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
pub impl VdomFilter for Baseline with fn take_reports(self) {
  let out = VdomFilter::take_reports(self.url)
  out.append(VdomFilter::take_reports(self.handlers))
  out
}

///|
pub impl VdomFilter for Baseline with fn filter_elem(self, el) {
  VdomFilter::filter_elem(self.url, el)
  VdomFilter::filter_elem(self.handlers, el)
}

///|
/// Each half asks about its own bit, so an element with a `href` and no `on*`
/// pays for the URL rule alone. Written out rather than delegating twice
/// through `filter_elem_hinted` for the reason this type exists at all: one
/// traversal, two rules, no indirection between them.
pub impl VdomFilter for Baseline with fn filter_elem_hinted(self, el, hints) {
  if hints.url {
    VdomFilter::filter_elem(self.url, el)
  }
  if hints.handler {
    VdomFilter::filter_elem(self.handlers, el)
  }
}
