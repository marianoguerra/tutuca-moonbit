// The capture seam: what a recorder is handed, when, and what it costs when
// there isn't one.
//
// The tests here are about the SEAM, not about any trace format — the shapes
// crossing it are `Dispatched`, `Offered` and `Answered`, and a recording built
// out of them lives in the `trace` package. What has to be true here is that
// the seam sees every door into the queue, tells an external dispatch from a
// derived one, and disappears entirely when nobody installed a strategy.

///|
priv struct Box {
  n : Int
}

///|
fn box(n : Int) -> @tutuca.Value {
  (Obj(Box::{ n, }) : @tutuca.Value)
}

///|
impl @tutuca.Obj for Box with fn obj_field(self, name) {
  match name {
    "n" => Some(Num(self.n.to_double()))
    _ => None
  }
}

///|
impl @tutuca.Obj for Box with fn obj_handler(self, bucket, name) {
  match (bucket, name) {
    (Receive, "bump") => Some(Handler((_a, _c) => Some(box(self.n + 1))))
    // Pushes a second dispatch: the one that must come back DERIVED.
    (Receive, "bump-twice") =>
      Some(
        Handler((_a, ctx) => {
          ctx.send("bump", [])
          Some(box(self.n + 1))
        }),
      )
    (Receive, "ask") =>
      Some(
        Handler((_a, ctx) => {
          ctx.intent(
            "save",
            [Str("x")],
            @tutuca.IntentOpts::new(route=[Lex], on_ok_name="saved"),
          )
          None
        }),
      )
    (Receive, "saved") => Some(Handler((_a, _c) => Some(box(self.n + 100))))
    _ => None
  }
}

///|
/// A recorder that keeps everything, in the one order the seam delivers it.
priv struct Tape {
  lines : Array[String]
  dispatched : Array[@transactor.Dispatched]
  offered : Array[@transactor.Offered]
  answered : Array[@transactor.Answered]
  observed : Array[@transactor.ObserveRecord]
}

///|
fn Tape::new() -> Tape {
  { lines: [], dispatched: [], offered: [], answered: [], observed: [], }
}

///|
impl @transactor.Recorder for Tape with fn recording(_self) {
  true
}

///|
impl @transactor.Recorder for Tape with fn on_dispatch(self, d) {
  self.dispatched.push(d)
  let src = if d.source is Extern { "extern" } else { "derived" }
  let bucket = if d.bucket is Receive { "send" } else { "intent" }
  self.lines.push("\{src}:\{bucket}:\{d.name}@\{d.at.to_label()}#t\{d.turn}")
}

///|
impl @transactor.Recorder for Tape with fn on_offered(self, o) {
  self.offered.push(o)
  self.lines.push("offered:\{o.name}/\{o.nth}")
}

///|
impl @transactor.Recorder for Tape with fn on_answer(self, a) {
  self.answered.push(a)
  let word = match a.answer {
    Ok(_) => "ok"
    Failed(_) => "failed"
    Pass => "pass"
  }
  self.lines.push("answered:\{word}/\{a.nth}")
}

///|
impl @transactor.Recorder for Tape with fn on_observed(self, r) {
  self.observed.push(r)
}

///|
fn at_box() -> @tutuca.DispatchPath {
  @tutuca.DispatchPath::of_steps([FieldStep("box")])
}

///|
fn rooted() -> @tutuca.Value {
  Map({ "box": box(0) })
}

///|
/// The counter inside the box, which is how every test here says "it ran".
fn n_of(root : @tutuca.Value) -> Int {
  @tutuca.Path::new(steps=[FieldStep("box"), FieldStep("n")])
  .lookup(root)
  .map(v => v.int())
  .unwrap_or(-1)
}

///|
/// The default is not "cheap", it is nothing: a transactor nobody asked to
/// record answers `false` before it builds anything, which is what keeps a
/// running page from paying for a devtool it never opened.
test "the default recorder records nothing and says so" {
  let tx = @transactor.Transactor::new(rooted())
  assert_false(tx.recorder().recording())
  let _ = tx.push_send(at_box(), "bump", [])
  tx.settle() |> ignore
  // It ran: the seam being silent is not the dispatch being skipped.
  assert_eq(n_of(tx.root), 1)
}

///|
/// The distinction the whole design rests on. A host reaching in and a handler
/// sending are the same call at the same site; `parent` is the only thing that
/// tells them apart, and only the first is something a rerun cannot produce
/// for itself.
test "a dispatch is external exactly when no handler pushed it" {
  let tx = @transactor.Transactor::new(rooted())
  let tape = Tape::new()
  tx.set_recorder(tape)
  assert_true(tx.recorder().recording())
  let _ = tx.push_send(at_box(), "bump-twice", [])
  tx.settle() |> ignore
  inspect(
    tape.lines.join(" "),
    content="extern:send:bump-twice@box#t1 derived:send:bump@box#t1",
  )
}

