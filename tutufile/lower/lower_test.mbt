// The lowering, end to end: a `.tutu` file in, the blocks the front end reads
// out — and then those blocks parsed by the readers they were printed for,
// which is the only check that means anything here.

///|
let guarded : String =
  #|spec:
  #|  /// A counter with a rule, and scenes that watch the rule hold.
  #|  Guarded ~root:
  #|    /// How far it has counted.
  #|    field n :: Int
  #|
  #|    /// True while there is room left.
  #|    pred room:
  #|      ~format: @str{the counter is full at @(it.n)}
  #|      it.n < 3
  #|
  #|logic:
  #|  Guarded:
  #|    /// Count one more, while there is room.
  #|    receive bump:
  #|      ~requires: room
  #|      it.n += 1
  #|
  #|view:
  #|  Guarded:
  #|    @div{
  #|      @button(~on_click: bump){+}
  #|      @output{@(it.n)}
  #|    }
  #|
  #|fixtures:
  #|  "nearly full":
  #|    ~doc: "One press from the rule declining."
  #|    it.n = 2
  #|
  #|tests:
  #|  "the guard stops it at three":
  #|    click("button")
  #|    click("button")
  #|    click("button")
  #|    expect text("output") == "3"
  #|    click("button")
  #|    expect log contains "precondition `room` does not hold"
  #|

///|
fn lower_text(src : String) -> Lowered {
  let sources = @report.Sources::new()
  let id = sources.add("card.tutu", src)
  lower(src, id)
}

///|
test "a card lowers into the four blocks and its templates" {
  let out = lower_text(guarded)
  assert_eq(out.reports.length(), 0)
  assert_true(out.text.contains("state Guarded {"))
  assert_true(out.text.contains("pred room"))
  assert_true(out.text.contains("format $'the counter is full at {.n}'"))
  assert_true(out.text.contains("receive bump requires room {"))
  assert_true(out.text.contains(".n += 1"))
  assert_true(out.text.contains("<template id=\"Guarded\">"))
  assert_true(out.text.contains("@on.click=\"bump\""))
}

///|
test "what it prints is what the front end reads" {
  // The only check worth having: the blocks are parsed by the readers they
  // were printed for, and the state they describe is the state the `.tutu`
  // file declared.
  let out = lower_text(guarded)
  let file = @viewfile.split_file(out.text, name="Guarded")
  assert_eq(file.state.length(), 1)
  let state = file.state[0]
  assert_eq(state.component, "Guarded")
  assert_eq(state.fields.length(), 1)
  assert_eq(state.fields[0].name, "n")
  @debug.assert_eq(state.fields[0].ty, TyInt(width=32, signed=true))
  assert_eq(state.rules.length(), 1)
  assert_eq(state.rules[0].name, "room")
  // the script block reached the file whole, under the component it answers for
  assert_true(file.script_for("Guarded") is Some(_))
  // one fixture, and one scene, both read from what the JSON printer wrote
  assert_eq(file.init.length(), 1)
  assert_eq(file.init[0].1.name, "nearly full")
  assert_eq(file.tests.length(), 1)
  assert_eq(file.tests[0].name, "the guard stops it at three")
  assert_eq(file.tests[0].steps.length(), 6)
  // and one view, with the button the at-notation wrote
  assert_eq(file.components.length(), 1)
  assert_true(file.components[0].views[0].source.contains("@on.click=\"bump\""))
}
