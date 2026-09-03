// The two capture strategies, and the small amount of interpretation between
// what the seam hands over and what a recording holds.
//
// The seam reports four things (a dispatch, an offer to a host, an answer, a
// handler having run) and a recording holds one list. The mapping is almost
// nothing, and the two places it is NOT are the two decisions worth reading:
//
//  1. An `on_observed` record is a handler having RUN, and every one of them
//     has an `on_dispatch` behind it — the same event, seen twice. The
//     recording keeps the dispatch, because that is the form a rerun can feed
//     back in, and reads the observation only for the state it produced.
//  2. `Offered` and `Answered` have no dispatch behind them at all: a lexical
//     hop is invoked inline rather than queued. They are the host boundary, and
//     they are the reason a recording of a host-integrated app is worth having.

///|
pub fn Origin::empty() -> Origin {
  { module_: "", component: "", example: "", view: "", fingerprint: "", }
}

///|
pub fn Trace::new(root~ : Json, origin? : Origin) -> Trace {
  {
    version: VERSION,
    origin: origin.unwrap_or(Origin::empty()),
    root,
    relocated_from: [],
    compacted: false,
    events: [],
  }
}

///|
pub fn TraceRecorder::new(
  root~ : Json,
  origin? : Origin,
  sink? : (String) -> Unit,
  keep_after? : Bool = false,
) -> TraceRecorder {
  let r : TraceRecorder = {
    origin: origin.unwrap_or(Origin::empty()),
    root,
    events: [],
    sink,
    keep_after,
    header_written: false,
    off: None,
  }
  r.write_header()
  r
}

///|
/// The two header lines, once, before any event can reach the sink.
///
/// Written at construction rather than lazily, so a session that records
/// nothing still produces a valid file — an empty recording of a known state is
/// a true statement, and a zero-byte file is not.
fn TraceRecorder::write_header(self : TraceRecorder) -> Unit {
  guard self.sink is Some(w) else { return }
  if self.header_written {
    return
  }
  self.header_written = true
  let t = Trace::new(root=self.root, origin=self.origin)
  let lines = t.to_jsonl().split("\n").collect()
  guard lines is [h0, h1, ..] else { return }
  w(h0.to_owned())
  w(h1.to_owned())
}

///|
/// Keep an event: down the sink, or in memory, never both.
///
/// Never both because the two are answers to different questions — a sink is a
/// session too long to hold, a buffer is a session about to be inspected — and
/// a recorder that did both would grow exactly as fast as the one that has no
/// sink, which is what the sink exists to avoid.
fn TraceRecorder::keep(self : TraceRecorder, e : Event) -> Unit {
  match self.sink {
    Some(w) => w(e.to_json().stringify())
    None => self.events.push(e)
  }
}

///|
pub fn TraceRecorder::take(self : TraceRecorder) -> Trace {
  {
    version: VERSION,
    origin: self.origin,
    root: self.root,
    relocated_from: [],
    compacted: false,
    events: self.events.copy(),
  }
}

///|
pub fn TraceRecorder::watch_refusals(self : TraceRecorder) -> () -> Unit {
  let off = @tutuca.on_runtime_notice(n => {
    match n {
      Refused(r) =>
        self.keep({
          // Seq 0: a refusal is raised from inside a handler, so the transactor's
          // counter is between two numbers and there is none to give it. Its
          // position in the list is its position in time, which is what a reader
          // uses anyway.
          seq: 0,
          turn: 0,
          walk: 0,
          parent: 0,
          at: Place::of_path(r.path),
          op: Refused(
            code=r.code.word(),
            asked=r.asked,
            rule=r.rule,
            sentence=r.sentence,
          ),
          input: false,
          after: None,
        })
      _ => ()
    }
  })
  self.off = Some(off)
  off
}

///|
pub fn TraceRecorder::stop_watching_refusals(self : TraceRecorder) -> Unit {
  match self.off {
    Some(off) => {
      self.off = None
      off()
    }
    None => ()
  }
}

///|
pub impl @transactor.Recorder for TraceRecorder with fn recording(_self) {
  true
}

///|
pub impl @transactor.Recorder for TraceRecorder with fn on_dispatch(self, d) {
  let op : Op = match d.bucket {
    Receive => Send(name=d.name, args=d.args)
    Intent => Intent(name=d.name, args=d.args, opts=d.opts)
  }
  self.keep({
    seq: d.seq,
    turn: d.turn,
    walk: d.walk,
    parent: d.parent,
    at: Place::of_path(d.at),
    op,
    input: d.origin.is_external(),
    after: None,
  })
}

