// Running a recording back: the types, plus the `declare` stubs. The
// implementation lives in player.mbt and answers.mbt.
//
// READONLY by convention: concrete public data types plus `declare` stubs for
// every function. This file and the `*_test.mbt` suites define the contract.

///|
/// How a rerun treats the recording.
///
/// One mode, and the reason there is only one is worth writing down, because
/// the obvious second one cannot exist.
///
/// A rerun runs the REAL APP: it feeds the inputs and the app derives the rest,
/// which is what makes a recording a regression test — a divergence is the
/// behaviour having moved. The tempting alternative is to feed the derived
/// events too, so a rerun reproduces the recording exactly rather than
/// re-earning it. That does not work here and cannot: the app's handlers still
/// run, so every fed consequence happens twice. Suppressing them would mean a
/// runtime seam for "dispatch nothing" — and a rerun with the app's own effects
/// switched off is not running the app, so it would prove nothing that reading
/// the file does not already prove.
///
/// The limit that mode would have covered is real and is left standing: an
/// intent raised inside a `*dyn` render target walks the RENDER ancestry, and a
/// stored address is the transaction path, so a reconstructed walk follows the
/// data ancestry instead. For a MESSAGE this is lossless —
/// `to_transaction_path` has already teleported the marker to where the data
/// lives, which is what the message mutates. For such an intent it is not, and
/// what happens then is the good failure: `verify` reports a divergence rather
/// than a rerun that quietly did something else.
pub(all) enum Fidelity {
  Live
} derive(Eq, Debug)

///|
/// A mounted recording, positioned somewhere in its own event list.
pub struct Player {
  /// The app the events are fed to. Public because everything a caller wants to
  /// read afterwards — the state, the rendered DOM, the render count — already
  /// has a name on `App` or on a `Harness` over it, and wrapping each of them
  /// again would be a second vocabulary for the same questions.
  app : @app.App[@memdom.MemNode]
  container : @memdom.MemNode
  trace : @trace.Trace
  fidelity : Fidelity
  /// How many events have been fed. The index of the next one.
  mut at : Int
  // private fields
  /// The rerun, recorded — so it can be compared with the recording being fed
  /// as like with like. `None` when `verify` is off.
  priv mut rerun : @trace.TraceRecorder?
  /// How many dispatches have already been held against the recording, so a
  /// step re-checks only what it added.
  priv mut checked : Int
  priv mut watching : (() -> Unit)?
}

///|
/// Why a rerun stopped.
pub suberror ReplayError {
  /// The app did something other than what was recorded.
  ///
  /// The finding, not the failure: this is what a recording kept as a
  /// regression test exists to produce. Both events are carried because the
  /// difference between them is the whole report.
  ///
  /// The one case where this fires and the app is fine: an intent that bubbles
  /// through a `*dyn` render target. A stored address is the TRANSACTION path,
  /// which teleports a dynamic marker to where the data lives — right for a
  /// message, and not the route the walk actually took. `Fidelity::Scripted`
  /// is for that case.
  Diverged(at~ : Int, want~ : @trace.Event, got~ : @trace.Event)
  /// The root component's shape moved since the recording was taken.
  ///
  /// Reported as itself rather than as the pile of decode failures it would
  /// otherwise become: one cause, one sentence.
  ShapeChanged(component~ : String, want~ : String, got~ : String)
  /// The snapshot names a component the scope cannot build — a module that was
  /// not registered, or a component that was renamed — or the mount itself
  /// failed. One case for both, because the caller's next move is the same:
  /// the scope is not the one this was recorded against.
  RootUnbuildable(String)
  /// The trace's own version is not one this build knows.
  UnknownVersion(got~ : Int)
}

///|
declare pub fn ReplayError::message(self : ReplayError) -> String

///|
/// The recorded answers, keyed the way a walk asks for them.
///
/// Not `Map[Int, _]` on the walk id alone: ids are handed out in order, so they
/// line up only while the rerun is faithful, and the moment it is not, matching
/// on the id alone would hand a walk somebody else's answer and hide the
/// divergence it should have reported. The NAME is checked too.
pub struct Answers {
  priv by_walk : Map[Int, Array[(String, Int, @tutuca.IntentAnswer)]]
  priv mut next_walk : Int
}

