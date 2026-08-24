// Spec for tutuca's transactor: the four
// dispatch channels (input / send-receive / bubble / request-response) over
// the path package's leaf-handler machinery, plus the per-transaction
// Completion scope (structured-concurrency counters).
//
// Differences from upstream, by design:
// - No async runtime (moonbitlang/async does not support wasm-gc, the
//   module's preferred target): request handlers are CALLBACK-style — they
//   receive a `respond` continuation they may call synchronously or store
//   and call later. `respond` enqueues the ResponseEvent and drains the
//   queue, so there is no event loop to await; `settle()` only drains
//   already-queued transactions.
// - Completion exposes callback subscription (on_settled /
//   on_subtree_settled) instead of promises.
// - Handler resolution lives on the leaf (Value::handler, which asks the
//   instance through Obj); only request handlers use an external registry
//   (upstream they resolve through the scope chain, not the component).
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
/// argument list, and it may answer `Pass`. `Pass` DECLINES: a handler with
/// nothing to say hands the intent to the next one rather than inventing an
/// error to discharge an obligation to respond.
pub(all) struct IntentHandler(
  (@tutuca.IntentCall, (@tutuca.IntentAnswer) -> Unit) -> Unit
)

///|
/// The lexical leg's registry.
///
/// It answers with the WHOLE chain rather than the first match, innermost
/// scope first, and that shape is the "`lex` walks" decision from
/// the intent walk: a declining handler hands the intent to its
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
/// The name-resolution seam: the two environments a route walks, for the
/// questions that are not "who handles this intent".
///
/// It is a seam for the same reason `Intents` is one. The `dyn` leg is the
/// RENDER ancestry, which only the renderer can rebuild, and the `lex` leg is
/// the registration scope, which only the component layer holds — and this
/// package deliberately imports neither. The app wires an implementation in,
/// the way it wires `Intents`.
///
/// A type is answered as a component ID rather than as a component, because a
/// component is not something `core` can name. `build` turns one back into an
/// instance.
pub(open) trait Names {
  /// The `dyn` leg: the nearest value published under `name` in the render
  /// ancestry at `at`, rebuilt from `root`.
  fn dyn_value(
    Self,
    root : @tutuca.Value,
    at : @tutuca.DispatchPath,
    name : String,
  ) -> @tutuca.Value? = _
  /// The `dyn` leg for a TYPE: the component an ancestor published under
  /// `name` with `provide {Name: "self"}`.
  fn dyn_type(
    Self,
    root : @tutuca.Value,
    at : @tutuca.DispatchPath,
    name : String,
  ) -> Int? = _
  /// The `lex` leg: what `name` means in the registration scope of the
  /// component at `at`.
  ///
  /// A scope chain holds components, so a VALUE never answers here. That is
  /// not a hole: it is why ONE default route serves both a value lookup and a
  /// type lookup — the leg that cannot answer simply misses.
  fn lex_type(
    Self,
    root : @tutuca.Value,
    at : @tutuca.DispatchPath,
    name : String,
  ) -> Int? = _
  /// Build an instance of the component `id` names.
  fn build(Self, id : Int, args : Map[String, @tutuca.Value]) -> @tutuca.Value? = _
}

///|
impl Names with fn dyn_value(_self, _root, _at, _name) {
  None
}

///|
impl Names with fn dyn_type(_self, _root, _at, _name) {
  None
}

///|
impl Names with fn lex_type(_self, _root, _at, _name) {
  None
}

///|
impl Names with fn build(_self, _id, _args) {
  None
}

///|
/// Resolves nothing. A transactor driven with no renderer and no registry —
/// every `Path::update` test — answers the way a route that misses answers.
pub(all) struct NoNames {}

///|
pub impl Names for NoNames

///|
/// How many positions one intent may walk before the runtime cuts it off
///.
///
/// A cycle breaker, not a tuning knob. A legitimate route is bounded by tree
/// depth plus scope depth and nothing in the corpus is near this; reaching it
/// means two components are forwarding to each other, a loop only a multi-hop
/// walk can build. It is a different number from `settle`'s `max_turns`, which
/// bounds the whole QUEUE rather than one chain, and it does not replace it.
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
/// What an observer record describes, as an enum.
pub(all) enum ObserveKind {
  Receive
  /// One hop of an intent's walk. Travelling up the tree, asking a registered
  /// handler and carrying an answer back are all the same event here, because
  /// they are all one hop of one walk.
  Intent
  /// A message the RUNTIME wrote: the `<name>Ok`, `<name>Error` or
  /// `<name>Unhandled` a walk produced. It is an ordinary message and the
  /// component cannot tell it from one a parent sent, which is deliberate: the
  /// distinction lives here, where an inspector needs it, and a handler never
  /// sees it.
  Answer
} derive(Debug, Eq)

///|
/// How the handler was resolved: an exact bucket entry, or
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
/// The kind as the wire/display word.
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
/// One normalized record per handler invocation:
/// purely observational — dev tools / storybook activity logs subscribe.
/// `path` has field-resolved keys pinned against the root the handler read,
/// so `path_keys` carries concrete keys. `after` is None when the handler
/// made no change. `seq` is a per-transactor monotonic counter (a timestamp
/// stand-in — wasm-gc has no clock).
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
  /// answer per intent rather than per hop — a walk has many hops, and only
  /// the first reply counts.
  priv walk : IntentWalk?
  /// Whether the runtime wrote this message: the `<name>Ok` / `<name>Error` /
  /// `<name>Unhandled` a walk produced.
  ///
  /// Read by the OBSERVER, and by nothing a component can reach: an answer is
  /// an ordinary message and a handler cannot tell it from one a parent sent.
  /// An inspector is outside that claim and needs to label the two.
  is_answer : Bool
  /// Where this message came FROM, and nothing else's business: `ctx.send_reply`
  /// is the only reader.
  ///
  /// `None` when nobody is waiting — a view's own `@on.*`, the host's
  /// `send_at_root`, an intent's answer — and that is what `NO_SENDER` refuses
  /// on. The pinned twin is resolved at PUSH time for the same reason an
  /// intent's answer path is: a reply must reach the sender that asked, even if
  /// a key moved while the message was in flight.
  priv origin : @tutuca.DispatchPath?
  priv origin_pinned : @tutuca.Path?
  priv mut cmpl : Completion?
  priv mut self_settled : Bool
  priv mut finished : Bool
  // observer capture (_matched/_before/_after); obs_matched None means no
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
  priv names : &Names
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
  names? : &Names,
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
/// one transaction (the drained-cascade hook): subscribers that
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
  origin? : @tutuca.DispatchPath,
) -> Transaction

///|
/// One intent's whole walk, as state shared across its hops.
///
/// A flag would be enough to say "keep going up"; it cannot say WHERE the walk
/// is — which leg, how far along it, and whether the one answer the walk is
/// allowed has already been given. A route is a list and a position, so this is
/// a list and a position.
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
  /// The one-shot: an intent gets one answer. Per INTENT and shared across
  /// every hop of the walk, not per hop — otherwise each handler along the
  /// route could answer once and the sender would hear several.
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
/// Whether transactions remain queued: the pending
/// check a time-slicing backend loops on alongside bounded settle(max_turns).
declare pub fn Transactor::has_pending(self : Transactor) -> Bool