///|
pub impl @transactor.Recorder for TraceRecorder with fn on_offered(self, o) {
  self.keep({
    seq: o.seq,
    turn: 0,
    walk: o.walk,
    parent: o.parent,
    at: Place::of_path(o.from),
    op: Offered(name=o.name, args=o.args, nth=o.nth),
    // Derived: a rerun offers it again. Kept because without it a reader sees
    // an intent climb the tree, stop, and an answer arrive from nowhere.
    input: false,
    after: None,
  })
}

///|
pub impl @transactor.Recorder for TraceRecorder with fn on_answer(self, a) {
  self.keep({
    seq: a.seq,
    turn: 0,
    walk: a.walk,
    parent: a.parent,
    at: Place([]),
    op: Answer(nth=a.nth, answer=a.answer),
    // An INPUT, and the only one that does not come from outside the process:
    // the host decided this, possibly long after it was asked, and nothing in
    // the tree can work it out again.
    input: true,
    after: None,
  })
}

///|
/// The state a handler produced, attached to the dispatch that caused it.
///
/// A second pass over an event already kept, rather than a fifth kind of event,
/// because it is the same event: a dispatch and the observation of its handler
/// running are one thing seen at two moments. Only reachable for a buffered
/// recorder — a line already written to a sink cannot be amended, which is the
/// honest cost of streaming and is why `keep_after` and `sink` are usually not
/// both wanted.
pub impl @transactor.Recorder for TraceRecorder with fn on_observed(self, r) {
  if !self.keep_after || self.sink is Some(_) {
    return
  }
  guard r.after is Some(a) else { return }
  // Backwards, because the dispatch this observes is the most recent one that
  // matches: an event loop is FIFO, so the nearest match is the right one.
  for i = self.events.length() - 1; i >= 0; i = i - 1 {
    let e = self.events[i]
    if e.after is None && e.at.label() == @tutuca.step_keys_label(r.path_keys) {
      let named = match e.op {
        Send(name~, ..) | Intent(name~, ..) => name == r.name
        _ => false
      }
      if named {
        self.events[i] = { ..e, after: Some(a.to_component_json()), }
        return
      }
    }
  }
}

// --- the ring -----------------------------------------------------------------

///|
pub fn RingRecorder::new(
  turns~ : Int,
  snapshot~ : () -> Json,
  origin? : Origin,
  keep_after? : Bool = false,
) -> RingRecorder {
  {
    inner: TraceRecorder::new(
      root=snapshot(),
      origin=origin.unwrap_or(Origin::empty()),
      keep_after~,
    ),
    turns: if turns < 1 {
      1
    } else {
      turns
    },
    snapshot,
    cur_turn: 0,
  }
}

///|
pub fn RingRecorder::take(self : RingRecorder) -> Trace {
  self.inner.take()
}

///|
/// Drop whole turns off the front until only `turns` remain, rebasing onto the
/// state at the cut.
///
/// Whole turns and not individual events, because half a turn is not a thing
/// that happened: a DOM event with two handlers is one turn, and a recording
/// that began between them starts from a state no snapshot describes.
///
/// The snapshot is taken when the cut happens rather than when the recording is
/// asked for, which is the whole reason this is a live recorder and not a
/// post-hoc trim: by the time somebody asks, the state the survivors start from
/// is long gone.
fn RingRecorder::rotate(self : RingRecorder, turn : Int) -> Unit {
  if turn == self.cur_turn {
    return
  }
  self.cur_turn = turn
  let seen : Array[Int] = []
  for e in self.inner.events {
    if e.turn != 0 && !seen.contains(e.turn) {
      seen.push(e.turn)
    }
  }
  // `turns - 1` of the OLD ones, because the turn just starting is the last of
  // the `turns` that will be held. Rotating to `turns` here would leave one
  // more than asked for as soon as the new turn recorded anything.
  let keep = self.turns - 1
  if seen.length() <= keep {
    return
  }
  let keep_from = if keep == 0 {
    // Only the turn about to start: everything already recorded goes.
    turn
  } else {
    seen[seen.length() - keep]
  }
  let kept : Array[Event] = self.inner.events.filter(e => e.turn >= keep_from)
  self.inner.root = (self.snapshot)()
  self.inner.events.clear()
  for e in kept {
    self.inner.events.push(e)
  }
}

///|
pub impl @transactor.Recorder for RingRecorder with fn recording(_self) {
  true
}

