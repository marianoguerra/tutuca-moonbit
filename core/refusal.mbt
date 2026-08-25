// The refusal channel: what the runtime decided and never said.
//
// `Path::update` returns the very same root for an unresolvable path, for a
// handler nothing answers, for a handler that declined, and for a handler that
// ran and changed nothing. The success path and the failure path are
// byte-identical, which is why this framework is hard to break and why a click
// that did nothing is indistinguishable from a click that was refused. The
// distinction exists at the moment it is decided; this is where it goes.
//
// A DECLINE is not a refusal. An `update` arm answering `None` and a generated
// mutator handed a value it cannot use are the intended design — the whole
// vocabulary of "nothing happened" would be noise if every one of them were
// reported. What is reported is the cases where something was ASKED FOR and
// nothing claimed it, or where a rule the author wrote said no.
//
// Off unless a host switches it on, and that is the design rather than an
// omission: a record carries the rejected STATE, so building one is not free,
// and nothing here should pay for a listener that does not exist. Every
// producer asks `refusing()` first and takes the old `warn` path when the
// answer is no, so a page that installs nothing behaves exactly as before.

///|
/// Why a dispatch produced nothing.
///
/// Each case names a producer that exists in this repo. The design this comes
/// from has a longer vocabulary — `NO_REQUEST_FN`, `DECODE_FAILED`,
/// `COERCED_TO_DEFAULT`, `OUT_OF_RANGE`, `TELEPORT_MISSING` — and none of those
/// is here, because a code nothing raises is a promise the runtime does not
/// keep: a host filtering on it would conclude the failure never happens. A new
/// case arrives with the site that raises it, in the same change.
///
/// (`@emit_mbt.Refusal` is a compile-time namesake and unrelated: that one is a
/// declaration the MoonBit backend will not compile, and it is answered to the
/// generator rather than to a running page.)
pub(all) enum RefusalCode {
  /// The path named a leaf that is not there, so there was nothing to ask.
  PathUnresolved
  /// The leaf is there and nothing answers the name: no `update` arm, no
  /// generated mutator, no bucket. Raised by `Path::update` for a dispatch and
  /// by the 404 handler a view's unanswered name resolves to.
  NoHandler
  /// A `requires` did not hold, so the transition never started.
  Precondition
  /// An `ensures` did not hold, so the transition was abandoned whole — state
  /// and effects together.
  Postcondition
  /// An `invariant` did not hold after a transition, so it was abandoned. Same
  /// abandonment as a postcondition, different owner: the rule is the
  /// component's rather than this handler's.
  Invariant
  /// An intent walked more positions than `INTENT_DEPTH` allows, so it was cut
  /// off. Not a rule anybody wrote: a route is bounded by tree depth plus
  /// scope depth, so reaching the limit means the walk is a cycle — two
  /// components forwarding to each other, which a single-component loop
  /// could not produce.
  IntentDepth
  /// `ctx.make` walked its whole route and no leg answered: nothing above
  /// published the name and nothing is registered under it.
  TypeNotFound
  /// `ctx.send_reply` with nobody waiting. A view's own `@on.*` and the host's
  /// `send_at_root` have no sender, so there is no position to answer at, and
  /// nothing is dispatched.
  NoSender
} derive(Eq, Debug)

///|
/// The screaming-snake spelling — the one an author reads in a test failure.
///
/// One vocabulary learned once: a build-time hint about a missing arm and the
/// runtime record for the same failure say the same word.
pub fn RefusalCode::word(self : RefusalCode) -> String {
  match self {
    PathUnresolved => "PATH_UNRESOLVED"
    NoHandler => "NO_HANDLER"
    Precondition => "PRECONDITION"
    Postcondition => "POSTCONDITION"
    Invariant => "INVARIANT"
    IntentDepth => "INTENT_DEPTH"
    TypeNotFound => "TYPE_NOT_FOUND"
    NoSender => "NO_SENDER"
  }
}

