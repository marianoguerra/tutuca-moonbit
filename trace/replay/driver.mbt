// Feeding a recording into a transactor somebody else owns.
//
// `Player` mounts its own app on the in-memory DOM, which is what a `moon test`
// wants and what a browser cannot use: a gallery is ONE transactor with every
// story already mounted under it, and a component's view owns its subtree
// outright, so there is nowhere to put a second app and nothing to gain from
// one. What a live replay needs is to feed the story that is already on screen.
//
// So the feeding is here, with no app, no DOM and no mounting in it, and
// `Player` is this plus "and I built the app myself". Everything that made the
// old loop small is unchanged — which events to feed is `input`, where to aim
// them is `at`, how to batch them is `turn` — and one thing is added: `base`,
// where the recording's root sits in the tree being fed.

///|
/// A recording being fed into a running transactor.
pub struct Driver {
  priv trace : @trace.Trace
  priv tx : @transactor.Transactor
  /// Where the recording's root sits in the live tree. Empty when the
  /// recording IS the tree.
  priv base : @trace.Place
  /// How many events have been fed. The index of the next one.
  priv mut at : Int
  /// The host, replaced by what it said last time — swapped in around a push
  /// and out again immediately, never left installed. `None` when the caller
  /// asked for the live host.
  priv recorded : RecordedHost?
  /// The rerun, recorded, so it can be held against the recording as like with
  /// like. `None` when `verify` is off.
  priv mut rerun : @trace.TraceRecorder?
  priv mut checked : Int
  priv mut watching : (() -> Unit)?
}

///|
/// Prepare to feed `t` into `tx`, aiming at `base`.
///
/// `verify` defaults to whether the aim is narrow enough for a comparison to
/// mean anything. Under a `base` the rerun can be filtered to the subtree the
/// recording is about; at the root of a tree that holds OTHER things — a
/// gallery's shell, its panels, its other stories — every dispatch they make is
/// indistinguishable from the app's, and holding that against the recording
/// reports a divergence on a rerun that did nothing wrong. So a rooted drive
/// does not verify unless the caller says otherwise, and a based one does.
///
/// `answer_intents` installs the recording's own answers. On by default,
/// because a recording of a component that asked the time or the network is
/// worth nothing replayed against a host that answers differently.
pub fn Driver::new(
  t : @trace.Trace,
  tx : @transactor.Transactor,
  base? : @trace.Place = Place([]),
  verify? : Bool,
  answer_intents? : Bool = true,
) -> Driver {
  let verify = match verify {
    Some(v) => v
    None => base.depth() > 0
  }
  let recorded = if answer_intents {
    Some(RecordedHost::new(Answers::of_trace(t), fallback=tx.intents()))
  } else {
    None
  }
  let d : Driver = {
    trace: t,
    tx,
    base,
    at: 0,
    recorded,
    rerun: None,
    checked: 0,
    watching: None,
  }
  if verify {
    d.watch()
  }
  d
}

///|
/// Record the rerun, so the two can be compared as like with like.
///
/// Through the `Recorder` seam and NOT through `observe`, for the reason
/// `Player` gave: a recorder reports a dispatch when it is PUSHED, an observer
/// when its handler RAN, and those are two different orders.
fn Driver::watch(self : Driver) -> Unit {
  let rec = @trace.TraceRecorder::new(root=Json::null())
  let prev = self.tx.recorder()
  self.tx.set_recorder(rec)
  self.rerun = Some(rec)
  self.watching = Some(fn() { self.tx.set_recorder(prev) })
}

///|
/// Stop watching, and put back the recorder that was there.
///
/// Restoring rather than nulling, because unlike a player's private app this
/// transactor belongs to somebody else: a gallery whose own Trace tab was
/// recording when a replay started is still recording when it ends.
pub fn Driver::stop(self : Driver) -> Unit {
  match self.watching {
    Some(off) => {
      self.watching = None
      off()
    }
    None => ()
  }
}

///|
pub fn Driver::done(self : Driver) -> Bool {
  self.at >= self.trace.events.length()
}

///|
/// How many events have been fed.
pub fn Driver::at(self : Driver) -> Int {
  self.at
}

///|
/// How many there are in all, so a caller can say "12 of 40" without reaching
/// into the recording it was handed.
pub fn Driver::total(self : Driver) -> Int {
  self.trace.events.length()
}

///|
/// The recording being fed.
pub fn Driver::trace(self : Driver) -> @trace.Trace {
  self.trace
}

///|
/// The recorded host answers, for a caller that installs them itself.
pub fn Driver::answers(self : Driver) -> Answers? {
  match self.recorded {
    Some(h) => Some(h.answers)
    None => None
  }
}

