// `tutuca trace`: what the command decides, and what it does to a file.
//
// Split the way the command is: the PLAN half is what `plan(argv)` decided,
// and the APPLY half is text in and text out. Neither reads a file, which is
// what makes both of them testable here.

///|
fn sample_trace_text() -> String {
  (
    #|{"origin":{"component":"Board","fingerprint":"abc"},"relocatedFrom":[],"tutucaTrace":1}
    #|{"root":{"$component":"Board","rows":[{"$component":"Row","n":0},{"$component":"Row","n":0}]}}
    #|{"seq":1,"turn":1,"at":[],"send":"init","args":[]}
    #|{"seq":2,"turn":2,"at":[{"f":"rows","k":0}],"send":"bump","args":[]}
    #|{"seq":3,"turn":2,"parent":2,"derived":true,"at":[{"f":"rows","k":1}],"send":"reset","args":[]}
    #|{"seq":4,"turn":3,"at":[{"f":"rows","k":1}],"send":"bump","args":[]}
    #|
  )
}

///|
fn tplan(argv : Array[String]) -> @cli.TracePlan? {
  match @cli.plan(argv) {
    Trace(_, plan~) => Some(plan)
    _ => None
  }
}

///|
fn temit(argv : Array[String]) -> @cli.Emit {
  match @cli.plan(argv) {
    Done(e) => e
    _ => { out: "", err: "(not done)", exit_code: 0, }
  }
}

///|
fn applied(plan : @cli.TracePlan) -> @cli.TraceResult {
  match @cli.trace_apply(plan, sample_trace_text()) {
    Ok(r) => r
    Err(e) => { file: None, report: "ERR " + e.message, diagnostics: [], }
  }
}

///|
/// No flags is `info`, because a file somebody was handed is a file they want
/// to know about before they change it.
test "trace with no flags plans a report" {
  assert_eq(
    tplan(["trace", "app.trace.jsonl"]),
    Some({ path: "app.trace.jsonl", op: Info, out: None, }),
  )
}

///|
test "the flags say which operation" {
  assert_eq(
    tplan(["trace", "a.jsonl", "--trim", "40"]).map(p => p.op),
    Some(Trim(at=40)),
  )
  assert_eq(
    tplan(["trace", "a.jsonl", "--at", ".rows[1]"]).map(p => p.op),
    Some(Relocate(place=".rows[1]", compact=false)),
  )
  assert_eq(
    tplan(["trace", "a.jsonl", "--at", ".rows[1]", "--compact"]).map(p => p.op),
    Some(Relocate(place=".rows[1]", compact=true)),
  )
  assert_eq(
    tplan(["trace", "a.jsonl", "-o", "out.jsonl"]).map(p => p.out),
    Some(Some("out.jsonl")),
  )
}

///|
/// Two operations on one file is not one operation, and the order changes the
/// answer — so it is refused rather than resolved by a rule nobody wrote down.
test "trimming and relocating at once is refused" {
  let e = temit(["trace", "a.jsonl", "--trim", "3", "--at", ".rows[0]"])
  assert_eq(e.exit_code, 1)
  assert_true(e.err.contains("two operations"))
}

///|
test "trace says what it needs" {
  let missing = temit(["trace"])
  assert_eq(missing.exit_code, 1)
  assert_true(missing.err.contains("requires a .trace.jsonl file"))
  let bad = temit(["trace", "a.jsonl", "--trim", "soon"])
  assert_eq(bad.exit_code, 1)
  assert_true(bad.err.contains("takes a number of events"))
}

///|
/// What `info` is for: a summary, and the addresses there is anything to cut
/// to — which is why it is worth running before `--at` rather than guessing.
test "info summarizes the file and lists its places" {
  inspect(
    applied({ path: "a.jsonl", op: Info, out: None, }).report,
    content=(
      #|component: Board
      #|shape: abc
      #|events: 4
      #|inputs: 3
      #|turns: 3
      #|places:
      #|  (root)  1 event
      #|  rows[0]  1 event
      #|  rows[1]  2 events
      #|
    ),
  )
}