///|
/// A turn is everything pushed between two drains. Two host sends before one
/// settle are one turn; two settles are two. A rerun that ignored this would
/// batch differently from the recording and re-render a different number of
/// times.
test "a turn is what one drain consumed" {
  let tx = @transactor.Transactor::new(rooted())
  let tape = Tape::new()
  tx.set_recorder(tape)
  let _ = tx.push_send(at_box(), "bump", [])
  let _ = tx.push_send(at_box(), "bump", [])
  tx.settle() |> ignore
  let _ = tx.push_send(at_box(), "bump", [])
  tx.settle() |> ignore
  assert_eq(tape.dispatched.map(d => d.turn), [1, 1, 2])
}

///|
/// The host boundary, both directions, in the order it happened. The first two
/// handlers decline, so they are two offers and not one — a `Pass` is a
/// decision and a recording that collapsed them could not replay a host that
/// declined once and answered the next time.
test "the seam sees an intent leave for the host and the answer come back" {
  let asked : Array[String] = []
  let reg = Reg::{
    handlers: [
      @transactor.IntentHandler((_c, answer) => answer(Pass)),
      @transactor.IntentHandler((c, answer) => {
        asked.push(c.name)
        answer(Ok(Str("stored")))
      }),
    ],
  }
  let tx = @transactor.Transactor::new(rooted(), intents=reg)
  let tape = Tape::new()
  tx.set_recorder(tape)
  let _ = tx.push_send(at_box(), "ask", [])
  tx.settle() |> ignore
  assert_eq(asked, ["save"])
  inspect(
    tape.lines.join(" "),
    content="extern:send:ask@box#t1 " +
      "derived:intent:save@box#t1 " +
      "offered:save/0 answered:pass/0 " +
      "offered:save/1 answered:ok/1 " +
      "derived:send:saved@box#t1",
  )
  // The answer reached the component: `saved` ran.
  assert_eq(n_of(tx.root), 100)
}

///|
priv struct Reg {
  handlers : Array[@transactor.IntentHandler]
}

///|
impl @transactor.Intents for Reg with fn intents_for(self, _leaf, _name) {
  self.handlers
}

///|
/// Every hop of one intent, and the answer it produced, carry the same walk id.
/// Two walks of the same intent can be in flight at once, so the NAME cannot
/// pair an answer with the question — only this can.
test "one walk id spans every hop and the answer" {
  let reg = Reg::{
    handlers: [@transactor.IntentHandler((_c, answer) => answer(Ok(Str("y"))))],
  }
  let tx = @transactor.Transactor::new(rooted(), intents=reg)
  let tape = Tape::new()
  tx.set_recorder(tape)
  let _ = tx.push_send(at_box(), "ask", [])
  tx.settle() |> ignore
  let walks = tape.observed
    .filter(r => r.walk != 0)
    .map(r => "\{r.kind.label()}:\{r.name}/\{r.walk}")
  // The answer's kind is `answer` and not `receive` — the runtime wrote that
  // message — and it carries the walk id all the same, which is the pairing a
  // name could never provide.
  assert_eq(walks, ["intent:save/1", "answer:saved/1"])
  assert_eq(tape.offered.map(o => o.walk), [1])
  assert_eq(tape.answered.map(a => a.walk), [1])
}

///|
/// The causal link. `Transaction.parent` has always existed and has always been
/// private, so an activity log could only be a flat list; this is that edge,
/// projected onto the records a reader actually holds.
test "a derived record points back at the record that caused it" {
  let tx = @transactor.Transactor::new(rooted())
  let records : Array[@transactor.ObserveRecord] = []
  let _un = tx.observe(r => records.push(r))
  let _ = tx.push_send(at_box(), "bump-twice", [])
  tx.settle() |> ignore
  assert_eq(records.length(), 2)
  // The one a host pushed has no cause inside the tree.
  assert_eq(records[0].parent_seq, 0)
  assert_eq(records[1].parent_seq, records[0].seq)
}

///|
/// Installing a whole tree is what replaying a recording does, and doing it by
/// assigning the public field skips the notification the App re-renders on.
test "reset_root swaps the tree and wakes the subscribers" {
  let tx = @transactor.Transactor::new(rooted())
  let swaps : Array[String] = []
  tx.on_change((next, prev) => swaps.push("\{n_of(prev)}->\{n_of(next)}"))
  let other : @tutuca.Value = Map({ "box": box(7) })
  tx.reset_root(other)
  assert_eq(swaps, ["0->7"])
  // Installing what is already there is not a change, on the same physical
  // test every other subscriber is woken by.
  tx.reset_root(other)
  assert_eq(swaps.length(), 1)
}
