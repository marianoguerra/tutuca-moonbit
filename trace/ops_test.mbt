// The three ways a recording gets shorter.
//
// The fixture is deliberately two levels — an app whose rows are components —
// because that is the only shape where relocation means anything, and because
// the interesting events are the ones that CROSS between the levels.

///|
fn ev(
  seq : Int,
  turn : Int,
  at : String,
  op : @trace.Op,
  input? : Bool = true,
  walk? : Int = 0,
  parent? : Int = 0,
) -> @trace.Event {
  { seq, turn, walk, parent, at: place_of(at), op, input, after: None, }
}

///|
fn two_level() -> @trace.Trace {
  let root = Json::object({
    "$component": Json::string("App"),
    "title": Json::string("shopping"),
    "rows": Json::array([
      Json::object({
        "$component": Json::string("Row"),
        "label": Json::string("milk"),
        "n": Json::number(0),
      }),
      Json::object({
        "$component": Json::string("Row"),
        "label": Json::string("eggs"),
        "n": Json::number(0),
      }),
    ]),
  })
  {
    ..@trace.Trace::new(root~),
    events: [
      // A host message at the root. Not the subtree's business.
      ev(1, 1, "", Send(name="init", args=[])),
      // A click on row 0.
      ev(2, 2, ".rows[0]", Send(name="bump", args=[])),
      // The parent reacting to it by sending INTO row 1. Derived here, and an
      // input once row 1 is on its own.
      ev(3, 2, ".rows[1]", Send(name="reset", args=[]), input=false, parent=2),
      // The parent's own bookkeeping. Gone after a cut to a row.
      ev(4, 2, ".title", Send(name="touch", args=[]), input=false, parent=2),
      // Row 0 asks the host something, and the host answers.
      ev(
        5,
        3,
        ".rows[0]",
        Intent(
          name="save",
          args=[],
          opts=@tutuca.IntentOpts::new(on_ok_name="saved"),
        ),
        input=false,
        walk=9,
        parent=2,
      ),
      ev(
        6,
        3,
        ".rows[0]",
        Offered(name="save", args=[], nth=0),
        input=false,
        walk=9,
      ),
      ev(7, 3, "", Answer(nth=0, answer=Ok(Str("stored"))), walk=9),
      // A click on row 1.
      ev(8, 4, ".rows[1]", Send(name="bump", args=[])),
    ],
  }
}

///|
fn names(t : @trace.Trace) -> String {
  t.events
  .map(e => {
    let verb = match e.op {
      Send(name~, ..) => "send:\{name}"
      Intent(name~, ..) => "intent:\{name}"
      Offered(name~, ..) => "offered:\{name}"
      Answer(..) => "answer"
      Refused(code~, ..) => "refused:\{code}"
    }
    let mark = if e.input { "" } else { "~" }
    "\{mark}\{verb}@\{e.at.label()}"
  })
  .join(" ")
}

// --- prefix -------------------------------------------------------------------

///|
/// A prefix of a recording is a recording: the state it starts from has not
/// moved, so nothing else has to change.
test "prefix keeps the root and the first n events" {
  let t = two_level()
  let p3 = t.prefix(3)
  assert_eq(p3.root, t.root)
  assert_eq(p3.events.length(), 3)
  assert_eq(t.prefix(0).events.length(), 0)
  assert_eq(t.prefix(999).events.length(), t.events.length())
  assert_eq(t.prefix(-1).events.length(), 0)
}

// --- rebase -------------------------------------------------------------------

///|
/// The caller brings the state, because computing it means running the app and
/// this package deliberately cannot.
test "rebase replaces the prefix with the state it produced" {
  let t = two_level()
  let mid = Json::object({
    "$component": Json::string("App"),
    "midway": Json::boolean(true),
  })
  let r = t.rebase(at=4, root=mid)
  assert_eq(r.root, mid)
  inspect(
    names(r),
    content="~intent:save@rows[0] ~offered:save@rows[0] answer@ send:bump@rows[1]",
  )
  // Renumbered from 1, so the tail is a recording in its own right and not a
  // slice of one that remembers where it came from.
  assert_eq(r.events.map(e => e.seq), [1, 2, 3, 4])
}

///|
/// An answer with no question is an answer a rerun would deliver to a handler
/// that was never waiting, so it goes with the intent it answered.
test "rebase drops an answer whose intent it discarded" {
  let t = two_level()
  let r = t.rebase(at=6, root=Json::null())
  // Events 6 and 7 are the offer and the answer for walk 9, whose intent (5)
  // is gone.
  inspect(names(r), content="send:bump@rows[1]")
}

