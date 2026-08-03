// The filter seam, end to end through the real render loop.
//
// The unit tests in `vdom/filter` prove the rule; these prove the SEAM — that
// the filter an App carries runs on every render before anything reaches the
// DOM, that it is on by default, and that opting out restores the old
// behaviour exactly.

///|
priv struct LinkState {
  url : String
}

///|
impl @component.Fields for LinkState with fn encode(s) {
  { "url": Str(s.url) }
}

///|
impl @component.Fields for LinkState with fn decode(f) {
  guard f.get("url") is Some(Str(v_url)) else { return None }
  Some({ url: v_url })
}

///|
impl @component.Fields for LinkState with fn schema() {
  @component.SchemaInfo::new(fingerprint="link_state", fields=[
    @component.FieldInfo::new("url", TyText),
  ])
}

///|
fn link_component() -> @component.Component {
  @component.component(
    views={
      "main": @anode.View::new(
        "main",
        raw_view="<div><a :href=\".url\" class=\"link\" @text=\"'go'\"></a><button @on.click=\"setUrl 'javascript:alert(1)'\">x</button><button @on.click=\"setUrl 'javascript:alert(2)'\">y</button></div>",
      ),
    },
    name="Linker",
    init=LinkState::{ url: "/safe" },
  )
}

///|
/// What an App is mounted with.
priv enum FilterMode {
  /// Whatever `App::new` installs — the thing most of these are about.
  Default
  /// `set_filter(None)`, the behaviour before the default existed.
  Off
  /// A host's own, replacing the default.
  Own
}

///|
fn mk_filtered_app(
  mode : FilterMode,
) -> (@app.App[@memdom.MemNode], @memdom.MemNode, @filter.UrlFilter) raise {
  let scope = @component.ComponentStack::new()
  scope.register_components([link_component()])
  guard scope.lookup_component("Linker") is Some(c) else {
    fail("component missing")
  }
  let doc = @memdom.document()
  let container = @vdom.DomNode::create_element(doc, "DIV", None, None)
  let f = @filter.UrlFilter::new()
  let a = @app.App::new(
    scope,
    c.make(Map([])),
    container,
    @vdom.RenderOpts::new(doc),
  )
  match mode {
    Default => ()
    Off => a.set_filter(None)
    Own => a.set_filter(Some(f))
  }
  a.start()
  (a, container, f)
}

///|
/// The headline of the change: an App nobody configured still does not render
/// a `javascript:` URL, and can say that it did not.
test "an app filters by default" {
  let (a, container, _f) = mk_filtered_app(Default)
  assert_true(container.to_html().contains("href=\"/safe\""))
  guard find_el(container, "BUTTON") is Some(btn) else { fail("no button") }
  assert_true(a.dispatch(btn, @render.DomEvent::new(name="click")))
  let html = container.to_html()
  assert_false(html.contains("javascript:"))
  // The attribute went, the element stayed.
  assert_true(html.contains("class=\"link\""))
  // Reachable without holding the filter, which the host never constructed.
  debug_inspect(
    a.take_filter_reports().map(@filter.Dropped::to_string),
    content=(
      #|["dropped href on <A>: URL scheme is not one a view may navigate to (javascript:alert(1))"]
    ),
  )
  // Drained, not copied.
  debug_inspect(a.take_filter_reports().length(), content="0")
}

///|
/// Opting out restores the old behaviour exactly, which is the escape hatch an
/// app with a deliberate `javascript:` URL or a trusted-only tree needs.
test "set_filter(None) opts out" {
  let (a, container, _f) = mk_filtered_app(Off)
  guard find_el(container, "BUTTON") is Some(btn) else { fail("no button") }
  assert_true(a.dispatch(btn, @render.DomEvent::new(name="click")))
  assert_true(container.to_html().contains("javascript:alert(1)"))
  // Nothing to report, because nothing ran.
  debug_inspect(a.take_filter_reports().length(), content="0")
}

///|
/// A value the static pass could not have seen — it arrives from state, and
/// only at render — is dropped before the DOM is written.
test "a host's own filter replaces the default" {
  let (a, container, f) = mk_filtered_app(Own)
  // The initial value is fine and survives.
  assert_true(container.to_html().contains("href=\"/safe\""))
  debug_inspect(f.take_reports().length(), content="0")

  // Now the component sets a javascript: URL on itself, the way a guest whose
  // state came from anywhere might.
  guard find_el(container, "BUTTON") is Some(btn) else { fail("no button") }
  assert_true(a.dispatch(btn, @render.DomEvent::new(name="click")))

  // The state really did change — the filter is not preventing the write, it
  // is preventing the render.
  assert_true(
    @tutuca.Path::new(steps=[FieldStep("url")]).lookup(a.transactor.root)
    is Some(Str("javascript:alert(1)")),
  )
  // ...and the DOM never saw it.
  let html = container.to_html()
  assert_false(html.contains("javascript:"))
  // The element and its other attributes are untouched: an attribute was
  // dropped, not a node.
  assert_true(html.contains("class=\"link\""))
  assert_true(html.contains(">go<"))
  debug_inspect(
    f.take_reports().map(@filter.Dropped::to_string),
    content=(
      #|["dropped href on <A>: URL scheme is not one a view may navigate to (javascript:alert(1))"]
    ),
  )
}

///|
/// Installing takes effect from the next render rather than retroactively —
/// what is already in the DOM stays until something re-renders over it, for
/// the same reason a policy applies at load.
test "a filter installed after mount applies from the next render" {
  // Mounted opted-out, so there is something in the DOM to not reach back for.
  let (a, container, f) = mk_filtered_app(Off)
  guard find_el(container, "BUTTON") is Some(bad1) else { fail("no button") }
  assert_true(a.dispatch(bad1, @render.DomEvent::new(name="click")))
  // No filter yet, so it rendered.
  assert_true(container.to_html().contains("javascript:alert(1)"))

  // Installing does NOT reach back into the DOM.
  a.set_filter(Some(f))
  assert_true(container.to_html().contains("javascript:alert(1)"))

  // The next render is where it takes effect.
  guard find_el(container, "BUTTON", nth=1) is Some(bad2) else {
    fail("no second button")
  }
  assert_true(a.dispatch(bad2, @render.DomEvent::new(name="click")))
  assert_false(container.to_html().contains("javascript:"))
  debug_inspect(f.take_reports().length(), content="1")
}
