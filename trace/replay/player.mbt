// Feeding a recording back into a running app.
//
// The loop is small, and it is small on purpose: everything a rerun needs to
// decide was decided when the recording was written. Which events to feed is
// `input`; where to aim them is `at`; how to batch them is `turn`; what the
// host says is the answers. What is left here is doing it, and noticing when
// the app disagrees.

///|
/// The recording's initial state, rebuilt against `scope`.
///
/// Extracted from `mount` because a rerun that does NOT mount — one fed into a
/// tree somebody else already mounted — needs the same three guards, and losing
/// them on that path is how "it replays wrong" stays unexplained. A version
/// this build cannot read, a snapshot naming a component the scope cannot
/// build, and a component whose fields have moved are each one sentence here
/// and a mystery anywhere else.
pub fn root_for(
  t : @trace.Trace,
  scope : @component.ComponentStack,
) -> @tutuca.Value raise ReplayError {
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
  root
}

///|
pub fn mount(
  t : @trace.Trace,
  scope : @component.ComponentStack,
  fidelity? : Fidelity = Live,
  verify? : Bool = true,
) -> Player raise ReplayError {
  let root = root_for(t, scope)
  let (doc, container) = @harness.new_mount()
  // The live host stays the FALLBACK behind the recorded one, which is what
  // lets a relocated recording replay against it for the parts it never
  // captured. `Driver` installs the recorded half itself, around each settle.
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
      intents=live,
    )
    // Inside the same `try` as the construction, and not only for brevity:
    // whether the first render raises depends on the backend, and a separate
    // `try` around it is dead code on the ones where it does not.
    a.start()
    a
  } catch {
    e => raise RootUnbuildable(e.to_string())
  }
  // At the root of its own app, so the recording's addresses are already the
  // tree's: no base, and `verify` asked for explicitly because a player's
  // transactor holds nothing but the app under test.
  let driver = Driver::new(t, app.transactor, verify~)
  { app, container, fidelity, driver, }
}

///|
pub fn Player::destroy(self : Player) -> Unit {
  self.driver.stop()
}

///|
pub fn Player::done(self : Player) -> Bool {
  self.driver.done()
}

///|
/// How many events have been fed. The index of the next one.
pub fn Player::at(self : Player) -> Int {
  self.driver.at()
}

///|
/// The recording being fed.
pub fn Player::trace(self : Player) -> @trace.Trace {
  self.driver.trace()
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
  self.driver.observed()
}

///|
pub fn Player::step_event(self : Player) -> Unit raise ReplayError {
  self.driver.step_event()
}

///|
pub fn Player::step(self : Player) -> Unit raise ReplayError {
  self.driver.step()
}

///|
pub fn Player::run_to(self : Player, n : Int) -> Unit raise ReplayError {
  self.driver.run_to(n)
}

///|
pub fn Player::run(self : Player) -> Unit raise ReplayError {
  self.driver.run()
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