///|
/// Every recorded answer, in walk order.
declare pub fn Answers::of_trace(t : @trace.Trace) -> Answers

///|
/// The answers a walk of `name` should hear, in order, or `[]` when the
/// recording has none — which is what makes an unanswered intent fall through
/// to whatever the app itself registered.
declare pub fn Answers::take(
  self : Answers,
  name : String,
) -> Array[@tutuca.IntentAnswer]

///|
/// The `Intents` a rerun installs: the host, replaced by what it said last
/// time.
///
/// The same idea as a scene's `intents:` fixture, and different in the one way
/// that matters here: per-OCCURRENCE rather than per-name, so a recording of a
/// host that declined the first time and answered the second replays as that
/// and not as two of whichever came first.
pub struct RecordedHost {
  priv answers : Answers
  priv fallback : &@transactor.Intents?
}

///|
declare pub fn RecordedHost::new(
  answers : Answers,
  fallback? : &@transactor.Intents,
) -> RecordedHost

///|
pub impl @transactor.Intents for RecordedHost

// --- mounting and driving -----------------------------------------------------

///|
/// Mount a recording's initial state and prepare to feed it.
///
/// Through `App::new` with the snapshot rebuilt, and NOT through
/// `App::from_module`: a rebased or relocated recording starts from a state no
/// example names, and being able to mount those is the whole reason the format
/// stores a snapshot rather than a constructor call.
declare pub fn mount(
  t : @trace.Trace,
  scope : @component.ComponentStack,
  fidelity? : Fidelity,
  verify? : Bool,
) -> Player raise ReplayError

///|
/// Feed one whole turn — every event the recording drained together.
///
/// The natural step, because a turn is what one drain consumed: stepping by
/// EVENT can leave the app mid-cascade, in a state it was never in.
declare pub fn Player::step(self : Player) -> Unit raise ReplayError

///|
/// Feed one event and settle. For a viewer's step slider, where landing
/// mid-cascade is the point.
declare pub fn Player::step_event(self : Player) -> Unit raise ReplayError

///|
/// Feed events until `n` of them have been consumed.
declare pub fn Player::run_to(self : Player, n : Int) -> Unit raise ReplayError

///|
/// Feed the rest.
declare pub fn Player::run(self : Player) -> Unit raise ReplayError

///|
/// Whether there is anything left to feed.
declare pub fn Player::done(self : Player) -> Bool

///|
/// The settled state, as a tagged snapshot — what `Trace::rebase` takes.
declare pub fn Player::snapshot(self : Player) -> Json

///|
/// The harness verbs over the same app: `text`, `html`, `render_count`, and the
/// rest. A rerun's DOM is read the way any other test reads one.
declare pub fn Player::harness(self : Player) -> @harness.MemHarness

///|
/// The rendered page, without the renderer's own bookkeeping.
///
/// What to hold a rerun's DOM against, and the raw `html()` is not it: a
/// component id comes from a process-global counter, so the same app mounted
/// twice renders the same page with a different number in every `data-cid`.
/// A comparison on the raw form fails on a rerun that did everything right.
declare pub fn Player::html(self : Player) -> String

///|
/// What the app did while being fed, in the recording's own vocabulary.
///
/// The other half of a divergence report: `Diverged` says where they parted,
/// and this is the whole of what actually happened, for a reader who wants to
/// see the rest of it.
declare pub fn Player::observed(self : Player) -> Array[@trace.Event]

///|
/// Stop watching. Releases the transactor subscription the player installed;
/// a player that is dropped without this leaves the app recording into it.
declare pub fn Player::destroy(self : Player) -> Unit

///|
/// Mount, feed everything, and answer the state it reached.
///
/// The one-liner a regression test is written as, and the one a `rebase`
/// calls: the interesting part of using a recording is usually not the
/// stepping.
declare pub fn replay(
  t : @trace.Trace,
  scope : @component.ComponentStack,
  fidelity? : Fidelity,
  verify? : Bool,
) -> Json raise ReplayError
