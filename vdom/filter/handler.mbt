// The event-handler rule: a NAME rule at render time, which the URL rule
// deliberately is not.
//
// `@sanitize` settles names at registration and is the better place to do it —
// it is cheaper and it can tell the author. But `Policy::check_view` has one
// call site (`dyncomp/host/bundle.mbt`), so that pass runs for a dyncomp guest
// and for nobody else. A plain tutuca app has no static pass at all, and this
// is the only place its `on*` names are ever looked at.
//
// It matters most for a namespaced element. `set_prop` routes by
// `has_property` and an event handler IS a property, so on a plain HTML element
// a string assigned to `.onclick` is inert — an accident of routing rather than
// a defense, but an effective one. `uses_prop` is `!namespaced && …`
// (`vdom/to_dom.mbt`), so SVG and MathML elements route every attribute through
// `set_attribute` instead: `<svg onclick="…">` is written verbatim and SVG
// honours it. Nothing saves that case but removing the name.
// `vdom/memdom/event_attr_test.mbt` pins both halves.

///|
/// An event-handler content attribute, by the `on` prefix.
///
/// The same predicate as `@sanitize.is_event_handler_attr`, duplicated rather
/// than imported: `vdom/filter` is a leaf over `vdom` and importing `anode`
/// here would put a template compiler behind every render. Both are a prefix
/// test rather than the spec's enumeration, which is a superset that cannot
/// fall behind the platform as handlers are added — the safe direction to be
/// wrong in for a REMOVE rule. No non-handler attribute in HTML, SVG or MathML
/// begins with `on`.
pub fn is_event_handler_attr(name : String) -> Bool {
  name is ['o' | 'O', 'n' | 'N', _, ..]
}

///|
/// Drops event-handler attributes, whatever their value.
///
/// By NAME and regardless of the value's type, including `Data`. A view has no
/// way to express a function, so no `on*` attribute a view produces can be a
/// working handler anyway — tutuca's handlers are `@on.click`, which compiles
/// to `data-eid` and never arrives here as an `on*` name. Anything that does
/// arrive under one of these names was written as a raw content attribute, and
/// there is no legitimate reason for a view to do that.
pub struct HandlerFilter {
  /// What was removed this render, oldest first. Bounded, like `UrlFilter`'s.
  reports : Array[Dropped]
  max_reports : Int
}

///|
pub fn HandlerFilter::new(max_reports? : Int = 64) -> HandlerFilter {
  { reports: [], max_reports }
}

///|
/// Everything dropped since the last call, and clears the log.
pub fn HandlerFilter::take_reports(self : HandlerFilter) -> Array[Dropped] {
  let out = self.reports.copy()
  self.reports.clear()
  out
}

///|
fn HandlerFilter::record(self : HandlerFilter, d : Dropped) -> Unit {
  if self.reports.length() < self.max_reports {
    self.reports.push(d)
  }
}

///|
/// The rule for one element, so `Baseline` can apply it in a shared walk.
fn HandlerFilter::filter_elem(self : HandlerFilter, el : @vdom.VElem) -> Unit {
  let doomed : Array[String] = []
  for name, value in el.attrs {
    if is_event_handler_attr(name) {
      doomed.push(name)
      self.record({
        tag: el.tag,
        attr: name,
        value: value.to_attr_string(),
        reason: "event-handler attributes are not something a view may set",
      })
    }
  }
  for name in doomed {
    el.attrs.remove(name)
  }
}

///|
pub impl VdomFilter for HandlerFilter with fn filter_tree(self, tree) {
  walk_elems(tree, el => self.filter_elem(el))
}
