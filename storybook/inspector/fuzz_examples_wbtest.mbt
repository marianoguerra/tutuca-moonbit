// The examples describe a real component, and this is what holds them to it.
//
// `fuzz_examples.mbt` builds its `@fuzz.Step`s by hand, because the projection
// under test is a pure function of one and the inspector must not depend on a
// mount. The risk that buys is a fixture that drifts: rows describing a run
// that the component beside them would never produce.
//
// So the component IS driven, here, once — through the same driver the
// storybook's Fuzz tab uses — and what comes back has to look like what the
// stories show. Whitebox because the fixture is package-private, which it
// should stay.

///|
priv struct DrawerState {
  held : Int
  owed : Int
}

///|
const DRAWER_SPEC : String =
  #|state Drawer {
  #|  held : Int
  #|  owed : Int
  #|
  #|  invariant covered
  #|    format 'more is owed than the drawer holds' { .owed <= .held }
  #|}

///|
impl @component.Fields for DrawerState with fn encode(s) {
  { "held": Num(s.held.to_double()), "owed": Num(s.owed.to_double()) }
}

///|
impl @component.Fields for DrawerState with fn decode(f) {
  guard f.get("held") is Some(Num(h)) else { return None }
  guard f.get("owed") is Some(Num(o)) else { return None }
  Some({ held: h.to_int(), owed: o.to_int(), })
}

///|
impl @component.Fields for DrawerState with fn schema() {
  @component.SchemaInfo::new(
    name="Drawer",
    fingerprint="fuzz-example-drawer",
    fields=[
      @component.FieldInfo::new("held", TyInt),
      @component.FieldInfo::new("owed", TyInt),
    ],
    // Declared, and nothing implements it — which is the whole fixture.
    invariants=["covered"],
    view_names=["main"],
  )
}

///|
fn drawer_comp() -> @component.Component {
  @component.component(
    name="Drawer",
    views={
      "main": @anode.View::new(
        "main",
        raw_view="<div><span class=\"held\" @text=\".held\"></span></div>",
      ),
    },
    init=DrawerState::{ held: 10, owed: 4, },
    spec=DRAWER_SPEC,
  )
}

///|
fn drawer_module() -> @component.ModuleDef {
  @component.ModuleDef::new(name="fuzz-drawer", components=[drawer_comp()], examples=[
    { component: "Drawer", title: "Open", args: Map([]), view: None, },
  ])
}

///|
/// The drawer's declared rule is enforced by nothing, and a run finds it.
///
/// The claim every FuzzRow and FuzzVerdict example rests on. If someone gives
/// `Drawer` a `compute` for `covered`, the runtime starts abandoning the
/// transitions instead and this fails — which is the moment the examples stop
/// describing the component and want rewriting.
test "the fixture really is a component whose invariant nothing enforces" {
  guard @fuzz.Plan::of_component(drawer_comp()) is Some(plan) else {
    fail("Drawer carries a spec block, so it has a plan")
  }
  // Both rules the block declares are ones `@core.Val` can answer.
  assert_eq(plan.unchecked(), [])
  let h = @harness.mount_example(drawer_module(), "Open")
  let run = plan.run(h, plan.script(seed=1, steps=20))
  guard run.outcome is Broke(rule~, sentence~, ..) else {
    fail("nothing implements `covered`, so a generated setter lands")
  }
  assert_eq(rule, "covered")
  // The same sentence the FuzzVerdict example shows.
  assert_eq(sentence, "more is owed than the drawer holds")
}

///|
/// The hand-built steps are shapes the driver actually produces.
///
/// Not the same dispatches — a generated script is drawn, and pinning one
/// would make this a test of the RNG. What is pinned is that every mutator
/// name the examples use is one the runtime installs for this schema, so a row
/// never shows a message that could not have been sent.
test "the examples name dispatches the runtime really installs" {
  let installed = @component.schema_mutators(drawer_comp().schema)
  for step in [quiet_step(), broken_step()] {
    guard step.dispatch is Receive(name, _) else {
      fail("the examples' steps are mutators, and a mutator is a Receive")
    }
    assert_true(installed.contains(name))
  }
  // `declined_step` is the same, and `unclaimed_step` deliberately is NOT:
  // it is the case where nothing answers the name.
  guard declined_step().dispatch is Receive(n, _) else {
    fail("a mutator is a Receive")
  }
  assert_true(installed.contains(n))
  guard unclaimed_step().dispatch is Receive(gone, _) else {
    fail("a mutator is a Receive")
  }
  assert_false(installed.contains(gone))
}
