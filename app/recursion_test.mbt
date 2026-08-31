// A component whose view renders its own value again. Nothing bounds it: the
// second pass reaches the same node with the same value and does it once more.
// The renderer leaves a marker at that site rather than following it down.
//
// The shape is not exotic. It is what `<div @each=".rows"><x render-it></x>`
// collapses to the moment the `@each` goes missing — which is why `@each` on an
// `<x>` op is now a parse-time rejection (anode/anode_xops_test.mbt) rather than
// a warning: the two together mean the mistake is caught when the view is
// parsed, and survivable if it ever reaches the renderer another way.

///|
priv struct SelfLoopState {
  label : String
}

///|
test "a component that renders itself renders a marker, not a stack overflow" {
  let scope = @component.ComponentStack::new()
  let looper = @component.component(
    views={
      "main": @anode.View::new(
        "main",
        raw_view="<div class=\"loop\"><span><x text=\".label\"></x></span><x render-it></x></div>",
      ),
    },
    name="SelfLoop",
    init=SelfLoopState::{ label: "once", },
  )
  scope.register_components([looper])
  scope.compile_all()
  guard scope.lookup_component("SelfLoop") is Some(c) else {
    fail("no SelfLoop")
  }
  let html = mount(scope.comps, c.make(Map([]))).to_html()
  // the body rendered exactly once, and the site that would have repeated it
  // left a marker instead of a second §Comp§ boundary
  assert_true(html.contains("once"))
  assert_true(html.contains("<!--RECURSION AVOIDED-->"))
  assert_true(count_of(html, "class=\"loop\"") == 1)
}

///|
fn count_of(haystack : String, needle : String) -> Int {
  let mut n = 0
  let mut rest = haystack
  while rest.find(needle) is Some(at) {
    n += 1
    rest = rest[at + needle.length():].to_owned()
  }
  n
}

///|
impl @component.Fields for SelfLoopState with fn encode(s) {
  { "label": Str(s.label) }
}

///|
impl @component.Fields for SelfLoopState with fn decode(f) {
  guard f.get("label") is Some(Str(v)) else { return None }
  Some({ label: v, })
}

///|
impl @component.Fields for SelfLoopState with fn schema() {
  @component.SchemaInfo::new(fingerprint="self_loop_state", fields=[
    @component.FieldInfo::new("label", TyText),
  ])
}
