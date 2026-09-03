// The filter seam, end to end through the real render loop.
//
// The unit tests in `vdom/filter` prove the rule; these prove the SEAM — that
// the chain an App carries runs on every render before anything reaches the
// DOM, that it is on by default, and that nothing a host can say takes it away.
//
// The SECOND layer — that a directive whose filter never ran renders an empty
// element, and that `set_prop` refuses a structured value on `href` — is not an
// app property: it is pinned where it lives, by `render/render_wbtest.mbt`
// ("… renders nothing on its own", two of them) and
// `vdom/memdom/custom_element_test.mbt` ("a structured value does not skip
// never_assign").

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
  Some({ url: v_url, })
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
        raw_view="<div><a :href=\".url\" class=\"link\" @text=\"'go'\"></a><button @on.click=\".url = 'javascript:alert(1)'\">x</button><button @on.click=\".url = 'javascript:alert(2)'\">y</button></div>",
      ),
    },
    name="Linker",
    init=LinkState::{ url: "/safe", },
  )
}

///|
/// What an App is mounted with.
priv enum FilterMode {
  /// Whatever `App::new` installs — the thing most of these are about.
  Default
  /// The same, plus a rule of the host's own BEHIND it. There is no mode for
  /// "instead of": `add_filter` appends and nothing replaces.
  Extra
}

///|
/// A host's own rule, of the kind `add_filter` is for: it drops `class`, which
/// no built-in rule touches, so a test can tell which of the two ran.
priv struct ClassDropper {
  mut dropped : Int
}

///|
impl @filter.VdomFilter for ClassDropper with fn filter_elem(self, el) {
  if el.attrs.contains("class") {
    el.attrs.remove("class")
    self.dropped = self.dropped + 1
  }
}

