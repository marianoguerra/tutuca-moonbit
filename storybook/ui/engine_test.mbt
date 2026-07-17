// Smoke: mount a few stories on memdom and assert the gallery chrome + the
// first story's live preview render. Per-component behavior is covered by each
// example's own harness test; here we only check the storybook shell wiring.

///|
fn lint_text(comp : @component.Component) -> String {
  let findings = @cli.check_component(comp)
  if findings.is_empty() {
    "No issues found."
  } else {
    let lines : Array[String] = []
    for f in findings {
      lines.push(f.line())
    }
    lines.join("\n")
  }
}

///|
fn pick(ids : Array[String]) -> Array[@sb.Section] {
  let all = @sb.stories()
  let picked : Array[@sb.Story] = []
  for s in all {
    if ids.contains(s.id) {
      picked.push(s)
    }
  }
  @sb.sections_of(picked)
}

///|
test "storybook mounts sidebar + first preview" {
  let sections = pick(["counter", "traffic-light", "tabbed-ui", "lint-errors"])
  let doc = @memdom.document()
  let container = @vdom.DomNode::create_element(doc, "DIV", None, None)
  let _app = mount(
    sections,
    container,
    @vdom.RenderOpts::new(doc),
    lint=lint_text,
  )
  let html = container.to_html()
  // sidebar entries for every picked story
  assert_true(html.contains("nav-counter"))
  assert_true(html.contains("nav-traffic-light"))
  assert_true(html.contains("nav-tabbed-ui"))
  assert_true(html.contains("nav-lint-errors"))
  // entries show the human title + description (from meta_for), not the slug
  assert_true(html.contains("Traffic Light"))
  assert_true(html.contains("Cycle a light through red, orange, and green"))
  // the filter box chrome and at least one rendered instance (data-cid stamped)
  assert_true(html.contains("placeholder=\"Filter\""))
  assert_true(html.contains("data-cid"))
}

///|
test "init-driven story loads its data after mount" {
  // request-example has no lifecycle; the gallery must dispatch `init` and fan
  // it out to the pane, firing loadData. The fixture returns these rows, which
  // render as Entry cards — proving the pane is live, not just an empty shell.
  let sections = pick(["request-example"])
  let doc = @memdom.document()
  let container = @vdom.DomNode::create_element(doc, "DIV", None, None)
  let _app = mount(
    sections,
    container,
    @vdom.RenderOpts::new(doc),
    lint=lint_text,
  )
  let html = container.to_html()
  assert_true(html.contains("Tutuca"))
  assert_true(html.contains("MoonBit"))
}

///|
/// A fixture `loadState`/`persistState` pair standing in for the browser
/// history handlers the wasm host wires: `loadState` returns a fixed snapshot,
/// `persistState` is a no-op. Lets the headless test drive the URL-restore path.
fn url_fixture(
  story : String,
  focus : String,
  filter : String,
  theme? : String = "",
) -> Map[String, @component.RequestFn] {
  {
    "loadState": RequestFn((_args, respond) => {
      respond(
        Ok(
          Map({
            "story": Str(story),
            "focus": Str(focus),
            "filter": Str(filter),
            "theme": Str(theme),
          }),
        ),
      )
    }),
    "persistState": RequestFn((_args, respond) => respond(Ok(Null))),
  }
}

///|
/// Read a top-level field off the started gallery's root instance.
fn[N] root_field(app : @app.App[N], name : String) -> @tutuca.Value {
  match app.root_value() {
    Some(Obj(o)) => o.obj_field(name).unwrap_or(Null)
    _ => Null
  }
}

