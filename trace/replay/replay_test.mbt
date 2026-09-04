// The proof. A recording that cannot be run back is a log; these are the tests
// that say it is a recording.

///|
/// A component's shape, as the runtime computes it.
fn fingerprint_of(v : @tutuca.Value) -> String {
  match v.schema() {
    Some(sc) => sc.shape_fingerprint()
    None => ""
  }
}

///|
/// A host that answers `save`, keeping what it was asked.
priv struct Host {
  asked : Array[String]
  answers : Array[@tutuca.IntentAnswer]
}

///|
impl @transactor.Intents for Host with fn intents_for(self, _leaf, name) {
  if name != "save" {
    return []
  }
  [
    IntentFn((call, answer) => {
      self.asked.push(call.args.map(a => a.str(default="")).join(","))
      let i = self.asked.length() - 1
      answer(
        if i < self.answers.length() {
          self.answers[i]
        } else {
          self.answers[self.answers.length() - 1]
        },
      )
    }),
  ]
}

///|
/// Mount the board, record everything, drive it, and hand back both halves:
/// what the app ended up as, and what the recording says happened.
fn record(
  drive : (@harness.MemHarness) -> Unit raise,
  host? : Host,
) -> (@trace.Trace, Json, String) raise {
  let scope = board_scope()
  let root = board_value(scope)
  let (doc, container) = @harness.new_mount()
  let app = @app.App::new(
    scope,
    root,
    container,
    @vdom.RenderOpts::new(doc),
    intents?=match host {
      Some(h) => Some(h as &@transactor.Intents)
      None => None
    },
  )
  app.start()
  // The fingerprint is `shape_fingerprint()` and not the schema's declared
  // `fingerprint`: the first is computed from the fields and moves when they
  // do, which is exactly the change a rerun has to refuse. Taken from the live
  // root, the way any host would take it.
  let rec = @trace.TraceRecorder::new(
    root=app.root_value().to_component_json(),
    origin={
      module_: "board",
      component: "Board",
      example: "",
      view: "",
      fingerprint: fingerprint_of(app.root_value()),
    },
  )
  app.transactor.set_recorder(rec)
  let h = @harness.Harness::over(app, container)
  drive(h)
  (rec.take(), app.root_value().to_component_json(), h.clean_html())
}

///|
/// The headline claim: the same events reach the same state.
///
/// Both halves are compared, and both are load-bearing. The STATE says the app
/// computed the same thing; the HTML says it rendered the same thing, which is
/// what a person would have looked at.
test "a recording replays to the state it recorded" {
  let host = Host::{ asked: [], answers: [Ok(Str("stored"))], }
  let (t, want_state, want_html) = record(
    h => {
      h.click(".row", nth=0)
      h.click(".row", nth=1)
      h.send_at_root("touch")
      h.click(".row", nth=0)
    },
    host~,
  )
  let p = @replay.mount(t, board_scope())
  p.run()
  assert_eq(p.snapshot(), want_state)
  assert_eq(p.html(), want_html)
  p.destroy()
}

///|
/// The host is replaced by what it said last time. The rerun installs no live
/// host at all, so if the answers did not come from the recording the rows
/// would never hear `saved` and would never gain their `*`.
test "the recorded host answers in the rerun" {
  let host = Host::{ asked: [], answers: [Ok(Str("stored"))], }
  let (t, want, _) = record(h => h.click(".row", nth=0), host~)
  assert_eq(host.asked, ["milk"])
  // Mounted against a scope with NO host registered.
  let p = @replay.mount(t, board_scope())
  p.run()
  assert_eq(p.snapshot(), want)
  inspect(
    p.snapshot().stringify(),
    content=(
      #|{"$component":"Board","title":"shopping","rows":[{"$component":"Row","label":"milk*","n":1},{"$component":"Row","label":"eggs","n":0}]}
    ),
  )
  p.destroy()
}

