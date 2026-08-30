// `Driver` is `Player` minus the app. These are the two claims that adds:
// a drive at no base does what a player does, and a drive at a base aims the
// recording's addresses at the right component in somebody else's tree.

///|
/// Mount a board and hand back the app, so a driver can be pointed at a
/// transactor this test owns rather than one `mount` made for it.
fn live_board() -> (@app.App[@memdom.MemNode], @memdom.MemNode) raise {
  let scope = board_scope()
  let root = board_value(scope)
  let (doc, container) = @harness.new_mount()
  let app = @app.App::new(scope, root, container, @vdom.RenderOpts::new(doc), intents=@app.ScopeIntents::{
    comps: scope.comps,
  })
  app.start()
  (app, container)
}

///|
/// At no base a driver is a player: same events in, same state out.
///
/// The point of asserting it against `Player` rather than against a literal is
/// that `Player` is now IMPLEMENTED as a driver — so this says the extraction
/// kept the behaviour, which is the only thing the refactor promised.
test "a driver at no base agrees with a player" {
  let (t, _, _) = record(h => {
    h.click(".row", nth=0)
    h.click(".row", nth=1)
    h.send_at_root("touch")
  })
  let p = @replay.mount(t, board_scope())
  p.run()
  let want = p.snapshot()
  p.destroy()
  let (app, _) = live_board()
  let d = @replay.Driver::new(t, app.transactor, verify=true)
  d.run()
  d.stop()
  assert_eq(app.root_value().to_component_json(), want)
}

///|
/// The claim the whole seam exists for: a recording cut to a subtree replays
/// INTO that subtree of a tree it was not cut from.
///
/// `relocate` rewrote every address down to the row; `Place::under` puts the
/// prefix back on the way in. If the two ever stop being inverses, the events
/// land on the wrong row and this fails with a row that never moved.
test "a relocated recording drives the subtree it was cut to" {
  let at = @trace.parse_place(".rows[0]")
  // With a host, so the row's `save` intent has a recorded answer: a relocated
  // recording carries the answers that crossed INTO it, and driving it back is
  // where that stops being a claim.
  let host = Host::{ asked: [], answers: [Ok(Str("stored"))], }
  let (t, whole, _) = record(
    h => {
      h.click(".row", nth=0)
      h.click(".row", nth=0)
      h.click(".row", nth=1)
    },
    host~,
  )
  let (cut, gaps) = t.relocate(at)
  assert_eq(gaps, [])
  let (app, _) = live_board()
  let d = @replay.Driver::new(cut, app.transactor, base=at)
  d.run()
  d.stop()
  // Only the row is claimed: the recording was cut to it, so the board's other
  // rows are still where the fixture left them and comparing the whole tree
  // would be comparing something this never fed.
  let got = @trace.cut_root(app.root_value().to_component_json(), at)
  assert_eq(got, @trace.cut_root(whole, at))
}

///|
/// A driver aimed at a base leaves everything outside it alone — including
/// whatever else shares the transactor, which in a gallery is every other
/// story and the whole shell.
test "a based drive touches nothing outside the base" {
  let at = @trace.parse_place(".rows[0]")
  let (t, _, _) = record(h => {
    h.click(".row", nth=0)
    h.click(".row", nth=1)
  })
  let (cut, _) = t.relocate(at)
  let (app, _) = live_board()
  let before = @trace.cut_root(
    app.root_value().to_component_json(),
    @trace.parse_place(".rows[1]"),
  )
  let d = @replay.Driver::new(cut, app.transactor, base=at)
  d.run()
  d.stop()
  let after = @trace.cut_root(
    app.root_value().to_component_json(),
    @trace.parse_place(".rows[1]"),
  )
  assert_eq(after, before)
}

///|
/// `stop` puts back the recorder that was there, rather than nulling it.
///
/// It matters because the transactor is somebody else's: a gallery whose Trace
/// tab was recording when a replay started is still recording when it ends,
/// and a driver that cleared the slot would have silently stopped it.
test "stop restores the recorder it displaced" {
  let (t, _, _) = record(h => h.click(".row", nth=0))
  let (app, _) = live_board()
  let mine = @trace.TraceRecorder::new(
    root=app.root_value().to_component_json(),
  )
  app.transactor.set_recorder(mine)
  let d = @replay.Driver::new(t, app.transactor, verify=true)
  d.run()
  d.stop()
  // Still recording into the same one: a send after the replay reaches it.
  let before = mine.take().events.length()
  app.send_at_root("touch") |> ignore
  assert_true(mine.take().events.length() > before)
}

///|
/// A driver reports how far it has got, so a viewer can say "12 of 40" without
/// reaching into the recording it was handed.
test "at and total track the feeding" {
  let (t, _, _) = record(h => {
    h.click(".row", nth=0)
    h.click(".row", nth=1)
  })
  let (app, _) = live_board()
  let d = @replay.Driver::new(t, app.transactor, verify=true)
  assert_eq(d.at(), 0)
  assert_true(d.total() > 0)
  d.step()
  assert_true(d.at() > 0)
  d.run()
  assert_true(d.done())
  assert_eq(d.at(), d.total())
  d.stop()
}