///|
/// A cut lands on a turn boundary or it lands nowhere useful. Half a turn is
/// not a thing that happened: a click whose cascade is cut in the middle leaves
/// the tail beginning with a consequence whose cause is gone, and nothing can
/// produce it again.
test "a cut rounds forward to a turn boundary" {
  let t = two_level()
  // The fixture's turns start at 0, 1, 4 and 7.
  assert_eq(t.turn_boundary(0), 0)
  assert_eq(t.turn_boundary(1), 1)
  // Anywhere inside a turn rounds forward to where the next one begins.
  for n in 2..<5 {
    assert_eq(t.turn_boundary(n), 4)
  }
  for n in 5..<8 {
    assert_eq(t.turn_boundary(n), 7)
  }
  assert_eq(t.turn_boundary(99), t.events.length())
}

///|
/// A link to a discarded event is a link a reader would follow into nothing.
test "rebase carries a parent link only where the parent survived" {
  let t = two_level()
  // Rounds forward to 4, so what survives is the intent's turn and the click
  // after it — and the intent's cause, event 2, is on the far side of the cut.
  let r = t.rebase(at=2, root=Json::null())
  assert_eq(r.events.map(e => e.parent), [0, 0, 0, 0])
  // Keeping everything keeps the ancestry, renumbered onto the same events.
  let whole = t.rebase(at=0, root=Json::null())
  assert_eq(whole.events.map(e => e.parent), t.events.map(e => e.parent))
}

// --- relocate -----------------------------------------------------------------

///|
/// The headline operation. A recording of a whole app becomes a recording of
/// one row: the parent's own events are gone, the addresses are row-relative,
/// and the message the parent sent INTO the row survived — as an input, because
/// after the cut there is no parent left to send it.
test "relocate cuts a trace down to one subtree" {
  let (r, gaps) = two_level().relocate(place_of(".rows[1]"))
  inspect(names(r), content="send:reset@ send:bump@")
  assert_eq(gaps, [])
  // The new root is the row, not the app.
  inspect(
    r.root.stringify(),
    content=(
      #|{"$component":"Row","label":"eggs","n":0}
    ),
  )
  // And it says so, so a reader knows the addresses were rewritten.
  assert_eq(r.relocated_from.map(p => p.label()), ["rows[1]"])
}

///|
/// A walk belongs to its sender, not to a position: an offer's address is the
/// sender's and an answer has none at all, so both are kept by asking whose
/// walk it is rather than where it landed.
test "relocate keeps a subtree's whole conversation with the host" {
  let (r, gaps) = two_level().relocate(place_of(".rows[0]"))
  inspect(names(r), content="send:bump@ ~intent:save@ ~offered:save@ answer@")
  assert_eq(gaps, [])
  // The answer stays an input: to the relocated row, the outside IS the host.
  assert_true(r.events[3].input)
}

///|
/// Missing something is still worth having — usually it is something that did
/// not matter — so a gap is a warning beside a result, not an error instead of
/// one.
test "relocate reports what it could not carry across" {
  let t = two_level()
  // Drop the answer: now the row asks and nothing in the recording replies.
  let no_answer : @trace.Trace = {
    ..t,
    events: t.events.filter(e => !(e.op is Answer(_))),
  }
  let (_, gaps) = no_answer.relocate(place_of(".rows[0]"))
  inspect(
    gaps.map(g => g.message()).join(" / "),
    content="`save` (event 2) was answered from outside the cut, and no answer was recorded — a rerun will hear `saveUnhandled`",
  )
}

///|
test "relocate onto a place that is not there says so and stops" {
  let (r, gaps) = two_level().relocate(place_of(".rows[9]"))
  assert_eq(r.events, [])
  inspect(
    gaps.map(g => g.message()).join(" / "),
    content="`rows[9]` names nothing in the root snapshot",
  )
}

///|
/// Without the derived stream there is no way to tell an event that crossed
/// into the subtree from one that never happened, so the promotion cannot run.
/// Said out loud rather than quietly producing a recording missing its inbound
/// messages.
test "relocating a compacted trace reports the missing stream" {
  let (r, gaps) = two_level().compact().relocate(place_of(".rows[1]"))
  assert_eq(gaps, [NoDerivedStream])
  // The parent's `reset` is gone with it, which is exactly the loss the gap
  // warns about.
  inspect(names(r), content="send:bump@")
}

