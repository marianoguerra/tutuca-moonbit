///| The contract every hinted rule has to keep.
///
/// `filter_elem_hinted` exists to skip work, never to do different work, so
/// there are exactly two things to hold each rule to: under
/// `SinkHints::all()` it must do what `filter_elem` does, and under a
/// `SinkHints` with its own bit clear it must do nothing at all. A rule that
/// broke the first would be a hole reachable from any caller with no view tree
/// to hint from; one that broke the second would be a hole reachable from
/// `render`, which is every render of every app.
///
/// The elements here carry a sink of every kind at once, so a rule that skipped
/// on the wrong bit — reading `css` where it meant `url` — fails these rather
/// than passing by coincidence.

///|
fn every_sink() -> @vdom.VElem {
  {
    tag: "a",
    attrs: {
      "href": Str("javascript:alert(1)"),
      "onclick": Str("alert(1)"),
      "style": Str("background-image:url(//evil.test/p)"),
      "class": Str("kept"),
    },
    childs: [],
    key: None,
    ns: None,
  }
}

///|
/// Which of `every_sink`'s four names survived, in a fixed order so the
/// comparison is about the set rather than about the map's iteration order.
fn names_of(el : @vdom.VElem) -> Array[String] {
  let out : Array[String] = []
  for name in ["class", "href", "onclick", "style"] {
    if el.attrs.contains(name) {
      out.push(name)
    }
  }
  out
}

///|
test "all() does what filter_elem does, for every rule" {
  // Each rule twice over the same element: once through the primitive, once
  // through the hinted entry point claiming everything. Same survivors.
  let direct = every_sink()
  UrlFilter::new().filter_elem(direct)
  HandlerFilter::new().filter_elem(direct)
  CssFilter::new().filter_elem(direct)
  let hinted = every_sink()
  let all = @sinks.SinkHints::all()
  UrlFilter::new().filter_elem_hinted(hinted, all)
  HandlerFilter::new().filter_elem_hinted(hinted, all)
  CssFilter::new().filter_elem_hinted(hinted, all)
  assert_eq(names_of(direct), names_of(hinted))
  // And it is not vacuous: the three sinks went and `class` stayed.
  assert_eq(names_of(hinted), ["class"])
}

///|
test "a rule whose bit is clear does nothing" {
  let el = every_sink()
  let none = @sinks.SinkHints::empty()
  UrlFilter::new().filter_elem_hinted(el, none)
  HandlerFilter::new().filter_elem_hinted(el, none)
  CssFilter::new().filter_elem_hinted(el, none)
  Baseline::new().filter_elem_hinted(el, none)
  assert_eq(names_of(el), ["class", "href", "onclick", "style"])
}

///|
test "each rule reads its own bit and no other" {
  // `url` set alone: the URL goes, the handler and the CSS stay.
  let el = every_sink()
  let url_only = { ..@sinks.SinkHints::empty(), url: true }
  UrlFilter::new().filter_elem_hinted(el, url_only)
  HandlerFilter::new().filter_elem_hinted(el, url_only)
  CssFilter::new().filter_elem_hinted(el, url_only)
  assert_eq(names_of(el), ["class", "onclick", "style"])

  // `handler` set alone, through `Baseline`, which reads both its halves'
  // bits separately rather than one bit for the pair.
  let el2 = every_sink()
  Baseline::new().filter_elem_hinted(el2, {
    ..@sinks.SinkHints::empty(),
    handler: true,
  })
  assert_eq(names_of(el2), ["class", "href", "style"])
}

///|
test "a Chain passes the hints through to every member" {
  let chain = Chain::new([CssFilter::new(), Baseline::new()])
  let all = every_sink()
  chain.filter_elem_hinted(all, @sinks.SinkHints::all())
  assert_eq(names_of(all), ["class"])
  let none = every_sink()
  chain.filter_elem_hinted(none, @sinks.SinkHints::empty())
  assert_eq(names_of(none), ["class", "href", "onclick", "style"])
}

///|
test "a filter that ignores the hints still sees every element" {
  // The default impl on the trait, which is what a host's own rule gets. It
  // must not be skippable: nothing here can describe what it looks for, so a
  // clear bit says nothing about it.
  let counter = { seen: 0 }
  let f : &VdomFilter = counter
  f.filter_elem_hinted(every_sink(), @sinks.SinkHints::empty())
  f.filter_elem_hinted(every_sink(), @sinks.SinkHints::all())
  assert_eq(counter.seen, 2)
}

///|
priv struct CountingFilter {
  mut seen : Int
}

///|
impl VdomFilter for CountingFilter with fn filter_elem(self, _el) {
  self.seen = self.seen + 1
}