///|
/// Per-OCCURRENCE and not per-name. A host that failed the first time and
/// succeeded the second replays as that, rather than as two of whichever came
/// first — which is exactly the sequence a bug worth recording tends to be
/// about.
test "a host that answered differently the second time replays that way" {
  let host = Host::{
    asked: [],
    answers: [Failed(Str("offline")), Ok(Str("stored"))],
  }
  let (t, want, _) = record(
    h => {
      h.click(".row", nth=0)
      h.click(".row", nth=0)
    },
    host~,
  )
  // The first click failed, so no `saved`; the second succeeded, so one `*`.
  inspect(
    want.stringify(),
    content=(
      #|{"$component":"Board","title":"shopping","rows":[{"$component":"Row","label":"milk*","n":2},{"$component":"Row","label":"eggs","n":0}]}
    ),
  )
  let p = @replay.mount(t, board_scope())
  p.run()
  assert_eq(p.snapshot(), want)
  p.destroy()
}

///|
/// A prefix of a recording is a recording, and running one is running the whole
/// thing partway.
test "replaying a prefix is stopping partway" {
  let host = Host::{ asked: [], answers: [Ok(Null)], }
  let (t, _, _) = record(
    h => {
      h.click(".row", nth=0)
      h.click(".row", nth=1)
      h.click(".row", nth=0)
    },
    host~,
  )
  let n = t.events.length()
  let whole = @replay.mount(t, board_scope())
  whole.run_to(n / 2)
  let cut = @replay.mount(t.prefix(n / 2), board_scope())
  cut.run()
  assert_eq(cut.snapshot(), whole.snapshot())
  whole.destroy()
  cut.destroy()
}

///|
/// The point of a rebase: a long recording becomes a short one that starts at
/// the interesting moment, and reaches the same end.
test "a rebased recording reaches the same state" {
  let host = Host::{ asked: [], answers: [Ok(Null)], }
  let (t, want, _) = record(
    h => {
      h.click(".row", nth=0)
      h.send_at_root("touch")
      h.click(".row", nth=1)
      h.click(".row", nth=0)
    },
    host~,
  )
  for cut in [0, 2, 5, t.events.length()] {
    let part = @replay.mount(t, board_scope())
    part.run_to(cut)
    let rebased = t.rebase(at=cut, root=part.snapshot())
    part.destroy()
    let p = @replay.mount(rebased, board_scope())
    p.run()
    assert_eq(p.snapshot(), want)
    p.destroy()
  }
}

///|
/// The finding a recording kept as a regression test exists to produce.
test "a rerun against changed behaviour reports where they parted" {
  let host = Host::{ asked: [], answers: [Ok(Null)], }
  let (t, _, _) = record(h => h.send_at_root("touch"), host~)
  // The same components, except the board now pokes row 1 instead of row 0.
  let moved = @component.ModuleDef::new(name="board", components=[
    @component.component(
      name="Board",
      views=board_views(),
      initial=BoardState::{ title: "", rows: [], },
      update=(s, msg, ctx) => {
        match msg {
          Receive("touch", _) => {
            ctx.at().index("rows", 1).send("reset", [])
            Next({ ..s, title: s.title + ".", })
          }
          _ => Unhandled
        }
      },
    ),
    row_comp(),
  ])
  let p = @replay.mount(t, moved.build_scope())
  inspect(
    try {
      p.run()
      "no divergence"
    } catch {
      e => e.message()
    },
    content="at event 1 the recording says `reset at rows[0]` and the app did `reset at rows[1]`",
  )
  p.destroy()
}

///|
/// One cause, one sentence — rather than the pile of decode failures a changed
/// component would otherwise produce.
test "a component that changed shape is refused by name" {
  let host = Host::{ asked: [], answers: [Ok(Null)], }
  let (t, _, _) = record(h => h.click(".row", nth=0), host~)
  let stale : @trace.Trace = {
    ..t,
    origin: { ..t.origin, fingerprint: "not-the-shape-it-has", },
  }
  let said = mount_err(stale, board_scope())
  assert_true(
    said.has_prefix("`Board` has changed shape since this was recorded"),
  )
  assert_true(said.contains("not-the-shape-it-has"))
}

///|
/// The scope is hoisted out of the `try` on purpose: building one raises for
/// its own reasons, and catching those here would widen the catch back to
/// `Error` and lose the typed message this is checking.
fn mount_err(t : @trace.Trace, scope : @component.ComponentStack) -> String {
  try {
    @replay.mount(t, scope) |> ignore
    "mounted"
  } catch {
    e => e.message()
  }
}