///|
/// Slicing lines never reads an event, which is the point: a trace holding a
/// kind this build has never heard of shortens just the same.
test "trim keeps the headers and the first n events" {
  let r = applied({ path: "a.jsonl", op: Trim(at=2), out: None, })
  assert_eq(r.report, "kept 2 of 4 events\n")
  inspect(
    r.file.unwrap_or(""),
    content=(
      #|{"origin":{"component":"Board","fingerprint":"abc"},"relocatedFrom":[],"tutucaTrace":1}
      #|{"root":{"$component":"Board","rows":[{"$component":"Row","n":0},{"$component":"Row","n":0}]}}
      #|{"seq":1,"turn":1,"at":[],"send":"init","args":[]}
      #|{"seq":2,"turn":2,"at":[{"f":"rows","k":0}],"send":"bump","args":[]}
      #|
    ),
  )
}

///|
test "trim past the end keeps everything, and zero keeps none" {
  assert_eq(
    applied({ path: "a.jsonl", op: Trim(at=99), out: None, }).report,
    "kept 4 of 4 events\n",
  )
  assert_eq(
    applied({ path: "a.jsonl", op: Trim(at=0), out: None, }).report,
    "kept 0 of 4 events\n",
  )
}

///|
/// A trace this build cannot fully read still trims, because trimming does not
/// read it. That is the whole reason the two halves are separate.
test "trim works on an event kind this build does not know" {
  let future = sample_trace_text() +
    (
      #|{"seq":5,"turn":9,"at":[],"teleported":"somewhere"}
      #|
    )
  let plan : @cli.TracePlan = { path: "a.jsonl", op: Trim(at=5), out: None, }
  match @cli.trace_apply(plan, future) {
    Ok(r) => assert_eq(r.report, "kept 5 of 5 events\n")
    Err(e) => fail("should have trimmed: \{e.message}")
  }
  // And reading it properly does fail, on the line it failed on.
  match @cli.trace_apply({ ..plan, op: Info, }, future) {
    Ok(_) => fail("should not have parsed")
    // The line in the FILE, and the file's own name in front of it: a trace is
    // routinely a hundred thousand lines, so a message with no position in it
    // is one nobody can act on.
    Err(e) =>
      inspect(
        e.message,
        content="a.jsonl: line 7: no verb here — found seq, turn, at, teleported",
      )
  }
}

///|
/// The headline operation: a recording of a whole app becomes a recording of
/// one row, with every address rewritten to suit.
test "relocate cuts the file down to one subtree" {
  let r = applied({
    path: "a.jsonl",
    op: Relocate(place=".rows[1]", compact=false),
    out: None,
  })
  inspect(
    r.file.unwrap_or(""),
    content=(
      #|{"origin":{"component":"Board","fingerprint":"abc"},"relocatedFrom":[[{"f":"rows","k":1}]],"tutucaTrace":1}
      #|{"root":{"$component":"Row","n":0}}
      #|{"seq":1,"turn":2,"at":[],"send":"reset","args":[]}
      #|{"seq":2,"turn":3,"at":[],"send":"bump","args":[]}
      #|
    ),
  )
  // `reset` was the parent's doing and is now an input — after the cut there
  // is no parent left to send it. Nothing says `derived` any more.
  assert_false(r.file.unwrap_or("").contains("derived"))
  assert_eq(r.diagnostics, [])
}

///|
test "relocate reports what it could not carry across" {
  let r = applied({
    path: "a.jsonl",
    op: Relocate(place=".rows", compact=false),
    out: None,
  })
  inspect(
    r.diagnostics.join(" / "),
    content="`rows` is not a component, so the trace it cuts cannot be mounted — did you mean one step deeper, or one fewer?",
  )
}

///|
test "an address that does not read as one says so" {
  match
    @cli.trace_apply(
      {
        path: "a.jsonl",
        op: Relocate(place=".rows[", compact=false),
        out: None,
      },
      sample_trace_text(),
    ) {
    Ok(_) => fail("should have refused")
    Err(e) => assert_true(e.message.contains("unclosed `[`"))
  }
}

///|
/// Smaller, and the trade is explicit rather than silent.
test "compact drops the derived events on the way out" {
  let r = applied({
    path: "a.jsonl",
    op: Relocate(place=".rows[0]", compact=true),
    out: None,
  })
  assert_true(r.file.unwrap_or("").contains("\"compacted\":true"))
  assert_true(r.report.contains("compacted: yes"))
}

///|
test "a file that is not a trace says which line and why" {
  match
    @cli.trace_apply(
      { path: "a.jsonl", op: Info, out: None, },
      "{\"nope\":1}\n{\"root\":{}}\n",
    ) {
    Ok(_) => fail("should have refused")
    Err(e) =>
      assert_true(e.message.contains("line 1: the first line must name"))
  }
}
