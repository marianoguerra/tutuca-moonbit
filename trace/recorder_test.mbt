// The recorders, driven by a real transactor.
//
// Everything above this file tests a `Trace` somebody wrote by hand. This one
// tests the only thing that matters about a recorder: that what the runtime did
// and what the recording says are the same story.

///|
priv struct Counter {
  n : Int
}

///|
fn counter(n : Int) -> @tutuca.Value {
  (Obj(Counter::{ n, }) : @tutuca.Value)
}

///|
impl @tutuca.Obj for Counter with fn field(self, name) {
  match name {
    "n" => Some(Num(self.n.to_double()))
    _ => None
  }
}

///|
impl @tutuca.Obj for Counter with fn schema(_self) {
  Some(
    @tutuca.SchemaInfo::new(name="Counter", fingerprint="cafe", fields=[
      @tutuca.FieldInfo::new("n", TyInt(width=32, signed=true)),
    ]),
  )
}

///|
impl @tutuca.Obj for Counter with fn handler(self, bucket, name) {
  match (bucket, name) {
    (Receive, "inc") => Some(Handler((_a, _c) => Some(counter(self.n + 1))))
    (Receive, "inc-twice") =>
      Some(
        Handler((_a, ctx) => {
          ctx.send("inc", [])
          Some(counter(self.n + 1))
        }),
      )
    (Receive, "ask") =>
      Some(
        Handler((_a, ctx) => {
          ctx.intent(
            "save",
            [Num(self.n.to_double())],
            @tutuca.IntentOpts::new(route=[Lex], on_ok_name="stored"),
          )
          None
        }),
      )
    (Receive, "stored") => Some(Handler((_a, _c) => Some(counter(self.n + 10))))
    // A rule declining, the way a body with a contract reports one. This is
    // what actually reaches the refusal channel: an unclaimed NAME is an
    // observation with `NoHandler` and stays quiet, by design.
    (Receive, "guarded") =>
      Some(
        Handler((_a, _c) => {
          @tutuca.precondition_failed(
            handler="guarded",
            pred="isPositive",
            sentence="the counter is at zero",
            state=Num(0),
          )
          None
        }),
      )
    _ => None
  }
}

///|
priv struct Host {
  answers : Array[@tutuca.IntentAnswer]
  asked : Array[String]
}

///|
impl @transactor.Intents for Host with fn intents_for(self, _leaf, name) {
  [
    IntentFn((_c, answer) => {
      self.asked.push(name)
      let i = self.asked.length() - 1
      answer(self.answers[if i < self.answers.length() { i } else { 0 }])
    }),
  ]
}

///|
fn app_root() -> @tutuca.Value {
  Map({ "box": counter(0) })
}

///|
fn box_at() -> @tutuca.DispatchPath {
  @tutuca.DispatchPath::of_steps([FieldStep("box")])
}

///|
fn recorded(
  drive : (@transactor.Transactor) -> Unit,
  intents? : &@transactor.Intents,
  keep_after? : Bool = false,
) -> @trace.Trace {
  let tx = @transactor.Transactor::new(app_root(), intents?)
  let rec = @trace.TraceRecorder::new(
    root=tx.root.to_component_json(),
    origin={
      module_: "demo",
      component: "Counter",
      example: "",
      view: "",
      fingerprint: "cafe",
    },
    keep_after~,
  )
  tx.set_recorder(rec)
  drive(tx)
  rec.take()
}

///|
fn story(t : @trace.Trace) -> String {
  t.events
  .map(e => {
    let verb = match e.op {
      Send(name~, ..) => "send:\{name}"
      Intent(name~, ..) => "intent:\{name}"
      Offered(name~, nth~, ..) => "offered:\{name}/\{nth}"
      Answer(nth~, answer~) => {
        let w = match answer {
          Ok(_) => "ok"
          Failed(_) => "failed"
          Pass => "pass"
        }
        "answer:\{w}/\{nth}"
      }
      Refused(code~, asked~, ..) => "refused:\{code}@\{asked}"
    }
    "\{if e.input { "" } else { "~" }}\{verb}"
  })
  .join(" ")
}

