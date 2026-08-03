// The filter seam, end to end through the real render loop.
//
// The unit tests in `vdom/filter` prove the rule; these prove the SEAM — that
// a filter installed on an App runs on every render, before anything reaches
// the DOM, and that an App without one behaves exactly as it did before.

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
fn mk_filtered_app(
  install : Bool,
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
  if install {
    a.set_filter(Some(f))
  }
  a.start()
  (a, container, f)
}

///|
/// Absent is the trusted case: nothing installed, nothing changed. This is the
/// test that would fail if the seam ever stopped being opt-in.
test "an app with no filter renders exactly what it used to" {
  let (_a, container, _f) = mk_filtered_app(false)
  assert_true(container.to_html().contains("href=\"/safe\""))
}

///|
/// A value the static pass could not have seen — it arrives from state, and
/// only at render — is dropped before the DOM is written.
test "an installed filter drops a script URL the state produced" {
  let (a, container, f) = mk_filtered_app(true)
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
  let (a, container, f) = mk_filtered_app(false)
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