///|
/// Relocating twice is relocating once, deeper — and the provenance stacks, so
/// a reader can see the whole cut rather than only its last step.
test "relocations compose, and the provenance stacks" {
  let root = Json::object({
    "$component": Json::string("App"),
    "rows": Json::array([
      Json::object({
        "$component": Json::string("Row"),
        "body": Json::object({
          "$component": Json::string("Note"),
          "text": Json::string("hi"),
        }),
      }),
    ]),
  })
  let t : @trace.Trace = {
    ..@trace.Trace::new(root~),
    events: [
      ev(1, 1, "", Send(name="init", args=[])),
      ev(2, 2, ".rows[0]", Send(name="focus", args=[])),
      ev(3, 3, ".rows[0].body", Send(name="edit", args=[Str("x")])),
    ],
  }
  let (once, g1) = t.relocate(place_of(".rows[0]"))
  assert_eq(g1, [])
  inspect(names(once), content="send:focus@ send:edit@body")
  let (twice, g2) = once.relocate(place_of(".body"))
  assert_eq(g2, [])
  inspect(names(twice), content="send:edit@")
  assert_eq(twice.relocated_from.map(p => p.label()), ["rows[0]", "body"])
  inspect(
    twice.root.stringify(),
    content=(
      #|{"$component":"Note","text":"hi"}
    ),
  )
}

///|
/// A root has to be an instance. Cutting to a list is a correct cut and an
/// unmountable trace, and it is almost always one step too few — so it is
/// reported rather than discovered later as a mount that will not start.
test "relocating onto something that is not a component says so" {
  let (_, gaps) = two_level().relocate(place_of(".rows"))
  inspect(
    gaps.map(g => g.message()).join(" / "),
    content="`rows` is not a component, so the trace it cuts cannot be mounted — did you mean one step deeper, or one fewer?",
  )
}

// --- compact ------------------------------------------------------------------

///|
test "compact keeps only what a rerun feeds" {
  let t = two_level()
  assert_eq(t.input_count(), 4)
  let c = t.compact()
  inspect(
    names(c),
    content="send:init@ send:bump@rows[0] answer@ send:bump@rows[1]",
  )
  assert_eq(c.events.map(e => e.seq), [1, 2, 3, 4])
  // Every parent link pointed at something; after this most point at nothing,
  // and a link into a hole is worse than no link.
  assert_eq(c.events.map(e => e.parent), [0, 0, 0, 0])
}

// --- reading a recording ------------------------------------------------------

///|
/// A turn is what one drain consumed, and the events with no turn of their own
/// — an offer, an answer, a refusal — belong with the turn they interrupted.
test "turns group the way a rerun steps" {
  let t = two_level()
  assert_eq(t.turns().map(g => g.map(e => e.seq)), [
    [1],
    [2, 3, 4],
    [5, 6, 7],
    [8],
  ])
}

///|
/// What a relocation picker offers: the places this recording is actually
/// ABOUT, rather than every component that happens to exist.
test "places lists what the recording touched, in first-seen order" {
  assert_eq(two_level().places().map(p => p.label()), [
    "", "rows[0]", "rows[1]", "title",
  ])
}

///|
/// The promotion rule is about CAUSE, not address. An intent the subtree raised
/// for itself lands inside the cut too, and a rerun raises it again — promoting
/// that would feed the app something it was about to do anyway, and it would
/// happen twice.
test "relocate promotes what came from outside, and nothing else" {
  let (r, _) = two_level().relocate(place_of(".rows[0]"))
  let by_name = r.events.map(e => {
    let n = match e.op {
      Send(name~, ..) | Intent(name~, ..) | Offered(name~, ..) => name
      Answer(..) => "answer"
      Refused(asked~, ..) => asked
    }
    "\{n}:\{if e.input { "in" } else { "derived" }}"
  })
  // `bump` was already an input; `save` the row raised itself stays derived;
  // the offer stays derived; the host's answer stays an input.
  assert_eq(by_name, ["bump:in", "save:derived", "save:derived", "answer:in"])
}

///|
/// The other half of the same rule, from the other side.
test "a message a parent sent into the subtree becomes an input" {
  let (r, _) = two_level().relocate(place_of(".rows[1]"))
  // `reset` was derived — the parent's `bump` handler sent it — and after the
  // cut there is no parent left to send it.
  assert_eq(r.events.map(e => e.input), [true, true])
}

///|
/// A recording where nothing derived ever happened is not missing anything, and
/// warning about it would be crying wolf. Only an actual `compact` is a loss.
test "no derived events is not the same as a compacted trace" {
  let t = two_level()
  let inputs_only : @trace.Trace = {
    ..t,
    events: t.events.filter(e => e.input),
  }
  let (_, gaps) = inputs_only.relocate(place_of(".rows[1]"))
  assert_false(gaps.contains(NoDerivedStream))
  let (_, gaps2) = t.compact().relocate(place_of(".rows[1]"))
  assert_true(gaps2.contains(NoDerivedStream))
}

///|
/// The flag survives the file, or the warning would only work in memory.
test "compacted survives a round trip" {
  let c = two_level().compact()
  assert_true(c.compacted)
  assert_true(@trace.from_jsonl(c.to_jsonl()).compacted)
  assert_false(@trace.from_jsonl(two_level().to_jsonl()).compacted)
}