///|
/// One refusal: where it happened, what was asked for, which rule said no, the
/// sentence that rule produced, and the state that was rejected.
pub(all) struct Refusal {
  code : RefusalCode
  /// The handler or message name that was asked for.
  asked : String
  /// The `pred` that said no. `""` when no rule was involved — nothing claimed
  /// the name, or the path did not resolve.
  rule : String
  /// What the rule's `format` said about THIS failure, with the values that
  /// made it fail. `""` when the rule declares no `format`, and `""` for every
  /// code that is not a rule.
  ///
  /// The doc comment on a `pred` and its `format` are different jobs: the
  /// comment says what the rule is, statically; the sentence says what went
  /// wrong this time.
  sentence : String
  /// The state that was rejected — the thing you actually want to look at, and
  /// the thing nothing could reach before this existed.
  ///
  /// WHICH state depends on the moment, and the moment is the code: a
  /// `Precondition` rejected the state as it arrived, a `Postcondition` and an
  /// `Invariant` rejected the successor the body built and the framework then
  /// threw away. `Null` where the producer has no state in hand at all, which
  /// today is only the render-time 404 handler.
  state : Value
  /// Where it happened, in the runtime's own addressing. Empty is the root and
  /// is a real answer, not a missing one.
  path : Path
} derive(Eq, Debug)

///|
/// A one-line rendering, for a host that wants text rather than the record.
///
/// The sentence the author wrote comes LAST and unquoted, because it is the
/// half a reader is meant to read: everything before it is provenance.
pub fn Refusal::to_line(self : Refusal) -> String {
  let b = StringBuilder()
  b.write_string(self.code.word())
  if self.rule != "" {
    b.write_string(" \{self.rule}")
  }
  if self.asked != "" {
    b.write_string(" at `\{self.asked}`")
  }
  if self.path.steps.length() > 0 {
    b.write_string(" on \{Repr(self.path.steps)}")
  }
  if self.sentence != "" {
    b.write_string(" — \{self.sentence}")
  }
  b.to_string()
}

///|
/// Where refusals go. `None` — the default — is the channel switched off, and
/// every producer checks it before building anything.
let refusal_hook : Ref[((Refusal) -> Unit)?] = Ref(None)

///|
/// One dispatch's worth of refusal.
///
/// `held` rather than a list because at most one record escapes a dispatch: a
/// refusal is reported where the chain ENDS, and everything above it on the way
/// out is the same failure being handed back. The first one to fire is the
/// deepest one that fired, which is the one that decided.
priv struct DispatchScope {
  path : Path
  mut held : Refusal?
}

///|
let dispatch_scope : Ref[DispatchScope?] = Ref(None)

///|
/// Switch the channel on. Returns the uninstall, which puts back whatever
/// listener was there before — so a test that installs one inside another's
/// lifetime cannot silently keep it.
pub fn on_refusal(f : (Refusal) -> Unit) -> () -> Unit {
  let prev = refusal_hook.val
  refusal_hook.val = Some(f)
  fn() { refusal_hook.val = prev }
}

///|
/// Whether anything is listening.
///
/// Producers ask this before they build a record, and take the `warn` path when
/// the answer is no. It is the reason a rejected state can be carried at all:
/// nobody pays for it until somebody wants it.
pub fn refusing() -> Bool {
  refusal_hook.val is Some(_)
}

///|
/// Report a refusal. A no-op when nothing is listening.
///
/// Inside a dispatch the record is HELD rather than delivered, so the one that
/// decided is the one that escapes. A refusal raised outside any dispatch — a
/// render-time name that nothing answers — is its own chain end and goes
/// straight out.
pub fn refuse(r : Refusal) -> Unit {
  guard refusal_hook.val is Some(f) else { return }
  match dispatch_scope.val {
    Some(sc) =>
      if sc.held is None {
        // A producer deep inside a body knows the rule and the state and has no
        // idea where the dispatch landed; the scope does. A path the producer
        // stated is kept — it knew something more specific.
        sc.held = Some(
          if r.path.steps.is_empty() {
            { ..r, path: sc.path }
          } else {
            r
          },
        )
      }
    None => f(r)
  }
}

///|
/// Open a dispatch scope, answering whether THIS call opened it.
///
/// A handler that dispatches again nests, and the inner call answers `false`
/// so it cannot close the outer one's scope: one dispatch, one record, however
/// many layers it walked.
fn begin_dispatch(path : Path) -> Bool {
  guard refusal_hook.val is Some(_) else { return false }
  guard dispatch_scope.val is None else { return false }
  dispatch_scope.val = Some({ path, held: None })
  true
}

///|
/// Close the scope `opened` reported opening, delivering the record it held.
fn end_dispatch(opened : Bool) -> Unit {
  guard opened else { return }
  let held = match dispatch_scope.val {
    Some(sc) => sc.held
    None => None
  }
  dispatch_scope.val = None
  guard held is Some(r) else { return }
  guard refusal_hook.val is Some(f) else { return }
  f(r)
}
