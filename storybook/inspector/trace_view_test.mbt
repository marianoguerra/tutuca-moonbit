// The trace viewer, mounted.
//
// What is worth testing here is the PROJECTION — the trace says one thing and
// the row has to say the same thing — plus the two filters, which are the only
// place the viewer decides anything at all.

///|
fn tv_insp() -> @inspector.Inspector {
  @inspector.Inspector::new()
}

///|
fn tv_mount(title : String) -> @harness.MemHarness raise {
  @harness.mount_example(@inspector.inspector_module(), title)
}

///|
/// One row says what the event said, in the words a reader scans.
test "a row reads the event it came from" {
  let h = tv_mount("Trace Row · an intent")
  inspect(h.text(".row-verb"), content="intent")
  inspect(h.text(".row-name"), content="save")
  inspect(h.text(".row-place"), content="rows[0]")
  // Derived: a rerun raises it again, so it is not something a rerun feeds.
  inspect(h.find_all(".row-input").length(), content="0")
  inspect(h.text(".row-walk"), content="walk 1")
}

///|
/// The input/derived line, which is the whole difference between what happened
/// TO the app and what the app did about it.
test "an input says so and a derived event does not" {
  let fed = tv_mount("Trace Row · a message")
  inspect(fed.find_all(".row-input").length(), content="1")
  let derived = tv_mount("Trace Row · the host answered")
  inspect(derived.text(".row-verb"), content="answer")
  // An answer IS an input — the host decided it and nothing in the tree can
  // work it out again — which is the one case where the two badges disagree
  // with the intuition that "derived" means "not from outside".
  inspect(derived.find_all(".row-input").length(), content="1")
}

///|
/// A refusal's name is what was ASKED FOR and not the code: the code is the
/// badge, and a reader scanning a column of names wants the same kind of word
/// in all of them.
test "a refusal names what was asked, and carries its sentence" {
  let h = tv_mount("Trace Row · refused")
  inspect(h.text(".row-verb"), content="refused")
  inspect(h.text(".row-name"), content="rename")
  h.click(".row-head")
  inspect(
    h.text(".row-args"),
    content="args a row with no label cannot be renamed",
  )
}

///|
/// Closed by default, because a recording is read by scanning it and forty
/// expanded rows is not a thing anybody scans.
test "a row opens to show what it carried" {
  let h = tv_mount("Trace Row · a message")
  inspect(h.find_all(".row-detail").length(), content="0")
  h.click(".row-head")
  inspect(h.find_all(".row-detail").length(), content="1")
  h.click(".row-head")
  inspect(h.find_all(".row-detail").length(), content="0")
}

///|
test "the log shows every event, and says so when there are none" {
  let h = tv_mount("Trace Log")
  inspect(h.find_all(".trace-row").length(), content="10")
  let empty = tv_mount("Trace Log · nothing recorded")
  inspect(empty.find_all(".trace-row").length(), content="0")
  inspect(empty.text(".empty-hint"), content="Nothing was recorded.")
}

///|
/// The view a person takes when they are about to hand the file to somebody
/// else: what a rerun would feed, and nothing the app did for itself.
test "the log can show only what a rerun feeds" {
  let h = tv_mount("Trace Log · only what a rerun feeds")
  inspect(h.find_all(".trace-row").length(), content="5")
  assert_true(h.texts(".row-input").length() == 5)
}

///|
/// A turn is what one drain consumed, so "this turn" is the unit a reader
/// actually asks about — one click and everything it caused.
test "the log can show one turn" {
  let h = tv_mount("Trace Log · one turn")
  inspect(h.find_all(".trace-row").length(), content="5")
  assert_eq(h.texts(".row-name"), ["bump", "save", "save", "ok", "saved"])
}

///|
/// What a recording says about itself, before any of its events.
test "the header counts the recording" {
  let h = tv_mount("Trace Header")
  inspect(h.text(".header-component"), content="Board")
  inspect(h.text(".header-events"), content="10 events")
  inspect(h.text(".header-inputs"), content="5 fed on a rerun")
  inspect(h.text(".header-turns"), content="4 turns")
  inspect(h.find_all(".header-relocated").length(), content="0")
  inspect(h.find_all(".header-compacted").length(), content="0")
}

///|
/// A trace that was cut says where from, and a compacted one says what it can
/// no longer do. Both are warnings a reader needs BEFORE they trust it.
test "the header owns up to a cut and to a compaction" {
  let h = tv_mount("Trace Header · relocated and compacted")
  inspect(h.text(".header-relocated"), content="relocated from rows[0]")
  inspect(h.text(".header-compacted"), content="compacted")
}

