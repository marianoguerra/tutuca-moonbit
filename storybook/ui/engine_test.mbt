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
  // the shell title and at least one rendered instance (data-cid stamped)
  assert_true(html.contains("Storybook"))
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
