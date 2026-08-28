// The Fuzz pane, as stories.
//
// The steps are built here rather than driven out of a live component, and
// that is the one thing about this file worth arguing. What these stories show
// is the PROJECTION — a `@fuzz.Step` says one thing and the row has to say the
// same thing — and a projection is a pure function of its input. Driving a
// real run to obtain that input would make the inspector depend on a mount,
// which it must not: `testing/harness` is a test-only import here, and a
// shipping story that needed one would make it a runtime one for every
// consumer of the inspector.
//
// Where a real run IS driven is `testing/fuzz`'s own suite, which is where the
// claim belongs: that the driver produces these values. This file's claim is
// the other half — that the pane says what they mean.
//
// The run these describe is the failure the pane exists to show: a component
// whose invariant is DECLARED and never implemented, so a generated setter
// writes a state the rule forbids and nothing stops it.
//
// That component lives in `fuzz_examples_wbtest.mbt`, beside the tests that
// drive it — because driving it is the only thing it is for. Those tests are
// what stop these steps from drifting into describing a run the component
// could not produce.

///|
/// A step that did nothing: the same value written twice.
fn quiet_step() -> @fuzz.Step {
  {
    dispatch: Receive("setHeld", [Num(10)]),
    refused: [],
    broke: [],
    disagreed: [],
    after: { "held": Num(10), "owed": Num(4) },
    renders: 0,
  }
}

///|
/// A step the runtime declined. Not a failure — the rule doing its job, and
/// the only place a decline is visible at all.
fn declined_step() -> @fuzz.Step {
  {
    dispatch: Receive("setHeld", [Num(1)]),
    refused: [
      {
        code: Invariant,
        rule: "covered",
        asked: "setHeld",
        sentence: "more is owed than the drawer holds",
        path: @tutuca.Path::new(),
        // The state the runtime turned down — the successor, which was
        // abandoned and which nothing else ever sees.
        state: Map({ "held": Num(1), "owed": Num(4) }),
      },
    ],
    broke: [],
    disagreed: [],
    after: { "held": Num(10), "owed": Num(4) },
    renders: 0,
  }
}

///|
/// A step that landed a state the block forbids, with nothing to stop it.
fn broken_step() -> @fuzz.Step {
  {
    dispatch: Receive("setOwed", [Num(99)]),
    refused: [],
    broke: ["covered"],
    disagreed: [],
    after: { "held": Num(10), "owed": Num(99) },
    renders: 1,
  }
}

///|
/// A step nothing claimed.
///
/// A refusal with no rule on it — the runtime declining a name no handler and
/// no mutator answers. It exists here because it is the case that renders an
/// EMPTY badge if a row shows `rule` and nothing else, which reads as a
/// rendering bug rather than as a finding.
fn unclaimed_step() -> @fuzz.Step {
  {
    dispatch: Receive("nope", []),
    refused: [
      {
        code: NoHandler,
        asked: "nope",
        rule: "",
        sentence: "nothing answers `nope`",
        path: @tutuca.Path::new(),
        state: Null,
      },
    ],
    broke: [],
    disagreed: [],
    after: { "held": Num(10), "owed": Num(4) },
    renders: 0,
  }
}

///|
/// The run those came from, in order.
fn drawer_steps() -> Array[@fuzz.Step] {
  [quiet_step(), declined_step(), broken_step()]
}

///|
/// The Fuzz pane's stories.
pub fn Inspector::fuzz_examples(
  self : Inspector,
) -> Array[@component.ExampleDef] {
  let steps = drawer_steps()
  let outcome : @fuzz.Outcome = Broke(
    rule="covered",
    sentence="more is owed than the drawer holds",
    at=2,
  )
  [
    {
      component: "FuzzRow",
      title: "Fuzz Row · a step that changed nothing",
      args: self.fuzz_row(quiet_step(), at=0).snapshot(),
      view: None,
    },
    {
      component: "FuzzRow",
      title: "Fuzz Row · the runtime declined it",
      args: self.fuzz_row(declined_step(), at=1).snapshot(),
      view: None,
    },
    {
      component: "FuzzRow",
      title: "Fuzz Row · a rule nothing enforced",
      args: self.fuzz_row(broken_step(), at=2, current=true).snapshot(),
      view: None,
    },
    {
      component: "FuzzRow",
      title: "Fuzz Row · nothing answered it",
      args: self.fuzz_row(unclaimed_step(), at=4).snapshot(),
      view: None,
    },
    {
      component: "FuzzLog",
      title: "Fuzz Log",
      args: self.fuzz_log(steps, at=2, planned=12).snapshot(),
      view: None,
    },
    {
      component: "FuzzControls",
      title: "Fuzz Controls",
      args: self
      .fuzz_controls(seed="1", steps="12", source="mutators")
      .snapshot(),
      view: None,
    },
    {
      component: "FuzzControls",
      title: "Fuzz Controls · nothing to generate",
      args: self
      .fuzz_controls(
        seed="1",
        steps="12",
        source="mutators",
        can_run=false,
        no_plan_hint="This story's component declares no <script type=\"tutuca/spec\"> block, so there is nothing to derive generators from.",
      )
      .snapshot(),
      view: None,
    },
    {
      component: "FuzzVerdict",
      title: "Fuzz Verdict · a rule nothing enforced",
      args: self.fuzz_verdict(outcome~).snapshot(),
      view: None,
    },
    {
      component: "FuzzVerdict",
      title: "Fuzz Verdict · held, with a rule that was not checked",
      args: self
      .fuzz_verdict(outcome=Held, unchecked=[
        ("conserved", "the slot vocabulary has no arithmetic"),
      ])
      .snapshot(),
      view: None,
    },
    {
      component: "FuzzPanel",
      title: "Fuzz Panel",
      args: self
      .fuzz_panel(
        seed="1",
        steps="12",
        source="mutators",
        run_steps=steps,
        at=2,
        planned=12,
        outcome~,
      )
      .snapshot(),
      view: None,
    },
  ]
}
