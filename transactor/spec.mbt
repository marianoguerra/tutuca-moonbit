// Spec for the port of tutuca's transactor (src/transactor.js): the four
// dispatch channels (input / send-receive / bubble / request-response) over
// the path package's leaf-handler machinery, plus the per-transaction
// Completion scope (structured-concurrency counters).
//
// Differences from JS, by design:
// - No async runtime (moonbitlang/async does not support wasm-gc, the
//   module's preferred target): request handlers are CALLBACK-style — they
//   receive a `respond` continuation they may call synchronously or store
//   and call later. `respond` enqueues the ResponseEvent and drains the
//   queue, so there is no event loop to await; `settle()` only drains
//   already-queued transactions.
// - Completion exposes callback subscription (on_settled /
//   on_subtree_settled) instead of promises.
// - Handler resolution lives on the leaf (Value::handler, which asks the
//   instance through Obj); only request handlers use an external registry (in
//   JS they resolve through the scope chain, not the component).
//
// walk_path (over Path::resolve_chain, leaf->root) and the ctx.at PathChanges
// builder have shipped — walk_path is implemented on EventContext
// (transactor.mbt), ctx.at / PathChanges live in the root package
// (path_changes.mbt) since they need only Ctx::path + send_at_path.
// (Observers and DOM InputEvent lookups also shipped: see ObserveRecord below
// and render/dom_event.mbt.)

///|
/// A static intent handler.
///
/// It receives an `IntentCall` — which carries `from`, the sender's position,
/// so a host can decide whether this sender may ask — rather than a bare
/// argument list, and it may answer `Pass`. v1's `RequestHandler`, which this
/// replaced, could do neither: a request handler MUST respond, so one with
/// nothing to say had to invent an error, while a declining intent handler
/// simply hands the intent to the next one.
pub(all) struct IntentHandler(
  (@tutuca.IntentCall, (@tutuca.IntentAnswer) -> Unit) -> Unit
)

///|
/// The lexical leg's registry.
///
/// It answers with the WHOLE chain rather than the first match, innermost
/// scope first, and that shape is the "`lex` walks" decision from
/// `totuka-v2.md` section 17: a declining handler hands the intent to its
/// parent scope, so the walk needs every candidate and not the first one. The
/// transactor asks each in turn INSIDE the transaction that is already
/// running, so a `Pass` costs a call rather than a queue step — which is why
/// the chain comes back as a list and not as a "next" continuation.
pub(open) trait Intents {
  fn intents_for(Self, leaf : @tutuca.Value, name : String) -> Array[
    IntentHandler,
  ] = _
}

///|
impl Intents with fn intents_for(_self, _leaf, _name) {
  []
}

///|
pub(all) struct NoIntents {}

///|
pub impl Intents for NoIntents

///|
/// How many positions one intent may walk before the runtime cuts it off
/// (`totuka-v2.md` section 17).
///
/// A cycle breaker, not a tuning knob. A legitimate route is bounded by tree
/// depth plus scope depth and nothing in the corpus is near this; reaching it
/// means two components are forwarding to each other, which v1's
/// single-component loop could not produce. It is a different number from
/// `settle`'s `max_turns`, which bounds the whole QUEUE rather than one chain,
/// and it does not replace it.
pub const INTENT_DEPTH : Int = 64

///|
/// Per-transaction completion scope (WaitGroup style): a counter of
/// outstanding units — one self-unit (the transaction's own processing) plus
/// one per derived child or in-flight request. Self settles when the handler
/// runs; the subtree settles when the counter reaches zero.
pub struct Completion {
  mut pending : Int
  mut self_settled : Bool
  mut subtree_settled : Bool
  mut self_released : Bool
  priv self_subs : Array[() -> Unit]
  priv subtree_subs : Array[() -> Unit]
}

///|
declare fn Completion::new() -> Completion

///|
/// Run `cb` once this transaction's own handler has run (immediately if it
/// already has).
declare pub fn Completion::on_settled(
  self : Completion,
  cb : () -> Unit,
) -> Unit

///|
/// Run `cb` once this transaction AND all transitively-derived work (sends,
/// intent walks and their answers) have settled.
declare pub fn Completion::on_subtree_settled(
  self : Completion,
  cb : () -> Unit,
) -> Unit

///|
/// Register an outstanding unit; returns a one-shot release.
declare fn Completion::track(self : Completion) -> () -> Unit

///|
declare fn Completion::mark_self_settled(self : Completion) -> Unit

///|
declare fn Completion::release_self(self : Completion) -> Unit

///|
/// What an observer record describes (JS observeKind strings as an enum).
pub(all) enum ObserveKind {
  Receive
  /// One hop of an intent's walk — the kind v1's `Bubble`, `Response` and
  /// `Request` all collapsed into once the walk owned all three.
  Intent
  /// A message the RUNTIME wrote: the `<name>Ok`, `<name>Error` or
  /// `<name>Unhandled` a walk produced. It is an ordinary message and the
  /// component cannot tell it from one a parent sent — which is the design's
  /// claim — so the distinction lives here, where an inspector needs it and a
  /// handler never sees it.
  Answer
} derive(Debug, Eq)