///|
/// The recording's own places, not every component that happens to exist: a
/// picker offering somewhere nothing ever happened is a picker offering an
/// empty trace.
test "the picker offers the places the recording touched" {
  let h = tv_mount("Relocation Picker")
  assert_eq(h.texts(".place-label"), ["(the whole thing)", "rows[0]", "rows[1]"])
  assert_eq(h.texts(".place-component"), ["Board", "Row", "Row"])
  assert_eq(h.texts(".place-count"), ["3", "4", "3"])
}

///|
test "the picker marks the one that is chosen" {
  let h = tv_mount("Relocation Picker · one chosen")
  let classes = h.find_all(".trace-place").length()
  inspect(classes, content="3")
  inspect(
    h
    .attr(".trace-place", "class", nth=1)
    .unwrap_or("")
    .contains("ring-primary/40"),
    content="true",
  )
}

///|
/// Off is the default and the whole point: nothing is recorded until somebody
/// asks.
test "the recorder starts idle" {
  let h = tv_mount("Recorder · idle")
  inspect(h.find_all(".rec-start").length(), content="1")
  inspect(h.find_all(".rec-stop").length(), content="0")
  inspect(h.find_all(".rec-clear").length(), content="0")
  inspect(h.text(".rec-scope"), content="the whole storybook")
}

///|
test "the recorder shows what it has while it runs" {
  let h = tv_mount("Recorder · recording")
  inspect(h.find_all(".rec-stop").length(), content="1")
  inspect(h.find_all(".rec-start").length(), content="0")
  inspect(h.text(".rec-count"), content="10 events · 4 turns")
  inspect(h.text(".rec-scope"), content="this example")
}

///|
/// What a recording covers is asked BEFORE it starts, because it is not
/// something a recording can be told afterwards: a narrower scope is what gets
/// mounted with a recorder on it, not a filter applied later.
test "the scope is picked before recording, not after" {
  let h = tv_mount("Recorder · choosing a scope")
  inspect(h.find_all(".recorder-picker").length(), content="1")
  inspect(
    h
    .attr(".pick-section", "class", nth=0)
    .unwrap_or("")
    .contains("btn-primary"),
    content="true",
  )
  inspect(
    h.attr(".pick-all", "class", nth=0).unwrap_or("").contains("btn-outline"),
    content="true",
  )
  h.click(".pick-example")
  inspect(
    h
    .attr(".pick-example", "class", nth=0)
    .unwrap_or("")
    .contains("btn-primary"),
    content="true",
  )
}

///|
/// Recording and reading are two tabs because they are two activities: while a
/// session is being recorded nobody is reading it.
test "the panel hides the trace until there is one" {
  let h = tv_mount("Trace Panel · nothing yet")
  inspect(h.find_all(".panel-empty").length(), content="1")
  inspect(h.find_all(".panel-trace").length(), content="0")
  inspect(h.find_all(".tab-trace").length(), content="0")
}

///|
test "the panel shows the recording once there is one" {
  let h = tv_mount("Trace Panel · reading a recording")
  inspect(h.find_all(".panel-trace").length(), content="1")
  inspect(h.find_all(".trace-row").length(), content="10")
  inspect(h.text(".panel-pos"), content="6 / 10")
  // The picker is right there beside the log, because cutting the recording
  // down is the thing a reader does next.
  inspect(h.find_all(".trace-place").length(), content="3")
}

///|
/// Selection mode is a mode, and the button says so — clicking the page is
/// about to mean something different from clicking the page.
test "the panel says when it is waiting for a click on the page" {
  let plain = tv_mount("Trace Panel · reading a recording")
  inspect(plain.text(".tab-select"), content="Pick a component")
  let picking = tv_mount("Trace Panel · picking a component")
  inspect(picking.text(".tab-select"), content="Click an element…")
}

///|
/// The projection is the thing that has to be right, so it is worth asserting
/// against the trace rather than against a screenshot of it.
test "the log's rows line up with the trace's events" {
  let insp = tv_insp()
  let t = @inspector.sample_trace()
  let log = insp.trace_log(t)
  let rows = log.field("rows").list()
  assert_eq(rows.length(), t.events.length())
  for i, e in t.events {
    assert_eq(rows[i].field("seq").int(), e.seq)
    assert_eq(rows[i].field("input").bool(), e.input)
    assert_eq(rows[i].field("walk").int(), e.walk)
  }
}

///|
/// The causal depth, which is what makes a cascade of sends from one click read
/// as one thing instead of as several.
test "a row knows how deep in the cascade it sits" {
  let insp = tv_insp()
  let rows = insp
    .trace_log(@inspector.sample_trace())
    .field("rows")
    .list()
    .map(r => r.field("depth").int())
  // `init` and `bump` were caused by nobody; the intent by `bump`; the offer,
  // the answer and the reply by the intent.
  assert_eq(rows, [0, 0, 1, 2, 2, 2, 0, 1, 0, 1])
}
