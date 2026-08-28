// Feeding a recording back into a running app.
//
// The loop is small, and it is small on purpose: everything a rerun needs to
// decide was decided when the recording was written. Which events to feed is
// `input`; where to aim them is `at`; how to batch them is `turn`; what the
// host says is the answers. What is left here is doing it, and noticing when
// the app disagrees.

///|
pub fn mount(
  t : @trace.Trace,
  scope : @component.ComponentStack,
  fidelity? : Fidelity = Live,
  verify? : Bool = true,
) -> Player raise ReplayError {
  if t.version != @trace.VERSION {
    raise UnknownVersion(got=t.version)
  }
  guard @tutuca.Value::from_component_json(t.root, scope) is Some(root) else {
    raise RootUnbuildable(
      "the snapshot names a component this scope cannot build" +
      (if t.origin.component == "" { "" } else { " (`\{t.origin.component}`)" }),
    )
  }
  // The shape check, before anything runs. A component whose fields moved
  // decodes into something that is almost right, and every symptom after that
  // points somewhere else.
  if t.origin.fingerprint != "" && root.schema() is Some(sc) {
    let got = sc.shape_fingerprint()
    if got != t.origin.fingerprint {
      raise ShapeChanged(component=sc.name, want=t.origin.fingerprint, got~)
    }
  }
  let (doc, container) = @harness.new_mount()
  // Built once and handed to the host, which is the only thing that reads it:
  // the player itself never asks what the recording answered, it just watches
  // what the app does with the reply.
  let answers = Answers::of_trace(t)
  // The recorded host, over whatever the scope registered. `ScopeIntents` is
  // what an ordinarily-mounted app uses, and keeping it as the FALLBACK is what
  // lets a relocated recording replay against a live host for the parts it
  // never captured.
  let live : &@transactor.Intents = @app.ScopeIntents::{ comps: scope.comps, }
  // Mounting can fail for reasons of its own — a view that will not compile, a
  // root view the component does not declare — and a caller of this has one
  // question either way: is this the scope the recording was made against.
  // So one error type reaches them, rather than two.
  let app = try {
    let a = @app.App::new(
      scope,
      root,
      container,
      @vdom.RenderOpts::new(doc),
      view=t.origin.view,
      intents=RecordedHost::new(answers, fallback=live),
    )
    // Inside the same `try` as the construction, and not only for brevity:
    // whether the first render raises depends on the backend, and a separate
    // `try` around it is dead code on the ones where it does not.
    a.start()
    a
  } catch {
    e => raise RootUnbuildable(e.to_string())
  }
  let p : Player = {
    app,
    container,
    trace: t,
    fidelity,
    at: 0,
    rerun: None,
    checked: 0,
    watching: None,
  }
  if verify {
    p.watch()
  }
  p
}

///|
/// Record the rerun, so the two can be compared as like with like.
///
/// Through the `Recorder` seam and NOT through `observe`, and the difference is
/// the only thing that makes a comparison meaningful: a recorder reports a
/// dispatch when it is PUSHED, an observer when its handler RAN, and those are
/// two different orders. An intent raised inside a handler is pushed second and
/// runs first, so holding one stream against the other reports a divergence on
/// a rerun that did exactly the right thing.
///
/// So a rerun records itself. That sounds circular and is not: the recording
/// being fed and the recording being made come from the same producer, in the
/// same vocabulary, in the same order, and the whole question is whether they
/// say the same thing.
fn Player::watch(self : Player) -> Unit {
  let rec = @trace.TraceRecorder::new(root=Json::null())
  self.app.transactor.set_recorder(rec)
  self.rerun = Some(rec)
  self.watching = Some(fn() {
    self.app.transactor.set_recorder(@transactor.NullRecorder::{ })
  })
}

///|
/// What the rerun did, in the recording's own vocabulary.
fn Player::rerun_events(self : Player) -> Array[@trace.Event] {
  match self.rerun {
    Some(r) => r.take().events
    None => []
  }
}

///|
pub fn Player::destroy(self : Player) -> Unit {
  match self.watching {
    Some(off) => {
      self.watching = None
      off()
    }
    None => ()
  }
}

///|
pub fn Player::done(self : Player) -> Bool {
  self.at >= self.trace.events.length()
}

///|
pub fn Player::snapshot(self : Player) -> Json {
  self.app.root_value().to_component_json()
}

///|
pub fn Player::harness(self : Player) -> @harness.MemHarness {
  @harness.Harness::over(self.app, self.container)
}

///|
pub fn Player::html(self : Player) -> String {
  @harness.clean_html(self.container)
}

///|
pub fn Player::observed(self : Player) -> Array[@trace.Event] {
  self.rerun_events()
}

