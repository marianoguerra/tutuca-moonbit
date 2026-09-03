// Smoke: the gallery shell over a module defined right here. This package
// SHIPS and the example corpus does not, so the test that proves `mount` works
// may not reach for the corpus — a `for "test"` import block survives
// `moon publish`, and a shipping package that test-imports an excluded one
// puts an unresolvable name into the tarball. The corpus-driven version of
// this test lives in `storybook/examples/gallery_test.mbt`.

///|
priv struct CounterState {
  count : Int
}

///|
impl @tutuca.Fields for CounterState with fn schema() {
  @tutuca.SchemaInfo::new(fingerprint="counter_state", fields=[
    @tutuca.FieldInfo::new("count", TyInt(width=32, signed=true)),
  ])
}

///|
impl @tutuca.Fields for CounterState with fn encode(s) {
  { "count": Num(s.count.to_double()) }
}

///|
impl @tutuca.Fields for CounterState with fn decode(f) {
  guard f.get("count") is Some(Num(v)) else { return None }
  Some({ count: v.to_int(), })
}

///|
priv struct HelloState {
  who : String
}

///|
impl @tutuca.Fields for HelloState with fn schema() {
  @tutuca.SchemaInfo::new(fingerprint="hello_state", fields=[
    @tutuca.FieldInfo::new("who", TyText),
  ])
}

///|
impl @tutuca.Fields for HelloState with fn encode(s) {
  { "who": Str(s.who) }
}

///|
impl @tutuca.Fields for HelloState with fn decode(f) {
  guard f.get("who") is Some(Str(v)) else { return None }
  Some({ who: v, })
}

///|
fn counter_comp() -> @component.Component {
  @component.component(
    views={
      "main": @anode.View::new(
        "main",
        raw_view="<div class=\"counter\"><x text=\".count\"></x><button @on.click=\"inc\">+</button></div>",
      ),
    },
    name="Counter",
    initial=CounterState::{ count: 0, },
    update=(s : CounterState, msg, _ctx) => {
      match msg {
        Receive("inc", _) => Next({ count: s.count + 1, })
        _ => Unhandled
      }
    },
  )
}

///|
fn hello_comp() -> @component.Component {
  @component.component(
    views={
      "main": @anode.View::new(
        "main",
        raw_view="<p class=\"hello\">hello <x text=\".who\"></x></p>",
      ),
    },
    name="Hello",
    initial=HelloState::{ who: "world", },
  )
}

///|
fn demo_module() -> @component.ModuleDef {
  @component.ModuleDef::new(
    name="demo",
    components=[counter_comp(), hello_comp()],
    examples=[
      { component: "Counter", title: "Zero", args: Map([]), view: None, },
      {
        component: "Counter",
        title: "Seeded",
        args: { "count": Num(7) },
        view: None,
      },
      {
        component: "Hello",
        title: "",
        args: { "who": Str("gallery") },
        view: None,
      },
    ],
  )
}

///|
fn demo_sections() -> Array[@sb.Section] {
  @sb.sections_of(@sb.stories_of_module(demo_module(), section="Demo"), order=[
    "Demo",
  ])
}

///|
test "mounts a sidebar and the first story's live instance" {
  let sections = demo_sections()
  assert_eq(sections.length(), 1)
  assert_eq(sections[0].stories.length(), 3)
  let doc = @memdom.document()
  let container = @vdom.DomNode::create_element(doc, "DIV", None, None)
  let _app = mount(sections, container, @vdom.RenderOpts::new(doc))
  let html = container.to_html()
  // one sidebar entry per projected story, under the section it was given
  assert_true(html.contains("Demo"))
  assert_true(html.contains("nav-demo-counter-zero"))
  assert_true(html.contains("nav-demo-counter-seeded"))
  assert_true(html.contains("nav-demo-hello"))
  // the human title rule: "<component> · <example title>", bare when untitled
  assert_true(html.contains("Counter · Zero"))
  assert_true(html.contains("Hello"))
  // the chrome, and the first story mounted live (the renderer stamps data-cid)
  assert_true(html.contains("placeholder=\"Filter\""))
  assert_true(html.contains("data-cid"))
  assert_true(html.contains("class=\"counter\""))
}

///|
test "a story renders the args its example declared" {
  let stories = @sb.stories_of_module(demo_module())
  let seeded = stories[1]
  assert_eq(seeded.root, "Counter")
  assert_eq(seeded.args.get("count"), Some(@tutuca.Value::Num(7)))
  let doc = @memdom.document()
  let container = @vdom.DomNode::create_element(doc, "DIV", None, None)
  let _app = mount(
    @sb.sections_of([seeded]),
    container,
    @vdom.RenderOpts::new(doc),
  )
  assert_true(container.to_html().contains("7"))
}

