// The standard set, over a two-component module defined right here.
//
// `storybook/examples/gallery_test.mbt` drives these panels hard — recording,
// picking, whole fuzz runs — against this repo's corpus. What is left for this
// package's own suite is the wiring `all()` is: that every panel gets a tab,
// that its value lands in its own field, and that the two the host pushes come
// up empty rather than missing.

///|
priv struct CountState {
  count : Int
}

///|
impl @tutuca.Fields for CountState with fn schema() {
  @tutuca.SchemaInfo::new(fingerprint="count_state", fields=[
    @tutuca.FieldInfo::new("count", TyInt(width=32, signed=true)),
  ])
}

///|
impl @tutuca.Fields for CountState with fn encode(s) {
  { "count": Num(s.count.to_double()) }
}

///|
impl @tutuca.Fields for CountState with fn decode(f) {
  guard f.get("count") is Some(Num(v)) else { return None }
  Some({ count: v.to_int(), })
}

///|
fn demo_sections() -> Array[@sb.Section] {
  let m = @component.ModuleDef::new(
    name="demo",
    components=[
      @component.component(
        views={
          "main": @anode.View::new(
            "main",
            raw_view="<div class=\"counter\"><x text=\".count\"></x></div>",
          ),
        },
        name="Counter",
        init=CountState::{ count: 3, },
      ),
    ],
    examples=[{ component: "Counter", title: "", args: Map([]), view: None, }],
  )
  @sb.sections_of(@sb.stories_of_module(m, section="Demo"))
}

///|
fn mounted() -> (@app.App[@memdom.MemNode], @memdom.MemNode) raise {
  let sections = demo_sections()
  let doc = @memdom.document()
  let container = @vdom.DomNode::create_element(doc, "DIV", None, None)
  let app = @sbui.mount(
    sections,
    container,
    @vdom.RenderOpts::new(doc),
    panels=all(sections),
  )
  (app, container)
}

///|
test "every panel gets a tab" {
  let (_app, container) = mounted()
  let html = container.to_html()
  for
    cls in [
      "story-tab", "instance-tab", "trace-tab", "fuzz-tab", "spec-tab", "raw-tab",
    ] {
    assert_true(html.contains(cls))
  }
}

///|
test "each panel builds into its own field, lazily" {
  let (app, _container) = mounted()
  // nothing is built until a tab is opened
  for f in ["i0", "r0", "f0", "d0", "w0"] {
    assert_true(app.root_value().field(f) is Null)
  }
  // the explorer is an instance of the inspector's own components, which mount
  // registered in a scope of their own — an unregistered one renders as
  // nothing, so this is also what proves `PanelSet::components` was wired
  app.send_at_root("onStoryTab", args=[Num(0), Str("instance")]) |> ignore
  assert_true(app.root_value().field("i0") is Obj(_))
  // the recorder bar and the fuzz panel come up as their empty selves rather
  // than waiting for the host's first push
  app.send_at_root("onStoryTab", args=[Num(0), Str("trace")]) |> ignore
  assert_true(app.root_value().field("r0") is Obj(_))
  // …and the explorer is dropped on the way out: it is a whole component tree
  assert_true(app.root_value().field("i0") is Null)
  app.send_at_root("onStoryTab", args=[Num(0), Str("fuzz")]) |> ignore
  assert_true(app.root_value().field("f0") is Obj(_))
  // a recording survives you looking away from it
  assert_true(app.root_value().field("r0") is Obj(_))
  app.send_at_root("onStoryTab", args=[Num(0), Str("spec")]) |> ignore
  assert_true(app.root_value().field("d0") is Obj(_))
  app.send_at_root("onStoryTab", args=[Num(0), Str("raw")]) |> ignore
  assert_true(app.root_value().field("w0") is Obj(_))
}

///|
test "the fuzz knobs are the panel layer's fields, not the shell's" {
  let (app, _container) = mounted()
  assert_eq(app.root_value().field("fzSeed"), Str("1"))
  assert_eq(app.root_value().field("fzSteps"), Str("40"))
  assert_eq(app.root_value().field("fzSource"), Str("public"))
}