///|
/// Push one event without settling.
///
/// Inputs only. A derived event is what the app does about an input, and the
/// app is about to do it — feeding one as well would make it happen twice.
fn Player::push(self : Player, e : @trace.Event) -> Unit {
  if !e.input {
    return
  }
  let at = @tutuca.DispatchPath::of_steps(e.at.to_steps())
  match e.op {
    Send(name~, args~) =>
      self.app.transactor.push_send(at, name, args) |> ignore
    Intent(name~, args~, opts~) =>
      self.app.transactor.push_intent(at, name, args, opts~) |> ignore
    // The runtime's own doing, all three. An offer and an answer are the walk
    // being served, which pushing the intent already sets in motion; a refusal
    // is something the app raises for itself if it is going to.
    Offered(..) | Answer(..) | Refused(..) => ()
  }
}

///|
pub fn Player::step_event(self : Player) -> Unit raise ReplayError {
  if self.done() {
    return
  }
  let e = self.trace.events[self.at]
  self.at = self.at + 1
  self.push(e)
  self.app.transactor.settle() |> ignore
  self.check(self.checked)
}

///|
pub fn Player::step(self : Player) -> Unit raise ReplayError {
  if self.done() {
    return
  }
  // Every event of one turn, pushed before the drain — because that is what a
  // turn IS. Settling between them would re-render once per handler where the
  // recording rendered once per event.
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
  self.app.transactor.settle() |> ignore
  self.check(self.checked)
}

///|
pub fn Player::run_to(self : Player, n : Int) -> Unit raise ReplayError {
  while self.at < n && !self.done() {
    self.step_event()
  }
}

///|
pub fn Player::run(self : Player) -> Unit raise ReplayError {
  while !self.done() {
    self.step()
  }
}

///|
/// Hold what the app just did against what the recording says it did.
///
/// Only the DERIVED events are compared, and only in `Live`. The inputs are
/// what was just fed, so agreeing about them proves nothing; the derived ones
/// are the app's own work, and they are the whole of what a regression test is
/// asking about.
fn Player::check(self : Player, from : Int) -> Unit raise ReplayError {
  guard self.rerun is Some(_) else { return }
  // Only the DISPATCHES, from both sides. An offer, an answer and a refusal are
  // the host's and the runtime's; what a regression test is asking about is
  // what the app dispatched.
  fn dispatches(xs : Array[@trace.Event]) -> Array[@trace.Event] {
    xs.filter(e => e.op is Send(_) || e.op is Intent(_))
  }

  let want = dispatches(self.trace.events[0:self.at].to_owned())
  let got = dispatches(self.rerun_events())
  // Only as far as both go: a shorter `got` is not yet a divergence, because
  // the recording holds events the turns fed so far have not reached.
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

///|
/// Whether two events are the same THING happening.
///
/// Name, address and kind. Not the arguments, and not the sequence numbers:
/// numbering shifts as soon as anything upstream does, and comparing arguments
/// would report a rounding difference as a behavioural change. What a reader
/// means by "the app did something else" is that it dispatched something else,
/// somewhere else.
fn same(a : @trace.Event, b : @trace.Event) -> Bool {
  if a.at.label() != b.at.label() {
    return false
  }
  match (a.op, b.op) {
    (Send(name=x, ..), Send(name=y, ..)) => x == y
    (Intent(name=x, ..), Intent(name=y, ..)) => x == y
    _ => false
  }
}

///|
pub fn replay(
  t : @trace.Trace,
  scope : @component.ComponentStack,
  fidelity? : Fidelity = Live,
  verify? : Bool = true,
) -> Json raise ReplayError {
  let p = mount(t, scope, fidelity~, verify~)
  p.run()
  let out = p.snapshot()
  p.destroy()
  out
}

///|
pub fn ReplayError::message(self : ReplayError) -> String {
  match self {
    Diverged(at~, want~, got~) =>
      "at event \{at} the recording says `\{op_label(want)}` and the app did `\{op_label(got)}`"
    ShapeChanged(component~, want~, got~) =>
      "`\{component}` has changed shape since this was recorded (\{want} -> \{got})"
    RootUnbuildable(why) => "cannot mount: \{why}"
    UnknownVersion(got~) =>
      "trace version \{got}, but this build knows \{@trace.VERSION}"
  }
}

///|
fn op_label(e : @trace.Event) -> String {
  let verb = match e.op {
    Send(name~, ..) => name
    Intent(name~, ..) => "intent \{name}"
    Offered(name~, ..) => "offer \{name}"
    Answer(..) => "answer"
    Refused(code~, ..) => "refused \{code}"
  }
  let at = e.at.label()
  if at == "" {
    verb
  } else {
    "\{verb} at \{at}"
  }
}