///|
/// A host push and the send a handler makes in response are the same call at
/// the same site; only one of them is something a rerun cannot produce.
test "a recording tells what happened to the app from what the app did" {
  let t = recorded(tx => {
    let _ = tx.push_send(box_at(), "inc-twice", [])
    tx.settle() |> ignore
  })
  inspect(story(t), content="send:inc-twice ~send:inc")
  assert_eq(t.input_count(), 1)
  // And the state it started from is the state it started from.
  inspect(
    t.root.stringify(),
    content=(
      #|{"box":{"$component":"Counter","n":0}}
    ),
  )
}

///|
/// The whole host conversation, in the order it happened. The first handler
/// declines and the second answers, which is two offers: a `Pass` is a decision
/// and a recording that collapsed them could not replay a host that declined
/// once and answered the next time.
test "a recording carries both directions of the host boundary" {
  let host = Host::{ answers: [Ok(Str("saved"))], asked: [], }
  let t = recorded(
    tx => {
      let _ = tx.push_send(box_at(), "ask", [])
      tx.settle() |> ignore
    },
    intents=host,
  )
  inspect(
    story(t),
    content="send:ask ~intent:save ~offered:save/0 answer:ok/0 ~send:stored",
  )
  // The answer is an INPUT — the only one here that did not come from outside
  // the process. Nothing in the tree can work it out again.
  let answers = t.events.filter(e => e.op is Answer(_))
  assert_eq(answers.map(e => e.input), [true])
}

///|
/// A rerun has to know the arm name the sender declared, or it delivers the
/// reply to a handler that does not exist.
test "an intent's options reach the recording" {
  let host = Host::{ answers: [Ok(Null)], asked: [], }
  let t = recorded(
    tx => {
      let _ = tx.push_send(box_at(), "ask", [])
      tx.settle() |> ignore
    },
    intents=host,
  )
  let intents = t.events.filter(e => e.op is Intent(_))
  assert_eq(intents.length(), 1)
  assert_true(
    intents[0].op
    is Intent(opts={ on_ok_name: Some("stored"), route: [Lex], .. }, ..),
  )
}

///|
/// Every hop of one intent and the answer it produced carry the same walk id.
/// Two walks of the same intent can be in flight at once, so the name cannot
/// pair an answer with the question.
test "one walk id ties the conversation together" {
  let host = Host::{ answers: [Ok(Null)], asked: [], }
  let t = recorded(
    tx => {
      let _ = tx.push_send(box_at(), "ask", [])
      tx.settle() |> ignore
    },
    intents=host,
  )
  let walks = t.events.filter(e => e.walk != 0).map(e => e.walk)
  assert_eq(walks.length(), 4)
  assert_true(walks.iter().all(w => w == walks[0]))
}

///|
/// A turn is what one drain consumed. Two host sends before one settle are one
/// turn; two settles are two. A rerun that ignored this would settle twice
/// where the recording settled once, and re-render twice.
test "turns are drains, not dispatches" {
  let t = recorded(tx => {
    let _ = tx.push_send(box_at(), "inc", [])
    let _ = tx.push_send(box_at(), "inc", [])
    tx.settle() |> ignore
    let _ = tx.push_send(box_at(), "inc", [])
    tx.settle() |> ignore
  })
  assert_eq(t.turns().map(g => g.length()), [2, 1])
}

///|
/// The refusal channel, which is not the transactor's: a recording of a bug
/// that ends in a refusal has to carry the refusal, or it is a recording of
/// nothing happening.
test "a recording can carry the refusals too" {
  let tx = @transactor.Transactor::new(app_root())
  let rec = @trace.TraceRecorder::new(root=tx.root.to_component_json())
  tx.set_recorder(rec)
  let off = rec.watch_refusals()
  let _ = tx.push_send(box_at(), "guarded", [])
  tx.settle() |> ignore
  off()
  inspect(
    story(rec.take()),
    content="send:guarded ~refused:PRECONDITION@guarded",
  )
  // And the sentence the rule produced came with it, which is the whole reason
  // a refusal is worth a line: `to_line` folds the code into prose and drops
  // the state, and a recording needs both back.
  let refusals = rec.take().events.filter(e => e.op is Refused(_))
  assert_true(
    refusals[0].op
    is Refused(rule="isPositive", sentence="the counter is at zero", ..),
  )
  // Detaching is idempotent, because a panel whose stop button is pressed twice
  // should not have to remember.
  rec.stop_watching_refusals()
  rec.stop_watching_refusals()
}

