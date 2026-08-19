// Smoke: mount a few stories on memdom and assert the gallery chrome + the
// first story's live preview render. Per-component behavior is covered by each
// example's own harness test; here we only check the storybook shell wiring.

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
  let _app = mount(sections, container, @vdom.RenderOpts::new(doc))
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
  let _app = mount(sections, container, @vdom.RenderOpts::new(doc))
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
) -> Map[String, Array[@component.IntentFn]] {
  {
    "loadState": [
      IntentFn((_call, answer) => {
        answer(
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
    ],
    "persistState": [IntentFn((_call, answer) => answer(Ok(Null)))],
  }
}

///|
/// Read a top-level field off the started gallery's root instance.
fn[N] root_field(app : @app.App[N], name : String) -> @tutuca.Value {
  app.root_value().field(name)
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
  let _app = mount(sections, container, @vdom.RenderOpts::new(doc))
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
    url_handlers=url_fixture("", "", ""),
  )
  // default selection is the first story; no focus
  assert_true(root_field(app, "active") == Str("counter"))
  assert_true(root_field(app, "focus") == Str(""))
  assert_true(root_field(app, "focusValue") is Null)
}

///|
/// Dispatch a shell input straight through the Obj trait and return the
/// successor root — the same route a click takes, without the DOM plumbing
/// this package has no glue for.
fn shell_input(
  root : @tutuca.Value,
  name : String,
  args : Array[@tutuca.Value],
) -> @tutuca.Value {
  guard root is Obj(o) else { return root }
  guard o.obj_handler(Receive, name) is Some(Handler(f)) else { return root }
  match f(args, @tutuca.NullCtx::{  }) {
    Some(node) => node
    None => root
  }
}

///|
/// Every story gets a Story | Instance tab pair, and the Instance pane shows
/// the inspector over that story's OWN instance.
///
/// The explorer reads the instance rather than being handed a descriptor
/// alongside it, which is what makes one per story affordable at all: the
/// gallery has no per-story inspector code, and never had anywhere to put any.
test "each story pane offers a live Instance tab" {
  let sections = pick(["counter", "traffic-light"])
  let doc = @memdom.document()
  let container = @vdom.DomNode::create_element(doc, "DIV", None, None)
  let app = mount(sections, container, @vdom.RenderOpts::new(doc))
  assert_true(container.to_html().contains("story-tab"))
  assert_true(container.to_html().contains("instance-tab"))
  let root = app.transactor.root
  // closed: the explorer is not built for a tab nobody opened
  assert_true(root.field("t0") is Str("story"))
  assert_true(root.field("i0") is Null)

  // open it: the explorer appears, over this story's instance
  let opened = shell_input(root, "onStoryTab", [Num(0), Str("instance")])
  assert_true(opened.field("t0") is Str("instance"))
  assert_true(opened.field("i0") is Obj(_))
  // ...and it is the InstanceExplorer, with the Component tab beside the
  // fields because the gallery's registry resolved the story's descriptor
  assert_true(opened.field("i0").field("hasComponent") is Bool(true))

  // LIVE: a story dispatch writes `s0` through the shell, and the explorer is
  // rebuilt in the same successor rather than showing the state as of the
  // moment the tab was opened.
  let story = opened.field("s0")
  assert_true(story.field("count") is Num(0.0))
  let bumped = story.call_field("setCount", [Num(7)])
  let after = opened.with_field("s0", bumped)
  assert_true(after.field("s0").field("count") is Num(7.0))
  let before_explorer = opened.field("i0")
  let after_explorer = after.field("i0")
  assert_true(after_explorer is Obj(_))
  @test.assert_not_same_object(after_explorer, before_explorer)

  // a story whose tab is CLOSED rebuilds nothing
  let quiet = root.with_field("s0", bumped)
  assert_true(quiet.field("i0") is Null)

  // closing drops the explorer: it is a whole component tree
  let closed = shell_input(opened, "onStoryTab", [Num(0), Str("story")])
  assert_true(closed.field("t0") is Str("story"))
  assert_true(closed.field("i0") is Null)
}

///|
/// First descendant of `n` (itself included) whose class list contains `cls`.
fn walk_by_class(n : @memdom.MemNode, cls : String) -> @memdom.MemNode? {
  if @vdom.DomWalk::attribute(n, "class") is Some(c) && c.contains(cls) {
    return Some(n)
  }
  for kid in @vdom.DomNode::child_nodes(n) {
    if walk_by_class(kid, cls) is Some(f) {
      return Some(f)
    }
  }
  None
}

///|
/// The Instance tab RENDERS, not merely builds.
///
/// The explorer is made from the shell's own Inspector, and a rendered
/// instance resolves its component through the app's registry by id — so an
/// inspector nobody registered draws nothing and the pane comes up blank, with
/// every value-level assertion above still passing. This drives the real
/// click and reads the DOM back.
test "the Instance tab renders the explorer, not a blank pane" {
  let sections = pick(["counter"])
  let doc = @memdom.document()
  let container = @vdom.DomNode::create_element(doc, "DIV", None, None)
  let app = mount(sections, container, @vdom.RenderOpts::new(doc))
  guard walk_by_class(container, "instance-tab") is Some(tab) else {
    fail("no Instance tab in the rendered gallery")
  }
  let _ = app.dispatch(tab, @render.DomEvent::new(name="click"))
  let html = container.to_html()
  // the counter's own field, shown as an InstanceFields row
  assert_true(html.contains(">count<"))
  // and the tab pair the explorer puts over it
  assert_true(html.contains("Component"))
}