///|
/// How the handler was resolved (JS _matched): an exact bucket entry, or
/// nothing (silent no-op).
///
/// There was a third answer, `Unknown`, for the `"$unknown"` catch-all a
/// second lookup probed for on every miss. Dispatch does one lookup now, so a
/// miss is a miss and there is no third thing to report.
pub(all) enum ObserveMatch {
  Exact
  NoHandler
} derive(Debug, Eq)

///|
/// The kind as the wire/display word (the JS observeKind string).
declare pub fn ObserveKind::label(self : ObserveKind) -> String

///|
/// The kind a dispatch through `bucket` is observed as. Every bucket has one;
/// `Request` is the kind with no bucket behind it.
declare pub fn ObserveKind::of_bucket(
  bucket : @tutuca.HandlerBucket,
) -> ObserveKind

///|
/// How the handler was resolved, as the wire/display word.
declare pub fn ObserveMatch::label(self : ObserveMatch) -> String

///|
/// One record as JSON — a dispatch a devtool can show, or a host can post
/// across a boundary.
///
/// This could not be written until an instance had a JSON form: `before` and
/// `after` are the leaf VALUES a handler read and returned, and a component
/// instance flattened to `null`, which is the whole of what a transaction is
/// about. `@tutuca.Value::to_json` projects a described instance now, so the
/// record carries the state change rather than a pair of nulls.
declare pub fn ObserveRecord::to_json(self : ObserveRecord) -> Json

///|
/// One normalized record per handler invocation (JS Transactor.observe):
/// purely observational — dev tools / storybook activity logs subscribe.
/// `path` has field-resolved keys pinned against the root the handler read,
/// so `path_keys` carries concrete keys. `after` is None when the handler
/// made no change. `seq` is a per-transactor monotonic counter (the JS
/// timestamp stand-in — wasm-gc has no clock).
pub(all) struct ObserveRecord {
  kind : ObserveKind
  name : String
  args : Array[@tutuca.Value]
  path : @tutuca.Path
  path_keys : Array[@tutuca.StepKey]
  target_path : @tutuca.DispatchPath
  matched : ObserveMatch
  before : @tutuca.Value?
  after : @tutuca.Value?
  seq : Int
}

///|
/// Outcome of one bounded settle pass. `pending` tells the caller whether it
/// must schedule another pass; a non-positive budget processes nothing and
/// reports the queue unchanged.
pub(all) struct SettleResult {
  processed : Int
  pending : Bool
} derive(Eq, Debug)

///|
/// One queued dispatch, the buckets collapsed onto `HandlerBucket`: `path`
/// drives dispatch and the walk, `target_path` stays the fixed origin across
/// an intent's hops so an answer knows where to land, and `txn_path` is a
/// pre-pinned transaction path for one.
pub struct Transaction {
  priv transactor : Transactor
  path : @tutuca.DispatchPath
  bucket : @tutuca.HandlerBucket
  name : String
  args : Array[@tutuca.Value]
  target_path : @tutuca.DispatchPath
  txn_path : @tutuca.Path?
  parent : Transaction?
  /// The walk this transaction is one hop of, shared BY REFERENCE with every
  /// other hop of the same intent. That sharing is what makes the one-shot
  /// answer per intent rather than per hop, which is the thing v1's per-request
  /// `responded` flag could not express because v1 had one hop.
  priv walk : IntentWalk?
  /// Whether the runtime wrote this message: the `<name>Ok` / `<name>Error` /
  /// `<name>Unhandled` a walk produced. Read by the observer, and by
  /// `Ctx::is_answer` for the one caller that bridges to a foreign contract.
  is_answer : Bool
  priv mut cmpl : Completion?
  priv mut self_settled : Bool
  priv mut finished : Bool
  // observer capture (JS _matched/_before/_after); obs_matched None means no
  // handler resolution ran (skipSelf sends emit no record)
  priv mut obs_matched : ObserveMatch?
  priv mut obs_before : @tutuca.Value?
  priv mut obs_after : @tutuca.Value?
}

///|
/// Lazily-created completion scope (a transaction nobody awaits never
/// allocates one). The transaction retains its lifecycle flags, so a completion
/// first requested after the transaction ran is returned already settled.
declare pub fn Transaction::completion(self : Transaction) -> Completion

///|
/// The dispatcher: a queue of transactions over a mutable root Value.
/// Handlers resolve on the leaf (Value::handler); an intent's `lex` leg
/// resolves through the external registry.
pub struct Transactor {
  priv intents : &Intents
  mut root : @tutuca.Value
  priv mut queue : Array[Transaction]
  priv mut queue_head : Int
  priv change_subs : Array[(@tutuca.Value, @tutuca.Value) -> Unit]
  priv mut draining : Bool
  priv observers : Array[(ObserveRecord) -> Unit]
  priv mut obs_seq : Int
  priv drain_subs : Array[() -> Unit]
}