///|
/// The other two sentences a rerun stops with, each from a failure that really
/// happens rather than from an error built by hand.
test "what a rerun says when it will not start" {
  let host = Host::{ asked: [], answers: [Ok(Null)], }
  let (t, _, _) = record(h => h.click(".row", nth=0), host~)
  // A scope that has never heard of `Board`.
  let empty = @component.ModuleDef::new(name="empty", components=[])
  inspect(
    mount_err(
      { ..t, origin: { ..t.origin, fingerprint: "", }, },
      empty.build_scope(),
    ),
    content="cannot mount: the snapshot names a component this scope cannot build (`Board`)",
  )
  inspect(
    mount_err({ ..t, version: 99, }, board_scope()),
    content="trace version 99, but this build knows 1",
  )
}

///|
/// A recording of a whole app becomes a recording of one row, and it still
/// reaches the state that row reached — which is the whole promise of the
/// operation.
test "a relocated recording replays against the subtree alone" {
  let host = Host::{ asked: [], answers: [Ok(Str("stored"))], }
  let (t, want, _) = record(
    h => {
      h.click(".row", nth=0)
      // The board sends `reset` INTO row 0. After the cut there is no board
      // left to send it, so it has to survive as an input.
      h.send_at_root("touch")
      h.click(".row", nth=0)
      // Row 1's traffic, which the cut must drop.
      h.click(".row", nth=1)
    },
    host~,
  )
  let (row_trace, gaps) = t.relocate(@trace.parse_place(".rows[0]"))
  assert_eq(gaps, [])
  // Mounted with `Row` as the ROOT — a component no example names in that
  // position, which is what the snapshot in the file is for.
  let row_origin = { ..row_trace.origin, component: "Row", fingerprint: "", }
  let p = @replay.mount({ ..row_trace, origin: row_origin, }, board_scope())
  p.run()
  // The same row state the full recording produced, with nothing of the board
  // and nothing of row 1 anywhere in it.
  assert_eq(
    p.snapshot(),
    @trace.cut_root(want, @trace.parse_place(".rows[0]")).unwrap_or(
      Json::null(),
    ),
  )
  inspect(
    p.snapshot().stringify(),
    content=(
      #|{"$component":"Row","label":"milk**","n":1}
    ),
  )
  p.destroy()
}

///|
/// The one-liner a regression test is written as.
test "replay is one call when the stepping is not the point" {
  let host = Host::{ asked: [], answers: [Ok(Null)], }
  let (t, want, _) = record(h => h.click(".row", nth=1), host~)
  assert_eq(@replay.replay(t, board_scope()), want)
}

///|
/// A rerun feeds the inputs and nothing else, and the reason is worth a test
/// rather than a comment: a derived event is what the app does ABOUT an input,
/// and the app is about to do it. Feeding one as well makes it happen twice.
///
/// The check is that a recording full of derived events reaches exactly the
/// state it recorded — which it only does if every one of them was skipped.
test "a rerun feeds the inputs and lets the app do the rest" {
  let host = Host::{ asked: [], answers: [Ok(Str("stored"))], }
  let (t, want, _) = record(
    h => {
      h.click(".row", nth=0)
      h.send_at_root("touch")
      h.click(".row", nth=1)
    },
    host~,
  )
  // Most of this recording is the app's own doing.
  assert_true(t.input_count() < t.events.length())
  let p = @replay.mount(t, board_scope())
  p.run()
  assert_eq(p.snapshot(), want)
  p.destroy()
}

///|
/// A compacted recording has only its inputs left, and reaches the same place:
/// what compacting costs is the ability to CHECK the rerun and to relocate it,
/// not the ability to run it.
test "a compacted recording still replays to the same state" {
  let host = Host::{ asked: [], answers: [Ok(Str("stored"))], }
  let (t, want, _) = record(h => h.click(".row", nth=0), host~)
  let p = @replay.mount(t.compact(), board_scope())
  p.run()
  assert_eq(p.snapshot(), want)
  p.destroy()
}