///|
/// What the recording writes and what a reader gets back are the same trace.
test "a recorded trace survives its own file format" {
  let host = Host::{ answers: [Ok(Str("saved"))], asked: [], }
  let t = recorded(
    tx => {
      let _ = tx.push_send(box_at(), "ask", [])
      tx.settle() |> ignore
      let _ = tx.push_send(box_at(), "inc-twice", [])
      tx.settle() |> ignore
    },
    intents=host,
  )
  assert_eq(@trace.from_jsonl(t.to_jsonl()), t)
}

///|
/// A sink is for a session too long to hold and a buffer is for one about to be
/// inspected — so a recorder does one or the other, never both, or the sink
/// would grow exactly as fast as the thing it exists to avoid.
test "a streaming recorder writes the same bytes it would have buffered" {
  let lines : Array[String] = []
  let tx = @transactor.Transactor::new(app_root())
  let rec = @trace.TraceRecorder::new(root=tx.root.to_component_json(), sink=l => {
    lines.push(l)
  })
  tx.set_recorder(rec)
  let _ = tx.push_send(box_at(), "inc-twice", [])
  tx.settle() |> ignore
  // Two headers plus two events, and it held none of them.
  assert_eq(lines.length(), 4)
  assert_eq(rec.take().events.length(), 0)
  let streamed = @trace.from_jsonl(lines.join("\n") + "\n")
  let buffered = recorded(t2 => {
    let _ = t2.push_send(box_at(), "inc-twice", [])
    t2.settle() |> ignore
  })
  assert_eq(story(streamed), story(buffered))
}

///|
/// The flight recorder. In a long session the recording you want is the one
/// just before it broke, and keeping the whole thing to get the end of it is
/// the wrong trade.
test "a ring recorder keeps the last turns, and stays a complete trace" {
  let tx = @transactor.Transactor::new(app_root())
  let rec = @trace.RingRecorder::new(turns=2, snapshot=() => {
    tx.root.to_component_json()
  })
  tx.set_recorder(rec)
  for i in 0..<5 {
    ignore(i)
    let _ = tx.push_send(box_at(), "inc-twice", [])
    tx.settle() |> ignore
  }
  let t = rec.take()
  // Two turns of two events each — whole turns, because half a turn is not a
  // thing that happened.
  assert_eq(t.turns().map(g => g.length()), [2, 2])
  // And it starts from the state AT THE CUT, not from where the session began:
  // a suffix would start from a state nothing describes. Five turns of
  // `inc-twice` reach n=10, and the snapshot was taken when turn 5 began — so
  // n=8, and replaying the two turns it kept gets to 10.
  inspect(
    t.root.stringify(),
    content=(
      #|{"box":{"$component":"Counter","n":8}}
    ),
  )
}

///|
/// Worth having in a devtool and not worth the size in a long session, which is
/// why it is off by default.
test "keep_after records the state each handler produced" {
  let t = recorded(
    tx => {
      let _ = tx.push_send(box_at(), "inc", [])
      tx.settle() |> ignore
    },
    keep_after=true,
  )
  assert_eq(t.events.length(), 1)
  inspect(
    t.events[0].after.map(a => a.stringify()).unwrap_or("none"),
    content=(
      #|{"$component":"Counter","n":1}
    ),
  )
  // Off by default, because a long session pays for it on every event.
  let plain = recorded(tx => {
    let _ = tx.push_send(box_at(), "inc", [])
    tx.settle() |> ignore
  })
  assert_eq(plain.events[0].after, None)
}

///|
priv struct Pair {
  a : @tutuca.Value
  b : @tutuca.Value
}