///|
declare pub fn Transactor::new(
  root : @tutuca.Value,
  intents? : &Intents,
) -> Transactor

///|
/// Subscribe to a normalized record for every handler invocation — a receive,
/// one hop of an intent's walk, or an answer. Returns an unsubscribe function.
/// Purely observational; empty by default (zero overhead).
declare pub fn Transactor::observe(
  self : Transactor,
  cb : (ObserveRecord) -> Unit,
) -> () -> Unit

///|
/// Run `cb` at the end of every OUTERMOST settle() that processed at least
/// one transaction (the JS setTimeout-batch analogue): subscribers that
/// react once per drained cascade — e.g. the App re-render — instead of once
/// per root swap.
declare pub fn Transactor::on_drained(
  self : Transactor,
  cb : () -> Unit,
) -> Unit

///|
/// Subscribe to root swaps: cb(new_root, old_root).
declare pub fn Transactor::on_change(
  self : Transactor,
  cb : (@tutuca.Value, @tutuca.Value) -> Unit,
) -> Unit

///|
/// Drop every subscription: change, drained, and observers. on_change and
/// on_drained hand back no unsubscribe handle (unlike observe), so this is how
/// a subscriber that owns the transactor lets go of it.
///
/// The App subscribes with closures that capture the App, which makes
/// App -> transactor -> closure -> App a reference cycle. A host that mounts
/// and discards apps must break it; see App::destroy.
declare pub fn Transactor::clear_subscriptions(self : Transactor) -> Unit

///|
/// Queue a targeted send (bucket Receive). Returns the transaction (subscribe
/// to its completion, then settle()).
declare pub fn Transactor::push_send(
  self : Transactor,
  path : @tutuca.DispatchPath,
  name : String,
  args : Array[@tutuca.Value],
  parent? : Transaction,
) -> Transaction

///|
/// One intent's whole walk, as state shared across its hops.
///
/// v1's `Transaction.bubbles : Bool` is the field this replaces, and the two
/// answer different questions. A boolean can say "keep going up"; it cannot say
/// WHERE the walk is — which leg, how far along it, and whether the one answer
/// the walk is allowed has already been given. A route is a list and a
/// position, so this is a list and a position.
pub struct IntentWalk {
  name : String
  /// The legs, in the order written. `[Dyn, Lex]` when nothing said otherwise.
  mut route : Array[@tutuca.Leg]
  /// Which leg is being walked.
  mut leg : Int
  /// Where the NEXT `dyn` hop runs. Starts at the sender's own path and is
  /// popped before each hop, which is how "the `dyn` leg starts at the parent"
  /// is spelled: a component never re-enters its own handler.
  mut dyn_at : @tutuca.DispatchPath
  /// The arguments the next hop carries. A `forward` in a body amends this.
  mut args : Array[@tutuca.Value]
  opts : @tutuca.IntentOpts
  /// The sender's position — where an answer goes. It does not move when a
  /// handler forwards, which is the whole of what makes `forward` different
  /// from dispatching the intent again.
  origin : @tutuca.DispatchPath
  /// The unit held on the sender for the length of the walk, released once —
  /// onto the answer's subtree if there is an answer, and directly if there is
  /// not. Without it a sender that waits for settlement would see the walk
  /// finish and the answer still in flight.
  priv mut release : (() -> Unit)?
  /// The one-shot. Per INTENT and across hops, which is the difference from
  /// v1's per-request `responded`.
  mut answered : Bool
  /// Ended by `stop`: served, and no answer.
  mut stopped : Bool
  /// Positions visited, against `INTENT_DEPTH`.
  mut hops : Int
}

///|
/// Dispatch an intent along `opts.route`, from `path` — the SENDER's own
/// position, which the walk pops before its first `dyn` hop.
declare pub fn Transactor::push_intent(
  self : Transactor,
  path : @tutuca.DispatchPath,
  name : String,
  args : Array[@tutuca.Value],
  opts? : @tutuca.IntentOpts,
  parent? : Transaction,
) -> IntentWalk

///|
/// Process at most `max_turns` queued transactions and report whether more
/// remain. Re-entrant calls (a respond firing mid-drain) process nothing — the
/// outer loop picks the new work up. A non-positive budget is also a no-op,
/// making invalid batching explicit without trapping a caller in a loop.
declare pub fn Transactor::settle(
  self : Transactor,
  max_turns? : Int,
) -> SettleResult

///|
/// Whether transactions remain queued (JS hasPendingTransactions): the pending
/// check a time-slicing backend loops on alongside bounded settle(max_turns).
declare pub fn Transactor::has_pending(self : Transactor) -> Bool