///|
test "fuzzy_match: substring, subsequence budget, and empty query" {
  // empty query matches anything
  assert_true(fuzzy_match("", "whatever"))
  // direct substring, case-insensitive
  assert_true(fuzzy_match("Count", "counter"))
  assert_true(fuzzy_match("light", "traffic light basics"))
  // near-contiguous subsequence within budget (t-r-a-f: gap of 1)
  assert_true(fuzzy_match("trf", "traffic"))
  // the same letters spread far apart exceed the query-scaled gap budget
  assert_false(fuzzy_match("tft", "traffic light"))
  // scattered letters across a long string exceed the gap budget
  assert_false(fuzzy_match("counter", "composition and views example"))
  // a query absent from the target never matches
  assert_false(fuzzy_match("zzz", "traffic light"))
}

///|
test "storybook renders the filter box, focus buttons, and collapse toggle" {
  let sections = pick(["counter", "traffic-light", "lint-errors"])
  let doc = @memdom.document()
  let container = @vdom.DomNode::create_element(doc, "DIV", None, None)
  let _app = mount(
    sections,
    container,
    @vdom.RenderOpts::new(doc),
    lint=lint_text,
  )
  let html = container.to_html()
  // the sidebar filter input
  assert_true(html.contains("placeholder=\"Filter\""))
  // the "hide sections" collapse toggle in the (shown) sidebar header
  assert_true(html.contains("«"))
  // a focus button for the active renderable story's pane (counter)
  assert_true(html.contains("Focus this story"))
  // collapsible group headers render the expand caret (groups start open;
  // @on.click handlers are directives, consumed at parse and not in the HTML)
  assert_true(html.contains("▾"))
}

///|
test "URL state restores the selected story, focus, and filter" {
  let sections = pick(["counter", "traffic-light", "tabbed-ui"])
  let doc = @memdom.document()
  let container = @vdom.DomNode::create_element(doc, "DIV", None, None)
  // restore: select traffic-light, focus tabbed-ui, filter "counter"
  let app = mount(
    sections,
    container,
    @vdom.RenderOpts::new(doc),
    lint=lint_text,
    url_handlers=url_fixture("traffic-light", "tabbed-ui", "counter"),
  )
  // selection + focus id came from the URL, overriding the default (counter)
  assert_true(root_field(app, "active") == Str("traffic-light"))
  assert_true(root_field(app, "focus") == Str("tabbed-ui"))
  assert_true(root_field(app, "filter") == Str("counter"))
  // focusValue holds the focused story's live instance (rendered in the overlay)
  assert_true(root_field(app, "focusValue") is Obj(_))
}

///|
test "URL state restores the theme into the switcher" {
  let sections = pick(["counter", "traffic-light"])
  let doc = @memdom.document()
  let container = @vdom.DomNode::create_element(doc, "DIV", None, None)
  let app = mount(
    sections,
    container,
    @vdom.RenderOpts::new(doc),
    lint=lint_text,
    url_handlers=url_fixture("", "", "", theme="dracula"),
  )
  // the resolved theme name syncs the switcher's shown value
  assert_true(root_field(app, "theme") == Str("dracula"))
}

///|
test "empty URL state keeps the default selection and clears focus" {
  let sections = pick(["counter", "traffic-light"])
  let doc = @memdom.document()
  let container = @vdom.DomNode::create_element(doc, "DIV", None, None)
  let app = mount(
    sections,
    container,
    @vdom.RenderOpts::new(doc),
    lint=lint_text,
    url_handlers=url_fixture("", "", ""),
  )
  // default selection is the first story; no focus
  assert_true(root_field(app, "active") == Str("counter"))
  assert_true(root_field(app, "focus") == Str(""))
  assert_true(root_field(app, "focusValue") is Null)
}

///|
test "lint callback surfaces findings for the lint-errors story" {
  // the callback the host wires must produce non-empty text for a component
  // that has lint issues, so the Lint panel is not blank.
  let sections = pick(["lint-errors"])
  let doc = @memdom.document()
  let container = @vdom.DomNode::create_element(doc, "DIV", None, None)
  let _app = mount(
    sections,
    container,
    @vdom.RenderOpts::new(doc),
    lint=lint_text,
  )
  let html = container.to_html()
  // lint-errors intentionally trips rules; the panel text lands in the pane
  assert_false(html.contains("No issues found."))
}