///|
/// What the app did while being fed, in the recording's own vocabulary.
pub fn Driver::observed(self : Driver) -> Array[@trace.Event] {
  self.rerun_events()
}

///|
fn Driver::rerun_events(self : Driver) -> Array[@trace.Event] {
  match self.rerun {
    Some(r) => r.take().events
    None => []
  }
}

///|
/// Push one event without settling.
///
/// Inputs only, for the reason the old loop gave: a derived event is what the
/// app does about an input, and the app is about to do it.
///
/// The address is the recording's, seen from `base` — `Place::under`, which is
/// `relocate`'s `strip_prefix` undone. A recording cut to a story says
/// `.rows[1]`; the gallery it is being fed into calls that same component
/// `.s3.rows[1]`.
fn Driver::push(self : Driver, e : @trace.Event) -> Unit {
  if !e.input {
    return
  }
  let at = @tutuca.DispatchPath::of_steps(e.at.under(self.base).to_steps())
  match e.op {
    Send(name~, args~) => self.tx.push_send(at, name, args) |> ignore
    Intent(name~, args~, opts~) =>
      self.tx.push_intent(at, name, args, opts~) |> ignore
    // The runtime's own doing, all three.
    Offered(..) | Answer(..) | Refused(..) => ()
  }
}

///|
/// Settle with the recording's answers installed, and put the live host back.
///
/// The swap is this narrow on purpose. `Answers` hands out one walk's replies
/// per ask, in order, so a recorded host left installed while ANYTHING else
/// raises an intent — a panel rebuilding itself, a shell reading the URL —
/// spends the recording's answers on questions it was not answering. The
/// divergence that follows is real and points nowhere useful.
fn Driver::settle(self : Driver) -> Unit {
  match self.recorded {
    Some(h) => {
      let live = self.tx.intents()
      self.tx.set_intents(h)
      self.tx.settle() |> ignore
      self.tx.set_intents(live)
    }
    None => self.tx.settle() |> ignore
  }
}

///|
pub fn Driver::step_event(self : Driver) -> Unit raise ReplayError {
  if self.done() {
    return
  }
  let e = self.trace.events[self.at]
  self.at = self.at + 1
  self.push(e)
  self.settle()
  self.check(self.checked)
}

///|
/// Feed one whole turn — every event the recording drained together.
pub fn Driver::step(self : Driver) -> Unit raise ReplayError {
  if self.done() {
    return
  }
  let turn = self.trace.events[self.at].turn
  while !self.done() {
    let e = self.trace.events[self.at]
    // Turn 0 is "no turn of its own" — an offer, an answer, a refusal — and
    // those belong with the turn they interrupted.
    if e.turn != 0 && e.turn != turn {
      break
    }
    self.at = self.at + 1
    self.push(e)
  }
  self.settle()
  self.check(self.checked)
}

///|
pub fn Driver::run_to(self : Driver, n : Int) -> Unit raise ReplayError {
  while self.at < n && !self.done() {
    self.step_event()
  }
}

///|
pub fn Driver::run(self : Driver) -> Unit raise ReplayError {
  while !self.done() {
    self.step()
  }
}

///|
/// Hold what the app just did against what the recording says it did.
///
/// Only the DERIVED events, and only the dispatches: the inputs are what was
/// just fed, so agreeing about them proves nothing.
///
/// Under a `base` the two sides speak different addresses — the recording's are
/// relative to the subtree, the rerun's are absolute — so the rerun is filtered
/// to the subtree and stripped back down before anything is compared. A rerun
/// dispatch OUTSIDE the base is not a divergence: it is whatever else shares
/// the transactor, doing its own work.
fn Driver::check(self : Driver, from : Int) -> Unit raise ReplayError {
  guard self.rerun is Some(_) else { return }
  fn dispatches(xs : Array[@trace.Event]) -> Array[@trace.Event] {
    xs.filter(e => e.op is Send(_) || e.op is Intent(_))
  }

  let want = dispatches(self.trace.events[0:self.at].to_owned())
  let got : Array[@trace.Event] = []
  for e in dispatches(self.rerun_events()) {
    match e.at.strip_prefix(self.base) {
      Some(rel) => got.push({ ..e, at: rel, })
      None => ()
    }
  }
  // Only as far as both go: a shorter `got` is not yet a divergence.
  let n = if want.length() < got.length() {
    want.length()
  } else {
    got.length()
  }
  for i in from..<n {
    let w = want[i]
    let g = got[i]
    if !same(w, g) {
      raise Diverged(at=i, want=w, got=g)
    }
  }
  self.checked = n
}