///|
test "themes are the caller's to choose" {
  let doc = @memdom.document()
  let container = @vdom.DomNode::create_element(doc, "DIV", None, None)
  let _app = mount(demo_sections(), container, @vdom.RenderOpts::new(doc), themes=[
    "light", "dark",
  ])
  let html = container.to_html()
  // only the two offered palettes are in the switcher
  assert_true(html.contains(">light<"))
  assert_false(html.contains(">cyberpunk<"))
  assert_true(html.contains("class=\"counter\""))
}

///|
test "no panels means no tab strip" {
  // The default. A gallery that declares no panels draws stories and nothing
  // else — and this package imports nothing that could draw more.
  let doc = @memdom.document()
  let container = @vdom.DomNode::create_element(doc, "DIV", None, None)
  let _app = mount(demo_sections(), container, @vdom.RenderOpts::new(doc))
  let html = container.to_html()
  assert_false(html.contains("role=\"tablist\""))
  assert_false(html.contains("instance-tab"))
  // the default switcher is margaui's palette list
  assert_true(html.contains(">cyberpunk<"))
}

///|
/// A panel layer of one panel, built from a closure that says what it saw.
/// Enough to drive the whole seam without an inspector: the tab strip, the
/// lazy build, the field the value lands in, and the two host doors.
fn[N] marker_panels() -> PanelSet[N] {
  {
    ..PanelSet::none(),
    defs: [
      {
        key: "marker",
        label: "Marker",
        field: "m",
        build: Some((inst, read) => {
          Str(
            "built:\{inst.field("count").num(default=-1.0).to_int()}:\{read("knob").str(default="")}",
          )
        }),
        live: false,
        keep: true,
        with_story: false,
      },
    ],
    fields: { "knob": Str("set") },
  }
}

///|
test "a declared panel gets a tab, a field and a lazy build" {
  let doc = @memdom.document()
  let container = @vdom.DomNode::create_element(doc, "DIV", None, None)
  let app = mount(
    demo_sections(),
    container,
    @vdom.RenderOpts::new(doc),
    panels=marker_panels(),
  )
  let html = container.to_html()
  assert_true(html.contains("marker-tab"))
  assert_true(html.contains("Marker"))
  // built lazily: the field exists and is empty until the tab is opened
  assert_true(app.root_value().field("m0") is Null)
  app.send_at_root("onStoryTab", args=[Num(0), Str("marker")]) |> ignore
  // the builder saw the story's instance AND the gallery-wide field the panel
  // layer declared
  assert_eq(app.root_value().field("m0"), Str("built:0:set"))
  // the host can write one in from outside, addressed by key
  push_panel(app, 0, "marker", Str("pushed"))
  assert_eq(app.root_value().field("m0"), Str("pushed"))
  // …and setFields writes only names a panel declared
  set_panel_fields(app, { "knob": Str("moved"), "active": Str("nope") })
  assert_eq(app.root_value().field("knob"), Str("moved"))
  assert_eq(app.root_value().field("active"), Str("demo-counter-zero"))
}

///|
test "a story renders under the view its example named" {
  // ExampleDef.view is what the gallery used to drop on the floor: the story
  // pane resolved the component's default view no matter what the example said.
  let m = @component.ModuleDef::new(
    name="views",
    components=[
      @component.component(
        views={
          "main": @anode.View::new(
            "main",
            raw_view="<p class=\"as-main\">main</p>",
          ),
          "compact": @anode.View::new(
            "compact",
            raw_view="<p class=\"as-compact\">compact</p>",
          ),
        },
        name="Two",
        initial=HelloState::{ who: "x", },
      ),
    ],
    examples=[
      { component: "Two", title: "Default", args: Map([]), view: None, },
      {
        component: "Two",
        title: "Compact",
        args: Map([]),
        view: Some("compact"),
      },
    ],
  )
  let stories = @sb.stories_of_module(m)
  assert_eq(stories[1].view, "compact")
  let doc = @memdom.document()
  let container = @vdom.DomNode::create_element(doc, "DIV", None, None)
  let _app = mount(
    @sb.sections_of([stories[1]]),
    container,
    @vdom.RenderOpts::new(doc),
  )
  let html = container.to_html()
  assert_true(html.contains("as-compact"))
  assert_false(html.contains("as-main"))
}
