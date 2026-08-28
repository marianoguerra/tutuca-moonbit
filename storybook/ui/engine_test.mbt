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
  match f(args, @tutuca.NullCtx::{ }) {
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

///|
/// Recording the gallery, end to end.
///
/// The claim is not that a button exists: it is that pressing Record installs a
/// recorder on the app's own transactor, that driving a story afterwards is
/// captured, and that pressing Stop hands the recording back as something the
/// Trace tab can show. Every one of those crosses the component/host line,
/// which is the part of this that could be wrong.
test "the gallery records what a story did, and shows it back" {
  let sections = pick(["counter"])
  let (doc, container) = @harness.new_mount()
  let app = mount(sections, container, @vdom.RenderOpts::new(doc))
  let h = @harness.Harness::over(app, container)
  // Nothing is recording until somebody asks. That is the default and the
  // whole point.
  assert_false(app.transactor.recorder().recording())
  h.click(".trace-tab")
  assert_eq(h.find_all(".recorder-bar").length(), 1)
  assert_eq(h.find_all(".rec-start").length(), 1)
  h.click(".rec-start")
  h.click(".picker-go")
  assert_true(app.transactor.recorder().recording())
  assert_eq(h.find_all(".rec-stop").length(), 1)
  // Back to the story to actually use it, which is the flow: you press Record
  // on the Trace tab, drive the thing on the Story tab, and come back to read
  // what happened. The recorder is on the transactor, not on the tab, so
  // switching away does not stop it.
  h.click(".story-tab")
  h.click(".btn-success")
  h.click(".btn-success")
  h.click(".trace-tab")
  h.click(".rec-stop")
  // Back to recording nothing, and not merely "stopped": leaving a live
  // recorder installed after Stop would be the gallery quietly still
  // recording.
  assert_false(app.transactor.recorder().recording())
  // And the recording is there, showing the two clicks it captured.
  assert_eq(h.find_all(".panel-trace").length(), 1)
  let names = h.texts(".row-name")
  assert_true(names.contains("inc"))
  assert_eq(names.filter(n => n == "inc").length(), 2)
}

///|
/// A narrower scope is not a filter applied afterwards: it is what the recorder
/// keeps, as it happens. A gallery is ONE transactor with every story mounted
/// under it, so this is the only way "record only this example" can mean
/// anything at all.
test "recording one example keeps only that example" {
  let sections = pick(["counter", "traffic-light"])
  let (doc, container) = @harness.new_mount()
  let app = mount(sections, container, @vdom.RenderOpts::new(doc))
  let h = @harness.Harness::over(app, container)
  h.click(".trace-tab")
  h.click(".rec-start")
  h.click(".pick-example")
  h.click(".picker-go")
  h.click(".story-tab")
  h.click(".btn-success")
  h.click(".trace-tab")
  h.click(".rec-stop")
  // The addresses are relative to the story, so a reader knows what they mean —
  // and the header says the paths were rewritten rather than leaving them to
  // be misread.
  assert_eq(h.find_all(".header-relocated").length(), 1)
  assert_eq(h.texts(".row-name"), ["inc"])
  assert_eq(h.texts(".row-place"), ["(root)"])
}

///|
/// A recording survives you looking away from it. The explorer is dropped when
/// its tab closes because it is a whole component tree nobody is looking at;
/// a recording is not, and a panel that reset itself would lose the session
/// that was just captured.
test "the recording survives leaving the tab" {
  let sections = pick(["counter"])
  let (doc, container) = @harness.new_mount()
  let app = mount(sections, container, @vdom.RenderOpts::new(doc))
  let h = @harness.Harness::over(app, container)
  h.click(".trace-tab")
  h.click(".rec-start")
  h.click(".picker-go")
  h.click(".story-tab")
  h.click(".btn-success")
  h.click(".trace-tab")
  h.click(".rec-stop")
  let before = h.texts(".row-name").length()
  h.click(".story-tab")
  assert_eq(h.find_all(".trace-row").length(), 0)
  h.click(".trace-tab")
  assert_eq(h.texts(".row-name").length(), before)
}

///|
/// Discard means discard.
test "discarding a recording puts the panel back where it started" {
  let sections = pick(["counter"])
  let (doc, container) = @harness.new_mount()
  let app = mount(sections, container, @vdom.RenderOpts::new(doc))
  let h = @harness.Harness::over(app, container)
  h.click(".trace-tab")
  h.click(".rec-start")
  h.click(".picker-go")
  h.click(".story-tab")
  h.click(".btn-success")
  h.click(".trace-tab")
  h.click(".rec-stop")
  assert_eq(h.find_all(".panel-trace").length(), 1)
  h.click(".rec-clear")
  assert_eq(h.find_all(".panel-trace").length(), 0)
  assert_eq(h.find_all(".panel-empty").length(), 1)
}

///|
/// Selection mode, end to end.
///
/// The claim: a person can point at a row instead of spelling `.s0.rows[1]`,
/// and what comes back is the ancestry the renderer itself stamped into the
/// DOM. Every step of that crosses the component/host line — the click is the
/// host's, the intent is the component's, the panel is the host's again — which
/// is the part of this that could be wrong.
test "clicking the page offers the components under it" {
  let sections = pick(["counter"])
  let (doc, container) = @harness.new_mount()
  let app = mount(sections, container, @vdom.RenderOpts::new(doc))
  let h = @harness.Harness::over(app, container)
  h.click(".trace-tab")
  h.click(".rec-start")
  h.click(".picker-go")
  h.click(".story-tab")
  h.click(".btn-success")
  h.click(".trace-tab")
  h.click(".rec-stop")
  // Before any click, the picker offers what the RECORDING touched.
  assert_eq(h.text(".places-heading"), "Relocate to")
  // Selection mode on. The button says so, because clicking the page is about
  // to mean something different from clicking the page.
  h.click(".tab-select")
  inspect(h.text(".tab-select"), content="Click an element…")
  // The glue's half: a node, turned into the ancestry under it. This is
  // exactly what a document listener would hand over — and the node has to be
  // on screen to be clicked, so the story is what is showing.
  h.click(".story-tab")
  // Picked while the story is showing, which is when a real click happens: the
  // pane re-renders on a tab switch, so a node kept across one is detached and
  // walks up to nothing.
  let found = pick_at(app, h.find(".stat-value"), container)
  h.click(".trace-tab")
  // The shell, then the story's counter — outermost first, each named by the
  // instance its address resolves to rather than by the render-time id, which
  // is a process-global counter and means nothing outside this run.
  assert_eq(found.map(c => c.1), ["Storybook", "Counter"])
  // And the host's half: the shell forwards it, the host stores it and rebuilds
  // the panel around it.
  let payload : Array[@tutuca.Value] = found.map(c => {
    Map({ "place": Str(c.0), "component": Str(c.1) })
  })
  h.send_at_root("onTraceCandidates", args=[List(payload)])
  assert_eq(h.text(".places-heading"), "Components under what you clicked")
  assert_eq(h.texts(".place-component"), ["Storybook", "Counter"])
  // Picking one keeps it, rather than acting on it: choosing a place is the
  // thing a person does several times before they mean it.
  h.click(".trace-place", nth=1)
  assert_true(
    h
    .attr(".trace-place", "class", nth=1)
    .unwrap_or("")
    .contains("ring-primary/40"),
  )
  // And selection mode is off again — a click was what it was waiting for.
  inspect(h.text(".tab-select"), content="Pick a component")
}

///|
/// Turning selection mode off puts the recording's own places back. A stale
/// list of candidates from a click nobody remembers making is worse than no
/// list.
test "leaving selection mode restores the recording's own places" {
  let sections = pick(["counter"])
  let (doc, container) = @harness.new_mount()
  let app = mount(sections, container, @vdom.RenderOpts::new(doc))
  let h = @harness.Harness::over(app, container)
  h.click(".trace-tab")
  h.click(".rec-start")
  h.click(".picker-go")
  h.click(".story-tab")
  h.click(".btn-success")
  h.click(".trace-tab")
  h.click(".rec-stop")
  h.click(".tab-select")
  h.click(".story-tab")
  let found = pick_at(app, h.find(".stat-value"), container)
  h.click(".trace-tab")
  h.send_at_root("onTraceCandidates", args=[
    List(found.map(c => Map({ "place": Str(c.0), "component": Str(c.1) }))),
  ])
  assert_eq(h.text(".places-heading"), "Components under what you clicked")
  h.click(".tab-select")
  h.click(".tab-select")
  assert_eq(h.text(".places-heading"), "Relocate to")
}

///|
/// A recording scoped to one story has story-relative addresses, so a candidate
/// has to be one too — offering an address the recording cannot be cut to would
/// be offering an empty trace.
test "candidates are relative to the story a scoped recording is about" {
  let sections = pick(["counter", "traffic-light"])
  let (doc, container) = @harness.new_mount()
  let app = mount(sections, container, @vdom.RenderOpts::new(doc))
  let h = @harness.Harness::over(app, container)
  h.click(".trace-tab")
  h.click(".rec-start")
  h.click(".pick-example")
  h.click(".picker-go")
  h.click(".story-tab")
  h.click(".btn-success")
  h.click(".trace-tab")
  h.click(".rec-stop")
  h.click(".tab-select")
  h.click(".story-tab")
  let found = pick_at(app, h.find(".stat-value"), container)
  h.click(".trace-tab")
  h.send_at_root("onTraceCandidates", args=[
    List(found.map(c => Map({ "place": Str(c.0), "component": Str(c.1) }))),
  ])
  // The shell is above the cut and drops out; the story becomes the root.
  assert_eq(h.texts(".place-component"), ["Counter"])
  assert_eq(h.texts(".place-label"), ["(the whole thing)"])
}

///|
/// The gate a host asks before it dispatches.
///
/// A pick and a use are two meanings for one click, and doing both is doing the
/// wrong one — so while the panel is waiting to be pointed at, the click is
/// consumed and the story never sees it.
test "a click is consumed only while the panel is waiting for one" {
  let sections = pick(["counter"])
  let (doc, container) = @harness.new_mount()
  let app = mount(sections, container, @vdom.RenderOpts::new(doc))
  let h = @harness.Harness::over(app, container)
  // Nothing is waiting, so nothing is claimed — the gallery behaves exactly as
  // it always did.
  assert_false(trace_selecting())
  assert_false(take_select_click(app, h.find(".btn-success"), container))
  h.click(".trace-tab")
  h.click(".rec-start")
  h.click(".picker-go")
  h.click(".story-tab")
  h.click(".btn-success")
  h.click(".trace-tab")
  h.click(".rec-stop")
  h.click(".tab-select")
  assert_true(trace_selecting())
  h.click(".story-tab")
  // Now it is, so the click is taken — and the counter does NOT move, which is
  // the whole point of the gate.
  let before = h.text(".stat-value")
  assert_true(take_select_click(app, h.find(".btn-success"), container))
  assert_eq(h.text(".stat-value"), before)
  // One click, and the panel is done waiting.
  assert_false(trace_selecting())
  h.click(".trace-tab")
  assert_eq(h.text(".places-heading"), "Components under what you clicked")
}

///|
/// The Fuzz tab derives its generators from the story's own spec block, and
/// runs them against the instance on screen.
///
/// The claim that makes the tab worth having: the component being driven is
/// the ONE the Story tab renders — `.sN`, the same field — so what a reader
/// watches mutate is what the rows say was sent. A second mount would make the
/// panel a report about something else.
test "the Fuzz tab drives the story on screen" {
  let sections = pick(["svg-bar-chart"])
  let (doc, container) = @harness.new_mount()
  let app = mount(sections, container, @vdom.RenderOpts::new(doc))
  let h = @harness.Harness::over(app, container)
  h.click(".fuzz-tab")
  // The knobs are there, so a plan was derived — `canRun` gates the whole
  // control block on the component carrying a block at all.
  assert_eq(h.find_all(".ctl-seed").length(), 1)
  assert_eq(h.find_all(".ctl-burst").length(), 1)
  assert_eq(h.find_all(".no-plan").length(), 0)
  // Six bars to start with, from the story's args.
  let before = h.find_all("rect").length()
  assert_eq(before, 6)
  h.click(".ctl-burst")
  fuzz_tick()
  // Forty generated dispatches ran, and each is a row.
  let rows = h.find_all(".fuzz-row")
  assert_eq(rows.length(), 40)
  // The chart moved: the run drove the instance the Story tab renders, not a
  // copy of it.
  assert_not_eq(h.find_all("rect").length(), before)
}

///|
/// A green verdict is a claim about the ENFORCEMENT, not about the generator
/// having found nothing.
///
/// `setValues []` is a legal dispatch that no button in `svg_more.html` can
/// produce, and the generator sends it. `neverEmpty` is what stands between it
/// and a chart with no bars — the runtime abandons the transition and refuses
/// — so the run holds AND the refusals are there to prove it got that far.
test "a run reaches the dispatches the invariant has to decline" {
  let sections = pick(["svg-bar-chart"])
  let (doc, container) = @harness.new_mount()
  let app = mount(sections, container, @vdom.RenderOpts::new(doc))
  let h = @harness.Harness::over(app, container)
  h.click(".fuzz-tab")
  h.click(".ctl-burst")
  fuzz_tick()
  assert_eq(h.texts(".verdict-kind"), ["held"])
  // At least one row was declined, by the invariant the block declares.
  //
  // This is the assertion that pins WHY a run steps on the tick rather than
  // inside the click that asked for it. A refusal is held for the length of a
  // dispatch and only the first one escapes, so a run driven from inside the
  // button's own chain would show an empty column here and a green verdict —
  // which is exactly what a component with no invariant at all looks like.
  let declined = h.texts(".row-refused")
  assert_true(declined.contains("neverEmpty"))
  // …and the chart still has bars, which is what the rule is for.
  assert_true(h.find_all("rect").length() > 0)
}

///|
/// The same seed draws the same script.
///
/// The claim the profiling story rests on: a run somebody records in DevTools
/// has to be the same run when they record it again.
test "a run is addressed by its seed" {
  fn names_at(seed : String) -> Array[String] raise {
    let sections = pick(["svg-bar-chart"])
    let (doc, container) = @harness.new_mount()
    let app = mount(sections, container, @vdom.RenderOpts::new(doc))
    let h = @harness.Harness::over(app, container)
    h.click(".fuzz-tab")
    h.type_into(".ctl-seed", seed)
    h.click(".ctl-burst")
    fuzz_tick()
    h.texts(".row-name")
  }

  let a = names_at("7")
  assert_eq(a.length(), 40)
  assert_eq(a, names_at("7"))
  assert_not_eq(a, names_at("8"))
}

///|
/// Reset puts the story back to what it was mounted with.
///
/// Remounting the value rather than undoing the dispatches, because rewinding
/// a component by sending it the reverse of what it received is not a thing
/// that exists.
test "reset puts the story back" {
  let sections = pick(["svg-bar-chart"])
  let (doc, container) = @harness.new_mount()
  let app = mount(sections, container, @vdom.RenderOpts::new(doc))
  let h = @harness.Harness::over(app, container)
  h.click(".fuzz-tab")
  let before = h.find_all("rect").length()
  h.click(".ctl-burst")
  fuzz_tick()
  assert_not_eq(h.find_all("rect").length(), before)
  h.click(".ctl-reset")
  assert_eq(h.find_all("rect").length(), before)
  // And the rows went with it: a reset that left the old script on screen
  // would be showing a run of a component that no longer exists.
  assert_eq(h.find_all(".fuzz-row").length(), 0)
}

///|
/// Play advances one dispatch per frame, and the frame comes from the host.
///
/// Headless there is no page, so `FuzzEffects::none()` never arms one and the
/// run sits at zero — which is the honest behaviour and worth pinning: the
/// yield is the browser's, and a gallery that advanced anyway would be
/// pretending to have one.
test "Play waits for a frame the host has to supply" {
  let sections = pick(["svg-bar-chart"])
  let (doc, container) = @harness.new_mount()
  let app = mount(sections, container, @vdom.RenderOpts::new(doc))
  let h = @harness.Harness::over(app, container)
  h.click(".fuzz-tab")
  h.click(".ctl-play")
  // Playing, and nothing has run: no frame ever arrived.
  assert_eq(h.find_all(".ctl-stop").length(), 1)
  assert_eq(h.find_all(".fuzz-row").length(), 0)
  // A frame, and exactly one dispatch lands.
  fuzz_tick()
  assert_eq(h.find_all(".fuzz-row").length(), 1)
  fuzz_tick()
  assert_eq(h.find_all(".fuzz-row").length(), 2)
  // Stop, and a stray frame is a no-op rather than a wrong answer.
  h.click(".ctl-stop")
  fuzz_tick()
  assert_eq(h.find_all(".fuzz-row").length(), 2)
}

///|
/// Step walks a run one dispatch at a time, and starts a new one when the last
/// is done.
///
/// The second half is the part worth pinning: "continue what is in progress"
/// and "there is nothing in progress" are different states, and a Step that
/// only knew the first is a button that goes dead at the end of a script.
test "Step walks a run, and restarts at the end of one" {
  let sections = pick(["svg-bar-chart"])
  let (doc, container) = @harness.new_mount()
  let app = mount(sections, container, @vdom.RenderOpts::new(doc))
  let h = @harness.Harness::over(app, container)
  h.click(".fuzz-tab")
  h.type_into(".ctl-steps", "3")
  for i in [1, 2, 3] {
    h.click(".ctl-step")
    fuzz_tick()
    assert_eq(h.find_all(".fuzz-row").length(), i)
  }
  // The script ran out and the run has a verdict.
  assert_eq(h.texts(".verdict-kind"), ["held"])
  // One more Step starts a new run rather than doing nothing.
  h.click(".ctl-step")
  fuzz_tick()
  assert_eq(h.find_all(".fuzz-row").length(), 1)
}

///|
/// A generated script sends nothing the story cannot answer.
///
/// `tabbed-ui` is the case that showed this was wrong: its `tab` field gets a
/// generated `tabLen` alongside `setTab`, and `tabLen` READS — it answers a
/// scalar rather than a successor, so the receive path leaves it `Unhandled`.
/// The generator drew it because it took its names from the full table of
/// generated callables rather than the half that writes, and every draw
/// surfaced as a refusal badge that looked exactly like a finding.
test "a run sends nothing the story leaves unhandled" {
  let sections = pick(["tabbed-ui"])
  let (doc, container) = @harness.new_mount()
  let app = mount(sections, container, @vdom.RenderOpts::new(doc))
  let h = @harness.Harness::over(app, container)
  h.click(".fuzz-tab")
  h.click(".ctl-burst")
  fuzz_tick()
  assert_eq(h.find_all(".fuzz-row").length(), 40)
  // No badge reading `unhandled`, and no row naming the reader.
  assert_false(h.texts(".row-refused").contains("unhandled"))
  assert_false(h.texts(".row-name").contains("tabLen"))
}

///|
/// The Spec and Raw tabs: what the story's component DECLARES, and the block
/// it declared it in.
///
/// They exist because that block became load-bearing at run time. The Fuzz tab
/// beside them derives a component's generators and its whole oracle from
/// `Component::spec`, so "what is this run held to" stopped being a question
/// you answer by opening the .html file and became one the pane has to answer
/// about the story on screen.
test "each story pane shows the block it was declared in" {
  let sections = pick(["counter"])
  let doc = @memdom.document()
  let container = @vdom.DomNode::create_element(doc, "DIV", None, None)
  let app = mount(sections, container, @vdom.RenderOpts::new(doc))
  assert_true(container.to_html().contains("spec-tab"))
  assert_true(container.to_html().contains("raw-tab"))
  let root = app.transactor.root
  // neither is built for a tab nobody opened: ~50 stories, and re-parsing
  // every block at mount to render none of them is pure cost
  assert_true(root.field("d0") is Null)
  assert_true(root.field("w0") is Null)

  let spec = shell_input(root, "onStoryTab", [Num(0), Str("spec")])
  assert_true(spec.field("t0") is Str("spec"))
  assert_true(spec.field("d0") is Obj(_))
  assert_true(spec.field("d0").field("hasSpec") is Bool(true))

  let raw = shell_input(spec, "onStoryTab", [Num(0), Str("raw")])
  assert_true(raw.field("w0") is Obj(_))
  // Verbatim, so it is the file's own bare `state { … }` and not the name the
  // parse gave it.
  let src = raw.field("w0").field("source").str(default="")
  assert_true(src.contains("state {"))
  assert_true(src.contains("count : Int"))

  // A declaration cannot go stale — the component behind a story is the one
  // thing about it that never changes — so leaving keeps both panels rather
  // than dropping them the way the explorer is dropped.
  let back = shell_input(raw, "onStoryTab", [Num(0), Str("story")])
  assert_true(back.field("t0") is Str("story"))
  assert_true(back.field("d0") is Obj(_))
  assert_true(back.field("w0") is Obj(_))
}

///|
/// The Spec tab RENDERS, not merely builds: the panel is made from the shell's
/// own Inspector, and a rendered instance resolves its component through the
/// app's registry — so an unregistered one draws nothing and the pane comes up
/// blank with every value-level assertion above still passing.
test "the Spec tab renders the declaration, not a blank pane" {
  let sections = pick(["counter"])
  let (doc, container) = @harness.new_mount()
  let app = mount(sections, container, @vdom.RenderOpts::new(doc))
  let h = @harness.Harness::over(app, container)
  h.click(".spec-tab")
  // the counter's arm, expanded, with the field it declares
  assert_true(h.texts(".comp-section").contains("Counter"))
  assert_true(h.texts(".spec-field-name").contains("count"))
  h.click(".raw-tab")
  assert_true(h.text(".spec-source-text").contains("count : Int"))
}
