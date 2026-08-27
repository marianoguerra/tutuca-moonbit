// What the hints claim, and the one invariant that lets them be memoized.
//
// The bits are only ever an optimization, so a hint that is wrong in the
// generous direction costs nothing and one that is wrong in the narrow
// direction costs a rule. Both halves are here: every shape that must set a
// bit, and every name that must not clear one.

///|
fn hints_of(html : String) -> @sinks.SinkHints {
  guard parse_node(html) is Dom(d) else {
    abort("expected an element at the root of \{html}")
  }
  classify_attrs(d.attrs)
}

///|
test "an element with no sink attribute concerns no rule" {
  let hints = hints_of("<div class=\"row\" id=\"main\" title=\"hi\"></div>")
  assert_false(hints.url)
  assert_false(hints.handler)
  assert_false(hints.css)
  assert_false(hints.markup)
  assert_false(hints.any())
}

///|
test "a URL attribute sets the URL bit and nothing else" {
  let hints = hints_of("<a href=\".target\" class=\"link\">go</a>")
  assert_true(hints.url)
  assert_false(hints.handler)
  assert_false(hints.css)
  assert_false(hints.markup)
}

///|
test "the URL bit follows the filter's own table, not a list here" {
  // `data` is `<object data>`; the `data-*` prefix is a different thing, and
  // the predicate these share is what says so.
  assert_true(hints_of("<object data=\".src\"></object>").url)
  assert_false(hints_of("<div data-role=\"x\"></div>").url)
  assert_true(hints_of("<img srcset=\".set\" />").url)
  assert_true(hints_of("<form action=\".to\"></form>").url)
}

///|
test "an on* name sets the handler bit" {
  let hints = hints_of("<div onclick=\"alert(1)\"></div>")
  assert_true(hints.handler)
  assert_false(hints.url)
  // tutuca's own handlers compile to `data-eid` and never arrive as `on*`.
  assert_false(hints_of("<button @on.click=\"$inc\">+</button>").handler)
}

///|
test "style and an SVG presentation attribute both set the CSS bit" {
  assert_true(hints_of("<div style=\"color:red\"></div>").css)
  assert_true(hints_of("<div style=\".dynamic\"></div>").css)
  // A property name is a property name wherever it is written, which is what
  // makes `fill=\"url(…)\"` a fetch and `fill=\"red\"` a colour.
  assert_true(hints_of("<div cursor=\"pointer\"></div>").css)
  assert_false(hints_of("<div class=\"text-red\"></div>").css)
  guard parse_node("<svg><circle fill=\"#1da1f2\" /></svg>") is Dom(svg) else {
    abort("expected <svg>")
  }
  // The wrapper carries nothing; the child is the one with the CSS value.
  assert_false(classify_attrs(svg.attrs).any())
  guard svg.childs[0] is Dom(circle) else { abort("expected <circle>") }
  assert_true(classify_attrs(circle.attrs).css)
}

///|
test "each markup directive sets the markup bit" {
  assert_true(hints_of("<div @setinnermd=\".doc\"></div>").markup)
  assert_true(hints_of("<div @setinnerhtml=\".doc\"></div>").markup)
  assert_true(hints_of("<div @setinnersvg=\".doc\"></div>").markup)
  assert_true(hints_of("<div @dangerouslysetinnerhtml=\".doc\"></div>").markup)
}

///|
test "both branches of an @if attribute are the same name, and it is read" {
  let hints = hints_of(
    "<a @if.href=\".loggedIn\" @then=\".profile\" @else=\".login\">me</a>",
  )
  assert_true(hints.url)
}

///|
test "the data-* names set_data_attr writes concern no rule" {
  // THE memo invariant. `Attrs` is mutable after parse, and `set_data_attr` is
  // the only thing that mutates it — `ir.mbt` writes `data-vid`, `view.mbt`
  // `data-cid`, `anode.mbt` `data-nid`, `attrs.mbt` `data-eid`, all at compile
  // time and all after this walk could have run. If one of those names ever
  // became a name a rule looks at, a hint computed before the stamp would be
  // narrower than the element it describes, and this is what would fail first.
  for name in ["data-vid", "data-cid", "data-nid", "data-eid"] {
    assert_false(@filter.is_url_attr(name))
    assert_false(@filter.is_event_handler_attr(name))
    assert_false(@filter.is_css_attr(name))
  }
}

///|
test "hints are computed once and then read from the element" {
  guard parse_node("<a href=\".target\">go</a>") is Dom(d) else {
    abort("expected <a>")
  }
  assert_true(d.sink_hints is None)
  let first = sink_hints(d)
  assert_true(first.url)
  assert_true(d.sink_hints is Some(_))
  // The second call reads the memo rather than walking again; the same answer
  // either way, which is the property that makes the memo invisible.
  assert_eq(first, sink_hints(d))
}

///|
/// A filter that decides nothing and remembers what it was told, so a test can
/// assert on the hints the RENDER LOOP produced rather than on ones it built
/// itself.
priv struct HintRecorder {
  seen : Array[(String, @sinks.SinkHints)]
}

///|
impl @filter.VdomFilter for HintRecorder with fn filter_elem(self, el) {
  // Reached only if something calls the primitive; `render` does not.
  self.seen.push((el.tag, @sinks.SinkHints::all()))
}

///|
impl @filter.VdomFilter for HintRecorder with fn filter_elem_hinted(
  self,
  el,
  hints,
) {
  self.seen.push((el.tag, hints))
}

///|
test "the render loop hands each element the hints for its own attributes" {
  let recorder = { seen: [], }
  let filter : &@filter.VdomFilter = recorder
  let _ = render_html(
    "<div class=\"page\"><a href=\".target\">go</a><p style=\"color:red\">x</p></div>",
    filter~,
  )
  // Children are built before their parent, so the wrapper is last; `h`
  // uppercases an HTML tag on the way into the vdom.
  let seen = recorder.seen
  assert_eq(seen.length(), 3)
  assert_eq(seen[0].0, "A")
  assert_true(seen[0].1.url)
  assert_false(seen[0].1.css)
  assert_eq(seen[1].0, "P")
  assert_true(seen[1].1.css)
  assert_false(seen[1].1.url)
  assert_eq(seen[2].0, "DIV")
  assert_false(seen[2].1.any())
}
