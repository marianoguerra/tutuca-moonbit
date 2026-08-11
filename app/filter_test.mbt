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

// ---------------------------------------------------------------------------
// Doing the work once.
//
// The filter used to run over the FINISHED tree, which meant it re-walked every
// subtree the render cache had handed back unchanged — O(whole tree) beside a
// pipeline that is otherwise O(changed). It now runs where a component subtree
// is BUILT, and stops at nested §Comp§ boundaries because those were filtered
// at their own sites. These two tests are that claim, counted.

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
  Some({ label: v })
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
    init=ChildState::{ label: "a" },
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
  Some({ title: v })
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
        raw_view="<div><h1><x text=\".title\"></x></h1><button @on.click=\"setTitle 'z'\">b</button><x render=\".kid\"></x></div>",
      ),
    },
    name="FParent",
    init=ParentState::{ title: "t" },
  )
}

///|
fn mk_counted() -> (@app.App[@memdom.MemNode], @memdom.MemNode, CountingFilter) raise {
  let scope = @component.ComponentStack::new()
  scope.register_components([child_comp(), parent_comp()])
  guard scope.lookup_component("FParent") is Some(p) else { fail("no FParent") }
  let doc = @memdom.document()
  let container = @vdom.DomNode::create_element(doc, "DIV", None, None)
  let f = CountingFilter::{ elems: 0 }
  let a = @app.App::new(
    scope,
    p.make({ "title": Str("t") }),
    container,
    @vdom.RenderOpts::new(doc),
  )
  a.set_filter(Some(f))
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
  Some({ body: v })
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
        raw_view="<div><article @setinnermd=\".body\"></article><button @on.click=\"setBody '## two [x](javascript:alert(1))'\">x</button></div>",
      ),
    },
    name="Bodied",
    init=BodyState::{ body: "# one\n\n*hi* <script>alert(1)</script>" },
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

///|
/// Opting out is honest about it: with no filter, the directive renders an
/// empty element rather than markdown-as-text or markdown-as-markup.
test "set_filter(None) makes setinnermd render nothing" {
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
  a.set_filter(None)
  a.start()
  let html = container.to_html()
  assert_true(html.contains("<article></article>"))
  assert_false(html.contains("# one"))
}

// ---------------------------------------------------------------------------
// The list-valued URL attribute.
//
// A `list<string>` field bound to `href` is the shape of a guest field, and
// every layer between it and the DOM used to wave it through: `value_to_attr`
// makes it `Data`, `UrlFilter` skipped `Data` because a list is not a URL
// string, and `set_prop` sent `Data` down the property path AHEAD of the
// `never_assign` check that lists `href` for exactly this reason. In the
// browser the IDL setter takes ToString of the array, so a one-element list
// became its element: a live `javascript:` URL in the host's origin, from an
// untrusted bundle.
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
  { "links": List(s.links.map(fn(x) { @tutuca.Value::Str(x) })) }
}

///|
impl @component.Fields for LinksState with fn decode(f) {
  guard f.get("links") is Some(List(vs)) else { return None }
  let out = []
  for v in vs {
    guard v is Str(s) else { return None }
    out.push(s)
  }
  Some({ links: out })
}

///|
impl @component.Fields for LinksState with fn schema() {
  @component.SchemaInfo::new(fingerprint="links_state", fields=[
    @component.FieldInfo::new("links", TyList(TyText)),
  ])
}

///|
fn mk_links_app(
  filtered : Bool,
) -> (@app.App[@memdom.MemNode], @memdom.MemNode) raise {
  let scope = @component.ComponentStack::new()
  let c = @component.component(
    views={
      "main": @anode.View::new(
        "main",
        raw_view="<div><a :href=\".links\" class=\"link\" @text=\"'go'\"></a><form :action=\".links\"></form></div>",
      ),
    },
    name="Linker",
    init=LinksState::{ links: ["javascript:alert(document.cookie)"] },
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
  if !filtered {
    a.set_filter(None)
  }
  a.start()
  (a, container)
}

///|
/// The default filter drops it and says so.
test "a list-valued URL attribute is dropped by default" {
  let (a, container) = mk_links_app(true)
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
/// And with the filter off, `set_prop` still refuses to put it on the property
/// path — the second layer, which is what holds when a host opts out.
test "set_filter(None) still does not put a list on the href property" {
  let (a, container) = mk_links_app(false)
  guard find_el(container, "A") is Some(anchor) else { fail("no anchor") }
  // `href` is in `never_assign`, so it degrades to inert JSON text.
  assert_false(anchor.props.contains("href"))
  assert_true(
    anchor.attrs.get("href") == Some("[\"javascript:alert(document.cookie)\"]"),
  )
  debug_inspect(a.take_filter_reports().length(), content="0")
}