///|
pub impl @transactor.Recorder for RingRecorder with fn on_dispatch(self, d) {
  self.rotate(d.turn)
  @transactor.Recorder::on_dispatch(self.inner, d)
}

///|
pub impl @transactor.Recorder for RingRecorder with fn on_offered(self, o) {
  @transactor.Recorder::on_offered(self.inner, o)
}

///|
pub impl @transactor.Recorder for RingRecorder with fn on_answer(self, a) {
  @transactor.Recorder::on_answer(self.inner, a)
}

///|
pub impl @transactor.Recorder for RingRecorder with fn on_observed(self, r) {
  @transactor.Recorder::on_observed(self.inner, r)
}

// --- the scope ----------------------------------------------------------------

///|
pub fn ScopedRecorder::new(
  at~ : Place,
  root~ : Json,
  origin? : Origin,
  keep_after? : Bool = false,
) -> ScopedRecorder {
  {
    inner: TraceRecorder::new(
      root~,
      origin=origin.unwrap_or(Origin::empty()),
      keep_after~,
    ),
    at,
    kept: Map([]),
    walks: Map([]),
  }
}

///|
pub fn ScopedRecorder::take(self : ScopedRecorder) -> Trace {
  let t = self.inner.take()
  // The cut is recorded on the trace, because a reader has to know the paths
  // are subtree-relative — the same statement `relocate` makes, made by a
  // recorder that never held the whole thing.
  { ..t, relocated_from: [self.at], }
}

///|
/// Whether this event is the scope's business, and where it sits once it is.
///
/// `None` means drop it; `Some(place)` is its address seen from the cut. The
/// bookkeeping is the side effect: an admitted event's `seq` is remembered, so
/// the next one can ask whether its CAUSE survived — which is how a derived
/// event that came from outside is spotted and promoted.
fn ScopedRecorder::admit(
  self : ScopedRecorder,
  seq : Int,
  at : @tutuca.Path,
  walk : Int,
) -> Place? {
  let place = Place::of_path(at)
  let inside = place.starts_with(self.at)
  let ours = walk != 0 && self.walks.get(walk) is Some(_)
  guard inside || ours else { return None }
  self.kept[seq] = true
  if walk != 0 && inside {
    self.walks[walk] = true
  }
  Some(place.strip_prefix(self.at).unwrap_or(Place([])))
}

///|
pub impl @transactor.Recorder for ScopedRecorder with fn recording(_self) {
  true
}

///|
pub impl @transactor.Recorder for ScopedRecorder with fn on_dispatch(self, d) {
  guard self.admit(d.seq, d.at, d.walk) is Some(at) else { return }
  // Promoted for the same reason `relocate` promotes: a message something
  // outside the scope sent in is not the scope's own doing, and after the cut
  // nothing remains to send it. `admit` recorded this event's seq already, so
  // the question is about its PARENT and cannot be about itself.
  let orphan = !d.origin.is_external() && self.kept.get(d.parent) is None
  let op : Op = match d.bucket {
    Receive => Send(name=d.name, args=d.args)
    Intent => Intent(name=d.name, args=d.args, opts=d.opts)
  }
  self.inner.keep({
    seq: d.seq,
    turn: d.turn,
    walk: d.walk,
    parent: d.parent,
    at,
    op,
    input: d.origin.is_external() || orphan,
    after: None,
  })
}

///|
pub impl @transactor.Recorder for ScopedRecorder with fn on_offered(self, o) {
  guard self.admit(o.seq, o.from, o.walk) is Some(at) else { return }
  self.inner.keep({
    seq: o.seq,
    turn: 0,
    walk: o.walk,
    parent: o.parent,
    at,
    op: Offered(name=o.name, args=o.args, nth=o.nth),
    input: false,
    after: None,
  })
}

///|
pub impl @transactor.Recorder for ScopedRecorder with fn on_answer(self, a) {
  // An answer has no address, so it is kept by whose walk it is and by nothing
  // else — which is exactly the case `admit`'s `ours` branch exists for.
  guard a.walk != 0 && self.walks.get(a.walk) is Some(_) else { return }
  self.kept[a.seq] = true
  self.inner.keep({
    seq: a.seq,
    turn: 0,
    walk: a.walk,
    parent: a.parent,
    at: Place([]),
    op: Answer(nth=a.nth, answer=a.answer),
    input: true,
    after: None,
  })
}

///|
pub impl @transactor.Recorder for ScopedRecorder with fn on_observed(self, r) {
  @transactor.Recorder::on_observed(self.inner, r)
}
