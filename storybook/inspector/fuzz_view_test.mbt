// The fuzz viewer, mounted.
//
// What is worth testing here is the PROJECTION — a `@fuzz.Step` says one thing
// and the row has to say the same thing — and the one branch that decides
// anything: whether there is a plan to run at all.

///|
fn fv_mount(title : String) -> @harness.MemHarness raise {
  @harness.mount_example(@inspector.inspector_module(), title)
}

///|
/// A row reads the step it came from.
test "a row reads the step it came from" {
  let h = fv_mount("Fuzz Row · a rule nothing enforced")
  inspect(h.text(".row-verb"), content="internal")
  inspect(h.text(".row-name"), content="setOwed")
  inspect(h.text(".row-args"), content="99")
  inspect(h.text(".row-broke"), content="covered")
  inspect(h.text(".row-renders"), content="1 render")
  // Nothing refused it, which is the whole finding: the rule is written down
  // and there is nothing behind the name.
  inspect(h.find_all(".row-refused").length(), content="0")
}

///|
/// A refusal is shown as a refusal, not as a break.
///
/// The two look the same from the state's side — nothing moved — and they mean
/// opposite things: one is a rule working, the other is a rule that is not
/// there. The row has to keep them apart.
test "a declined step is not a broken one" {
  let h = fv_mount("Fuzz Row · the runtime declined it")
  inspect(h.text(".row-refused"), content="covered")
  inspect(h.find_all(".row-broke").length(), content="0")
  // And a dispatch that was declined rendered nothing.
  inspect(h.text(".row-renders"), content="0 render")
}

///|
/// A step that changed nothing is neither.
test "a quiet step is neither refused nor broken" {
  let h = fv_mount("Fuzz Row · a step that changed nothing")
  inspect(h.find_all(".row-refused").length(), content="0")
  inspect(h.find_all(".row-broke").length(), content="0")
  inspect(h.text(".row-renders"), content="0 render")
}

///|
/// The log is the steps, in order.
test "the log lists every step it was given" {
  let h = fv_mount("Fuzz Log")
  assert_eq(h.texts(".row-name"), ["setHeld", "setHeld", "setOwed"])
  // The hint is gone once there are rows: `@hide` takes it out of the tree
  // rather than styling it away, so a reader never sees "nothing drawn yet"
  // above three rows.
  inspect(h.find_all(".empty-hint").length(), content="0")
}

///|
/// A verdict says the rule's own sentence.
///
/// The words the author wrote for exactly this moment, rather than a rendering
/// of the expression — which is the half nobody can reconstruct afterwards.
test "the verdict carries the declaration's own words" {
  let h = fv_mount("Fuzz Verdict · a rule nothing enforced")
  inspect(h.text(".verdict-kind"), content="broke")
  inspect(h.text(".verdict-rule"), content="covered")
  inspect(
    h.text(".verdict-sentence"),
    content="more is owed than the drawer holds",
  )
}

///|
/// A green verdict that had rules it could not check says so.
///
/// Otherwise it reads as a stronger claim than it is: those rules were never
/// asked, and the run is quieter than it looks.
test "a held verdict admits what it did not check" {
  let h = fv_mount("Fuzz Verdict · held, with a rule that was not checked")
  inspect(h.text(".verdict-kind"), content="held")
  assert_true(h.text(".verdict-unchecked").contains("conserved"))
}

///|
/// A component with no block gets the reason, not buttons that cannot act.
test "nothing to generate says why" {
  let h = fv_mount("Fuzz Controls · nothing to generate")
  assert_true(h.text(".no-plan").contains("tutuca/spec"))
  inspect(h.find_all(".ctl-burst").length(), content="0")
  inspect(h.find_all(".ctl-seed").length(), content="0")
}

///|
/// A plan with an empty SOURCE is not a component with no plan, and the panel
/// says which: the run buttons go, the switcher stays — because switching is
/// the thing to do about it.
test "a source that draws nothing keeps the switcher" {
  let h = fv_mount("Fuzz Controls · nothing to draw")
  assert_true(h.text(".no-draw").contains("no messages"))
  inspect(h.find_all(".ctl-play").length(), content="0")
  inspect(h.find_all(".ctl-burst").length(), content="0")
  // …and everything that could change the answer is still there
  inspect(h.find_all(".src-internal").length(), content="1")
  inspect(h.find_all(".ctl-seed").length(), content="1")
  inspect(h.find_all(".no-plan").length(), content="0")
}

///|
/// The knobs are there when there is something to run.
test "the controls show the run's whole address" {
  let h = fv_mount("Fuzz Controls")
  inspect(h.value_of(".ctl-seed"), content="1")
  inspect(h.value_of(".ctl-steps"), content="12")
  inspect(h.find_all(".no-plan").length(), content="0")
  // The active source is the one marked, and only that one.
  assert_true(
    h.attr(".src-internal", "class").unwrap_or("").contains("btn-primary"),
  )
  assert_true(
    h.attr(".src-public", "class").unwrap_or("").contains("btn-ghost"),
  )
}

///|
/// The panel is the three of them, over one run.
test "the panel puts the controls, the verdict and the log together" {
  let h = fv_mount("Fuzz Panel")
  inspect(h.find_all(".fuzz-controls").length(), content="1")
  inspect(h.find_all(".fuzz-verdict").length(), content="1")
  inspect(h.find_all(".fuzz-log").length(), content="1")
  inspect(h.text(".panel-pos"), content="3 / 12")
}

///|
/// A refusal that names no rule still says something.
///
/// A dispatch nothing claims is refused with `NoHandler` and an empty `rule`.
/// A badge that showed only the rule would be an empty badge — which reads as
/// a rendering bug rather than as the finding it is.
test "a refusal with no rule falls back to its code" {
  let h = fv_mount("Fuzz Row · nothing answered it")
  inspect(h.text(".row-refused"), content="unhandled")
  inspect(h.find_all(".row-broke").length(), content="0")
}