///|
fn mk_filtered_app(
  mode : FilterMode,
) -> (@app.App[@memdom.MemNode], @memdom.MemNode, ClassDropper) raise {
  let scope = @component.ComponentStack::new()
  scope.register_components([link_component()])
  guard scope.lookup_component("Linker") is Some(c) else {
    fail("component missing")
  }
  let doc = @memdom.document()
  let container = @vdom.DomNode::create_element(doc, "DIV", None, None)
  let f = ClassDropper::{ dropped: 0, }
  let a = @app.App::new(
    scope,
    c.make(Map([])),
    container,
    @vdom.RenderOpts::new(doc),
  )
  match mode {
    Default => ()
    Extra => a.add_filter(f)
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
/// There is no policy that turns the URL rule off, which is the point of the
/// seam taking a POLICY rather than a filter.
///
/// A sanitizer decides names, raw markup and CSS. The URL rule and the `on*`
/// rule are not in it and have nothing to configure — a view has no legitimate
/// `javascript:` URL — so the widest sanitizer a host can write still gets
/// them. `set_filter(None)`, which did turn them off, is gone.
test "no sanitizer a host can install removes the URL rule" {
  let (a, container, _f) = mk_filtered_app(Default)
  // As permissive as the config model goes: raw markup permitted, nothing
  // removed, no allow-list narrowing anything.
  a.set_sanitizer(
    @sanitize.Sanitizer::new({
      ..@sanitize.SanitizerConfig::default(),
      raw_markup: Some(true),
    }),
  )
  guard find_el(container, "BUTTON") is Some(btn) else { fail("no button") }
  assert_true(a.dispatch(btn, @render.DomEvent::new(name="click")))
  let html = container.to_html()
  assert_false(html.contains("javascript:"))
  assert_true(html.contains("class=\"link\""))
  debug_inspect(
    a.take_filter_reports().map(@filter.Dropped::to_string),
    content=(
      #|["dropped href on <A>: URL scheme is not one a view may navigate to (javascript:alert(1))"]
    ),
  )
}

///|
/// A value the static pass could not have seen — it arrives from state, and
/// only at render — is dropped before the DOM is written.
test "a host's own filter runs behind the built-in chain, not instead of it" {
  let (a, container, f) = mk_filtered_app(Extra)
  // The addition ran: `class` is gone, and no built-in rule would have taken
  // it. The initial URL is fine and survives, so the addition did not replace
  // the rule that decides that either.
  let html = container.to_html()
  assert_true(html.contains("href=\"/safe\""))
  assert_false(html.contains("class="))
  assert_true(f.dropped > 0)

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
  // ...and the DOM never saw it, which is the built-in rule still running with
  // a host's own filter installed.
  let html = container.to_html()
  assert_false(html.contains("javascript:"))
  // The element stayed: an attribute was dropped, not a node.
  assert_true(html.contains(">go<"))
  debug_inspect(
    a.take_filter_reports().map(@filter.Dropped::to_string),
    content=(
      #|["dropped href on <A>: URL scheme is not one a view may navigate to (javascript:alert(1))"]
    ),
  )
}

///|
/// Installing takes effect from the next render rather than retroactively —
/// what is already in the DOM stays until something re-renders over it, for
/// the same reason a policy applies at load.
test "a filter added after mount applies from the next render" {
  // Mounted with the default chain, which does not touch `class`, so there is
  // something in the DOM for the addition to not reach back for.
  let (a, container, _f) = mk_filtered_app(Default)
  assert_true(container.to_html().contains("class=\"link\""))

  // Adding does NOT reach back into the DOM.
  let dropper = ClassDropper::{ dropped: 0, }
  a.add_filter(dropper)
  assert_true(container.to_html().contains("class=\"link\""))
  assert_eq(dropper.dropped, 0)

  // The next render is where it takes effect.
  guard find_el(container, "BUTTON") is Some(btn) else { fail("no button") }
  assert_true(a.dispatch(btn, @render.DomEvent::new(name="click")))
  assert_false(container.to_html().contains("class="))
  assert_true(dropper.dropped > 0)
}

// ---------------------------------------------------------------------------
// Doing the work once.
//
// The filter runs where a component subtree is BUILT, and stops at nested
// §Comp§ boundaries because those were filtered at their own sites. These two
// tests are that claim, counted.

///|
/// Counts elements it is shown, so a test can say how much of the tree the
/// filter actually walked.
priv struct CountingFilter {
  mut elems : Int
}

///|
impl @filter.VdomFilter for CountingFilter with fn filter_elem(self, _el) {
  self.elems = self.elems + 1
}

///|
priv struct ChildState {
  label : String
}

///|
impl @component.Fields for ChildState with fn encode(s) {
  { "label": Str(s.label) }
}

///|
impl @component.Fields for ChildState with fn decode(f) {
  guard f.get("label") is Some(Str(v)) else { return None }
  Some({ label: v, })
}

///|
impl @component.Fields for ChildState with fn schema() {
  @component.SchemaInfo::new(fingerprint="f_child_state", fields=[
    @component.FieldInfo::new("label", TyText),
  ])
}

///|
fn child_comp() -> @component.Component {
  @component.component(
    views={
      "main": @anode.View::new(
        "main",
        raw_view="<li><span><x text=\".label\"></x></span><em>x</em></li>",
      ),
    },
    name="FChild",
    init=ChildState::{ label: "a", },
  )
}

///|
priv struct ParentState {
  title : String
}

///|
impl @component.Fields for ParentState with fn encode(s) {
  { "title": Str(s.title) }
}

///|
impl @component.Fields for ParentState with fn decode(f) {
  guard f.get("title") is Some(Str(v)) else { return None }
  Some({ title: v, })
}

///|
impl @component.Fields for ParentState with fn schema() {
  @component.SchemaInfo::new(fingerprint="f_parent_state", fields=[
    @component.FieldInfo::new("title", TyText),
    @component.FieldInfo::new("kid", TyComp(Some("FChild"))),
  ])
}

///|
fn parent_comp() -> @component.Component {
  @component.component(
    views={
      "main": @anode.View::new(
        "main",
        raw_view="<div><h1><x text=\".title\"></x></h1><button @on.click=\".title = 'z'\">b</button><x render=\".kid\"></x></div>",
      ),
    },
    name="FParent",
    init=ParentState::{ title: "t", },
  )
}

///|
fn mk_counted() -> (@app.App[@memdom.MemNode], @memdom.MemNode, CountingFilter) raise {
  let scope = @component.ComponentStack::new()
  scope.register_components([child_comp(), parent_comp()])
  guard scope.lookup_component("FParent") is Some(p) else { fail("no FParent") }
  let doc = @memdom.document()
  let container = @vdom.DomNode::create_element(doc, "DIV", None, None)
  let f = CountingFilter::{ elems: 0, }
  let a = @app.App::new(
    scope,
    p.make({ "title": Str("t") }),
    container,
    @vdom.RenderOpts::new(doc),
  )
  a.add_filter(f)
  a.start()
  (a, container, f)
}

///|
/// Everything is built on the first render, so everything is filtered — the
/// parent's own `div`/`h1`/`button` at its site, and the child's
/// `li`/`span`/`em` at ITS site. Six elements, each seen exactly once. If the
/// parent also descended into the nested boundary they would be seen nine
/// times.
test "the first render filters every element exactly once" {
  let (_a, container, f) = mk_counted()
  assert_true(container.to_html().contains("<em>"))
  inspect(f.elems, content="6")
}

///|
/// The point of filtering where a subtree is BUILT. Changing the parent's
/// title rebuilds the parent and nothing else; the child is a cache hit, and
/// the filter never sees it. Over the finished tree this would be 6 again, on
/// this render and on every render after it.
test "a rebuild filters only what was rebuilt" {
  let (a, container, f) = mk_counted()
  f.elems = 0
  guard find_el(container, "BUTTON") is Some(btn) else { fail("no button") }
  assert_true(a.dispatch(btn, @render.DomEvent::new(name="click")))
  // The parent really did re-render.
  assert_true(container.to_html().contains("z"))
  // ...and the child is still there, unfiltered this time because unchanged.
  assert_true(container.to_html().contains("<em>"))
  inspect(f.elems, content="3")
}

///|
/// Changing the policy drops the render cache, so the new rules see the whole
/// tree rather than only what happens to rebuild next.
///
/// The same reason adding a filter does: a cached subtree carries the verdict
/// of whichever chain was installed when it was BUILT, so keeping it would mean
/// a newly installed policy silently never saw most of the page. This is the
/// counter-example to "a rebuild filters only what was rebuilt" above — after a
/// policy change, everything is a rebuild.
test "changing the policy re-filters the whole tree" {
  let (a, container, f) = mk_counted()
  f.elems = 0
  a.set_sanitizer(@sanitize.Sanitizer::default())
  guard find_el(container, "BUTTON") is Some(btn) else { fail("no button") }
  assert_true(a.dispatch(btn, @render.DomEvent::new(name="click")))
  assert_true(container.to_html().contains("z"))
  // Six, not the three that changed: the child was rebuilt too.
  inspect(f.elems, content="6")
}

// ---------------------------------------------------------------------------
// `@setinnermd`, end to end

///|
priv struct BodyState {
  body : String
}

///|
impl @component.Fields for BodyState with fn encode(s) {
  { "body": Str(s.body) }
}

///|
impl @component.Fields for BodyState with fn decode(f) {
  guard f.get("body") is Some(Str(v)) else { return None }
  Some({ body: v, })
}

///|
impl @component.Fields for BodyState with fn schema() {
  @component.SchemaInfo::new(fingerprint="body_state", fields=[
    @component.FieldInfo::new("body", TyText),
  ])
}

///|
/// A component whose whole content is markdown from its own state — the shape
/// of a comment renderer, a CMS body, or an LLM response.
fn md_component() -> @component.Component {
  @component.component(
    views={
      "main": @anode.View::new(
        "main",
        raw_view="<div><article @setinnermd=\".body\"></article><button @on.click=\".body = '## two [x](javascript:alert(1))'\">x</button></div>",
      ),
    },
    name="Bodied",
    init=BodyState::{ body: "# one\n\n*hi* <script>alert(1)</script>", },
  )
}

///|
fn mk_md_app() -> (@app.App[@memdom.MemNode], @memdom.MemNode) raise {
  let scope = @component.ComponentStack::new()
  scope.register_components([md_component()])
  guard scope.lookup_component("Bodied") is Some(c) else {
    fail("component missing")
  }
  let doc = @memdom.document()
  let container = @vdom.DomNode::create_element(doc, "DIV", None, None)
  let a = @app.App::new(
    scope,
    c.make(Map([])),
    container,
    @vdom.RenderOpts::new(doc),
  )
  a.start()
  (a, container)
}

///|
/// The headline: an app nobody configured renders markdown, and the payload's
/// `<script>` never becomes an element — through the SAME sanitizer that judges
/// every other node, with no permission granted anywhere.
///
/// The assertion is on the DOM rather than on `to_html()`, and that distinction
/// matters here more than anywhere else in this file. memdom's serializer does
/// no entity escaping — it says so at the top of `vdom/memdom/serialize.mbt` —
/// so the characters `<script>` DO appear in its output. They are a TEXT node:
/// upstream's inline parser never produces raw markup for a bare tag, and the
/// builder turns the resulting bogus autolink into literal text, which reaches
/// the browser through `createTextNode` and is inert. A test that asserted on
/// the serialized string would have read that as a hole and been wrong; one
/// that asserted the string is clean would pass only because of how a test aid
/// prints. Asking the tree what elements exist is the question with an answer.
test "an app renders setinnermd by default, and a script never becomes an element" {
  let (_a, container) = mk_md_app()
  guard find_el(container, "ARTICLE") is Some(article) else {
    fail("no article")
  }
  assert_true(container.to_html().contains("<h1>one</h1>"))
  assert_true(container.to_html().contains("<em>hi</em>"))
  // No SCRIPT element anywhere, which is the claim that matters.
  assert_true(find_el(article, "SCRIPT") is None)
  // The characters survive as text, which is what a reader should see.
  assert_true(container.to_html().contains("<script>alert(1)</script>"))
}

///|
/// **`set_inner_html` was never called.** This is the claim the whole design
/// rests on: the markdown became elements through `create_element`, so the
/// browser never re-parses a string this code produced, and there is no second
/// parser to disagree with. memdom counts real writes, so this is a fact about
/// the run rather than about the intent.
test "setinnermd never touches set_inner_html" {
  let (a, container) = mk_md_app()
  inspect(container.inner_html_sets, content="0")
  // ...and still not after a re-render with different markdown.
  guard find_el(container, "BUTTON") is Some(btn) else { fail("no button") }
  assert_true(a.dispatch(btn, @render.DomEvent::new(name="click")))
  inspect(container.inner_html_sets, content="0")
}

///|
/// The content tracks state, and the URL rule reaches values that arrive only
/// on a later render — the case a registration-time pass cannot see at all.
test "setinnermd re-renders, and the url rule follows the new value" {
  let (a, container) = mk_md_app()
  guard find_el(container, "BUTTON") is Some(btn) else { fail("no button") }
  assert_true(a.dispatch(btn, @render.DomEvent::new(name="click")))
  let html = container.to_html()
  assert_true(html.contains("<h2>two "))
  assert_false(html.contains("<h1>"))
  // The link kept its words and lost its destination.
  assert_true(html.contains("<a>x</a>"))
  assert_false(html.contains("javascript:"))
  debug_inspect(
    a.take_filter_reports().map(@filter.Dropped::to_string),
    content=(
      #|["dropped href on <ARTICLE>: URL scheme is not one a view may navigate to (javascript:alert(1))"]
    ),
  )
}

// ---------------------------------------------------------------------------
// The list-valued URL attribute.
//
// These assert on `props`, not on `to_html()`. That is the point: on `<form
// action>` the live property leaves no attribute behind, so HTML-reading
// assertions — which is what the tests above are — cannot see this bug at all.

///|
priv struct LinksState {
  links : Array[String]
}

///|
impl @component.Fields for LinksState with fn encode(s) {
  { "links": List(s.links.map(fn(x) { Str(x) })) }
}

///|
impl @component.Fields for LinksState with fn decode(f) {
  guard f.get("links") is Some(List(vs)) else { return None }
  let out = []
  for v in vs {
    guard v is Str(s) else { return None }
    out.push(s)
  }
  Some({ links: out, })
}

///|
impl @component.Fields for LinksState with fn schema() {
  @component.SchemaInfo::new(fingerprint="links_state", fields=[
    @component.FieldInfo::new("links", TyList(TyText)),
  ])
}

///|
fn mk_links_app() -> (@app.App[@memdom.MemNode], @memdom.MemNode) raise {
  let scope = @component.ComponentStack::new()
  let c = @component.component(
    views={
      "main": @anode.View::new(
        "main",
        raw_view="<div><a :href=\".links\" class=\"link\" @text=\"'go'\"></a><form :action=\".links\"></form></div>",
      ),
    },
    name="Linker",
    init=LinksState::{ links: ["javascript:alert(document.cookie)"], },
  )
  scope.register_components([c])
  let doc = @memdom.document()
  let container = @vdom.DomNode::create_element(doc, "DIV", None, None)
  let a = @app.App::new(
    scope,
    c.make(Map([])),
    container,
    @vdom.RenderOpts::new(doc),
  )
  a.start()
  (a, container)
}

///|
/// The default filter drops it and says so.
test "a list-valued URL attribute is dropped by default" {
  let (a, container) = mk_links_app()
  guard find_el(container, "A") is Some(anchor) else { fail("no anchor") }
  guard find_el(container, "FORM") is Some(form) else { fail("no form") }
  // Neither the property path nor the attribute path carries it.
  assert_false(anchor.props.contains("href"))
  assert_false(anchor.attrs.contains("href"))
  assert_false(form.props.contains("action"))
  assert_false(form.attrs.contains("action"))
  // The elements stayed; an attribute was dropped, not a node.
  assert_true(anchor.attrs.get("class") == Some("link"))
  debug_inspect(
    a.take_filter_reports().map(@filter.Dropped::to_string),
    content=(
      #|[
      #|  "dropped href on <A>: a structured value cannot be a URL ([\"javascript:alert(document.cookie)\"])",
      #|  "dropped action on <FORM>: a structured value cannot be a URL ([\"javascript:alert(document.cookie)\"])",
      #|]
    ),
  )
}

///|
/// The second layer — `set_prop` refusing to put a structured value on the
/// `href` PROPERTY, whatever the filter did — is not reachable from here any
/// more, since an app always filters. It is pinned where it lives:
/// `vdom/memdom/custom_element_test.mbt`, "a structured value does not skip
/// never_assign".

// ---------------------------------------------------------------------------
// `@setinnerhtml` and `@setinnersvg`, end to end
//
// The same shape as the markdown suite above, and the same headline claim: an
// app nobody configured renders a runtime markup payload with the dangerous
// parts already gone, through the sanitizer that judges every other node, with
// no permission granted anywhere.

///|
/// A component whose content is HTML and SVG from its own state — the shape of
/// a CMS body and of a server-computed chart.
fn safe_markup_component() -> @component.Component {
  @component.component(
    views={
      "main": @anode.View::new(
        "main",
        raw_view="<div><article @setinnerhtml=\".body\"></article><svg @setinnersvg=\".body\"></svg><button @on.click=\".body = '<a href=\\'javascript:alert(2)\\'>later</a>'\">x</button></div>",
      ),
    },
    name="Marked",
    init=BodyState::{
      body: "<b>ok</b><script>alert(1)</script><style>b{display:none}</style>",
    },
  )
}

///|
fn mk_safe_app() -> (@app.App[@memdom.MemNode], @memdom.MemNode) raise {
  let scope = @component.ComponentStack::new()
  scope.register_components([safe_markup_component()])
  guard scope.lookup_component("Marked") is Some(c) else {
    fail("component missing")
  }
  let doc = @memdom.document()
  let container = @vdom.DomNode::create_element(doc, "DIV", None, None)
  let a = @app.App::new(
    scope,
    c.make(Map([])),
    container,
    @vdom.RenderOpts::new(doc),
  )
  a.start()
  (a, container)
}

///|
/// Asserted on the TREE rather than on `to_html()`, for the reason the markdown
/// suite spells out: memdom's serializer does no entity escaping, so the
/// characters of a dropped tag can appear in its output as an inert text node
/// and a string assertion would misread that. Asking what elements exist is the
/// question with an answer.
test "an app renders setinnerhtml by default, with the dangerous parts gone" {
  let (_a, container) = mk_safe_app()
  guard find_el(container, "ARTICLE") is Some(article) else {
    fail("no article")
  }
  assert_true(find_el(article, "B") is Some(_))
  assert_true(find_el(article, "SCRIPT") is None)
  assert_true(find_el(article, "STYLE") is None)
}

///|
/// **`set_inner_html` was never called**, for either directive. The claim the
/// whole design rests on, and the one that makes the names honest: the payload
/// became elements through `create_element`, so the browser never re-parses a
/// string this code produced and there is no second parser to disagree with.
test "the safe markup directives never touch set_inner_html" {
  let (a, container) = mk_safe_app()
  inspect(container.inner_html_sets, content="0")
  guard find_el(container, "BUTTON") is Some(btn) else { fail("no button") }
  assert_true(a.dispatch(btn, @render.DomEvent::new(name="click")))
  inspect(container.inner_html_sets, content="0")
}

///|
/// A value that arrives only on a later render is the case a registration-time
/// pass cannot see at all, which is the entire reason there is a Pass 2. The
/// link keeps its words and loses its destination, and the host is told why.
test "a payload that arrives on a later render is filtered too" {
  let (a, container) = mk_safe_app()
  let _ = a.take_filter_reports()
  guard find_el(container, "BUTTON") is Some(btn) else { fail("no button") }
  assert_true(a.dispatch(btn, @render.DomEvent::new(name="click")))
  let html = container.to_html()
  assert_true(html.contains("<a>later</a>"))
  assert_false(html.contains("javascript:"))
  let reports = a.take_filter_reports().map(@filter.Dropped::to_string)
  assert_true(
    reports.contains(
      "dropped href on <ARTICLE>: URL scheme is not one a view may navigate to (javascript:alert(2))",
    ),
  )
}