///|
impl @tutuca.Obj for Pair with fn field(self, name) {
  match name {
    "a" => Some(self.a)
    "b" => Some(self.b)
    _ => None
  }
}

///|
impl @tutuca.Obj for Pair with fn with_field(self, name, v) {
  match name {
    "a" => Some(Obj(Pair::{ a: v, b: self.b, }))
    "b" => Some(Obj(Pair::{ a: self.a, b: v, }))
    _ => None
  }
}

///|
impl @tutuca.Obj for Pair with fn schema(_self) {
  Some(
    @tutuca.SchemaInfo::new(name="Pair", fingerprint="pair", fields=[
      @tutuca.FieldInfo::new("a", TyComp(Some("Counter"))),
      @tutuca.FieldInfo::new("b", TyComp(Some("Counter"))),
    ]),
  )
}

///|
impl @tutuca.Obj for Pair with fn handler(_self, bucket, name) {
  match (bucket, name) {
    // The cross-branch event: touching one side pokes the OTHER. After a cut
    // to `b` this is the message that has to survive as an input, because
    // there is no parent left to send it.
    (Receive, "poke") =>
      Some(
        Handler((_a, ctx) => {
          ctx.at().field("b").send("inc", [])
          None
        }),
      )
    _ => None
  }
}

///|
fn pair_root() -> @tutuca.Value {
  Obj(Pair::{ a: counter(0), b: counter(0), })
}

///|
fn at_field(f : String) -> @tutuca.DispatchPath {
  @tutuca.DispatchPath::of_steps([FieldStep(f)])
}

///|
/// A gallery is ONE transactor with every story mounted under it, so narrowing
/// a recording cannot be done by mounting less. This is what it is done by
/// instead — and the claim worth testing is that it agrees with the lossless
/// route: record everything, then cut.
test "recording a scope agrees with recording everything and cutting" {
  fn drive(tx : @transactor.Transactor) -> Unit {
    let _ = tx.push_send(at_field("a"), "inc", [])
    tx.settle() |> ignore
    let _ = tx.push_send(at_field("b"), "inc-twice", [])
    tx.settle() |> ignore
    // The parent reaching into `b`.
    let _ = tx.push_send(@tutuca.DispatchPath::new(), "poke", [])
    tx.settle() |> ignore
  }

  let place = @trace.parse_place(".b")
  // Scoped, as it happens.
  let tx1 = @transactor.Transactor::new(pair_root())
  let scoped = @trace.ScopedRecorder::new(
    at=place,
    root=@trace.cut_root(tx1.root.to_component_json(), place).unwrap_or(
      Json::null(),
    ),
  )
  tx1.set_recorder(scoped)
  drive(tx1)
  // Everything, then cut.
  let tx2 = @transactor.Transactor::new(pair_root())
  let whole = @trace.TraceRecorder::new(root=tx2.root.to_component_json())
  tx2.set_recorder(whole)
  drive(tx2)
  let (cut, gaps) = whole.take().relocate(place)
  assert_eq(gaps, [])
  assert_eq(story(scoped.take()), story(cut))
  // Two events under `b` plus the one the parent sent in, and nothing of `a`.
  inspect(story(cut), content="send:inc-twice ~send:inc send:inc")
  // And both say the paths were rewritten, so a reader is not misled about
  // what the addresses mean.
  assert_eq(scoped.take().relocated_from.map(p => p.label()), ["b"])
}

///|
/// The scope's own root is the SUBTREE's snapshot. A recording of a subtree
/// that started from the whole app's state would be a recording nothing can
/// mount.
test "a scoped recording starts from the subtree's state" {
  let tx = @transactor.Transactor::new(pair_root())
  let place = @trace.parse_place(".b")
  let rec = @trace.ScopedRecorder::new(
    at=place,
    root=@trace.cut_root(tx.root.to_component_json(), place).unwrap_or(
      Json::null(),
    ),
  )
  tx.set_recorder(rec)
  let _ = tx.push_send(at_field("b"), "inc", [])
  tx.settle() |> ignore
  inspect(
    rec.take().root.stringify(),
    content=(
      #|{"$component":"Counter","n":0}
    ),
  )
}
