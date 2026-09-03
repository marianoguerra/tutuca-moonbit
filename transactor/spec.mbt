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
/// A static intent handler. `@tutuca.IntentFn`, which is the same struct the
/// component layer registers — there were two, identical to the field, with an
/// adapter in `app` that unwrapped one and rewrapped it as the other.
pub using @tutuca {type IntentFn}

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
  fn intents_for(Self, leaf : @tutuca.Value, name : String) -> Array[IntentFn] = _
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
  /// The `lex` leg for a VALUE: the app-root-relative path registered under
  /// `name` in the scope of the component at `at`.
  fn lex_value(
    Self,
    root : @tutuca.Value,
    at : @tutuca.DispatchPath,
    name : String,
  ) -> @tutuca.Value? = _
  /// The `lex` leg for a TYPE: the component registered under `name` in the
  /// scope of the component at `at`.
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
impl Names with fn lex_value(_self, _root, _at, _name) {
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
/// The three words a reader sees: the bucket's, or `answer`.
declare pub fn ObserveRecord::kind_label(self : ObserveRecord) -> String

///|
/// One normalized record per handler invocation:
/// purely observational — dev tools / storybook activity logs subscribe.
/// `path` has field-resolved keys pinned against the root the handler read,
/// so `path_keys` carries concrete keys. `after` is None when the handler
/// made no change. `seq` is a per-transactor monotonic counter (a timestamp
/// stand-in — wasm-gc has no clock).
pub(all) struct ObserveRecord {
  /// Who raised it: a host call, a view's own `@on.*`, or a handler already
  /// running. What `Source` used to answer for the recorder, said once.
  origin : @tutuca.Origin
  bucket : @tutuca.HandlerBucket
  /// A message the RUNTIME wrote: the `<name>Ok`, `<name>Failed` or
  /// `<name>Unhandled` a walk produced. It is dispatched as an ordinary
  /// `Receive` and the component cannot tell it from one a parent sent, which
  /// is deliberate — the distinction lives here, where an inspector needs it,
  /// and a handler never sees it.
  is_answer : Bool
  name : String
  args : Array[@tutuca.Value]
  path : @tutuca.Path
  path_keys : Array[@tutuca.StepKey]
  target_path : @tutuca.DispatchPath
  matched : ObserveMatch
  before : @tutuca.Value?
  after : @tutuca.Value?
  seq : Int
  /// The intent walk this is one hop of, 0 for a message. Shared by every hop
  /// of one intent and by the answer it produced, which is what lets a reader
  /// group a walk instead of guessing at it from names.
  walk : Int
  /// The `seq` of the record whose handler caused this one, 0 for none.
  ///
  /// `Transaction.parent` has always existed and has always been private, so an
  /// activity log could only ever be a flat list — a cascade of twelve sends
  /// from one click read as twelve unrelated rows. This is that link, projected.
  parent_seq : Int
}

///|
/// One dispatch entering the queue, as a recorder sees it.
///
/// `at` is a `Path` and not the `DispatchPath` the transaction carries, because
/// this is the form that can be written down: a `DispatchPath` names render-time
/// producers by component id — a process-global counter nothing may persist —
/// and `Step`'s frame-only variants hold `Val` expressions and closures. The
/// transaction path is what the dispatch actually lands on, with every dynamic
/// active render frame already addresses where the data lives.
pub(all) struct Dispatched {
  /// Who raised it. `origin.is_external()` is the whole basis of replaying
  /// one: an external dispatch is an input a rerun has to feed, a `Handler`
  /// one is a consequence a rerun produces again.
  origin : @tutuca.Origin
  bucket : @tutuca.HandlerBucket
  name : String
  args : Array[@tutuca.Value]
  /// Pinned against the root as it is NOW, so a key that moves later still
  /// names the item this was addressed to.
  at : @tutuca.Path
  /// The intent walk this belongs to; 0 for a message.
  walk : Int
  /// The `seq` of the dispatch whose handler caused this one, 0 for none.
  ///
  /// Read at PUSH time, which is why it is a different number from
  /// `ObserveRecord.parent_seq` even though both come from the same counter: a
  /// parent's observation is emitted after its handler returns, and by then the
  /// child it pushed is already on the queue. Each stream is internally
  /// consistent, and a consumer reads one or the other.
  parent : Int
  /// The walk's options, and `IntentOpts::new()` for a message.
  ///
  /// On the dispatch rather than only on the walk because they decide the NAME
  /// of the answer — a sender that declared `on_ok_name` hears that arm and not
  /// `<name>Ok` — and a rerun that had to guess would deliver the reply to a
  /// handler that does not exist.
  opts : @tutuca.IntentOpts
  /// Dispatches pushed between two settles share a turn. One DOM event with two
  /// handlers is one turn, which is the grouping a rerun has to reproduce to
  /// batch the way the recording did.
  turn : Int
  seq : Int
}

///|
/// The tree → host leg: the walk is offering an intent to a handler the HOST
/// registered.
///
/// The boundary, and the reason it is its own record. Everything up to here the
/// runtime derived and a rerun derives again; what comes back does not exist
/// until the host says it. Without this an observer sees an intent climb the
/// tree, stop, and an answer appear from nowhere.
pub(all) struct Offered {
  walk : Int
  /// The `seq` of the dispatch that raised the intent.
  parent : Int
  name : String
  args : Array[@tutuca.Value]
  /// The sender's position — who is asking, which is what a host gates on.
  from : @tutuca.Path
  /// Which handler in the lexical chain. A `Pass` and the next handler after it
  /// are two offers and not one, because they are two decisions.
  nth : Int
  seq : Int
}

///|
/// The host → tree reply: how a registered handler answered.
///
/// The other thing a rerun cannot recompute, and the harder one, because the
/// handler may answer long after it was asked. A recording that keeps this can
/// replay a host that answered late, answered differently the second time, or
/// did not answer at all.
pub(all) struct Answered {
  walk : Int
  /// The `seq` of the dispatch that raised the intent.
  parent : Int
  nth : Int
  answer : @tutuca.IntentAnswer
  seq : Int
}

///|
/// The capture seam: what a recorder is handed, and when.
///
/// A trait rather than a callback for the same reason `Intents` and `Names` are
/// traits — an implementation answers several questions and wants one place to
/// keep the state behind them — but unlike those two it is swappable while the
/// app runs, because recording is something a person turns on after they have
/// seen something go wrong.
///
/// Every method is defaulted, so an implementation writes only the hooks it
/// cares about, and `NullRecorder` writes none.
pub(open) trait Recorder {
  /// Asked BEFORE any record is built.
  ///
  /// `false` — the default — costs one virtual call per push and nothing else:
  /// no path pinning, no argument copy, no record. It is the same bargain the
  /// observer list already strikes by being empty, and it is why the default
  /// recorder is free rather than cheap.
  fn recording(Self) -> Bool = _
  /// A message or an intent entered the queue.
  fn on_dispatch(Self, Dispatched) -> Unit = _
  /// An intent reached a host handler.
  fn on_offered(Self, Offered) -> Unit = _
  /// A host handler answered.
  fn on_answer(Self, Answered) -> Unit = _
  /// A handler ran, with the state it read and the state it produced. The same
  /// stream `observe` delivers; a recorder that wants it need not also
  /// subscribe.
  fn on_observed(Self, ObserveRecord) -> Unit = _
}

///|
impl Recorder with fn recording(_self) {
  false
}

///|
impl Recorder with fn on_dispatch(_self, _d) {
  ()
}

///|
impl Recorder with fn on_offered(_self, _o) {
  ()
}

///|
impl Recorder with fn on_answer(_self, _a) {
  ()
}

///|
impl Recorder with fn on_observed(_self, _r) {
  ()
}

///|
/// Records nothing, and says so. What a `Transactor` is built with, so the
/// capture machinery costs a running app nothing until somebody asks for it.
pub(all) struct NullRecorder {}

///|
pub impl Recorder for NullRecorder

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
/// drives dispatch and the walk, `target_path` stays the fixed anchor across
/// an intent's hops so an answer knows where to land, and `txn_path` is a
/// pre-pinned transaction path for one.
pub struct Transaction {
  priv transactor : Transactor
  path : @tutuca.DispatchPath
  bucket : @tutuca.HandlerBucket
  name : String
  args : Array[@tutuca.Value]
  origin : @tutuca.Origin
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
  priv sender : @tutuca.DispatchPath?
  priv sender_pinned : @tutuca.Path?
  priv mut cmpl : Completion?
  priv mut self_settled : Bool
  priv mut finished : Bool
  // observer capture (_matched/_before/_after); obs_matched None means no
  // handler resolution ran (skipSelf sends emit no record)
  priv mut obs_matched : ObserveMatch?
  priv mut obs_before : @tutuca.Value?
  priv mut obs_after : @tutuca.Value?
  /// The `seq` this transaction's record was emitted under, 0 before it ran or
  /// when nothing was watching. Read by its CHILDREN, to say what caused them.
  priv mut obs_seq : Int
  /// The `seq` this dispatch was recorded under when it entered the queue, 0
  /// when nothing was recording. Read by the transactions this one PUSHES, to
  /// say what caused them.
  priv mut push_seq : Int
  /// The walk's `raise_seq`, for a transaction the walk produced rather than a
  /// handler. Its cause, when `parent` is None and there still was one.
  priv walk_parent : Int
  /// Which walk this belongs to, 0 for none.
  ///
  /// Not read off `walk`, and the difference matters: `walk` is what a
  /// transaction ADVANCES when it finishes, so an intent's answer must not
  /// carry one or it would advance a walk that is already over. The answer
  /// still belongs to the walk, and this is how it says so.
  priv walk_id : Int
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
  /// Who answers an intent's `lex` leg.
  ///
  /// Mutable for the reason `recorder` is, and with the same warning attached:
  /// there is exactly one at a time, and a caller that swaps one in owns
  /// putting the old one back. See `set_intents`.
  priv mut intents : &Intents
  priv names : &Names
  mut root : @tutuca.Value
  priv mut queue : Array[Transaction]
  priv mut queue_head : Int
  priv change_subs : Array[(@tutuca.Value, @tutuca.Value) -> Unit]
  priv mut draining : Bool
  priv observers : Array[(ObserveRecord) -> Unit]
  priv mut obs_seq : Int
  priv drain_subs : Array[() -> Unit]
  /// The capture strategy, `NullRecorder` until somebody swaps one in.
  priv mut recorder : &Recorder
  /// Hands out `IntentWalk.id`.
  priv mut walk_seq : Int
  /// Bumped at the end of every outermost `settle`, so everything pushed
  /// between two drains shares a number. The grouping falls out of `draining`
  /// and nothing outside this package has to know it exists.
  priv mut turn : Int
}

///|
declare pub fn Transactor::new(
  root : @tutuca.Value,
  intents? : &Intents,
  names? : &Names,
) -> Transactor

///|
/// Install a capture strategy, replacing whatever was there.
///
/// Swappable while the app runs, which is the point: recording is something a
/// person turns on after they have seen something go wrong, and turns off again
/// by installing `NullRecorder::{}`. Unlike `observe`, there is exactly one at a
/// time — a recorder OWNS the recording, and two of them would each hold half
/// of one.
declare pub fn Transactor::set_recorder(
  self : Transactor,
  r : &Recorder,
) -> Unit

///|
/// The installed strategy.
declare pub fn Transactor::recorder(self : Transactor) -> &Recorder

///|
/// Install who answers intents, replacing whoever did.
///
/// The pair `set_recorder` has had all along, and it exists for one caller: a
/// REPLAY, which must answer an intent with what the host said last time
/// rather than what it would say now. `trace/replay`'s `RecordedHost` is that
/// answerer, and a recording of a component that asked the time or the network
/// is worth nothing without it.
///
/// Swap it for as short a time as possible — around the push and the settle
/// that feed one turn, and back again. A recorded host is a finite supply of
/// answers handed out in walk order, so leaving one installed while anything
/// else raises an intent spends the recording's answers on questions it was
/// not answering, and the divergence that follows points at the wrong place.
declare pub fn Transactor::set_intents(self : Transactor, i : &Intents) -> Unit

///|
/// Who currently answers intents, so a caller that swapped can put it back
/// rather than rebuild one and hope it matches.
declare pub fn Transactor::intents(self : Transactor) -> &Intents

///|
/// Install a whole tree, telling the subscribers.
///
/// `root` is a public mutable field and assigning it directly is the trap this
/// closes: the assignment inside `transact` is followed by the `on_change`
/// notification, and an outside assignment is not, so the App never re-renders
/// and the mismatch surfaces later as a view that will not update. Nothing in
/// the repo installed a tree before — replaying a recording is the first thing
/// that needs to, and a state editor would be the second.
///
/// Notifies only when the tree actually moved, on the same physical-identity
/// test every other change subscriber is woken by.
declare pub fn Transactor::reset_root(
  self : Transactor,
  root : @tutuca.Value,
) -> Unit

///|
/// Apply a public property setter at an addressed component and install its
/// successor synchronously.
///
/// The setter itself is a pure copy-on-write transition. Resolving the path,
/// rebuilding its parents, and swapping the root happen as one call, so a
/// caller never observes the child successor detached from its parent tree.
/// Missing paths/properties and refused writes leave the root untouched and
/// are distinguished by `Outcome`.
declare pub fn Transactor::set_property(
  self : Transactor,
  at : @tutuca.DispatchPath,
  name : String,
  value : @tutuca.Value,
) -> @tutuca.Outcome

///|
/// Apply a private-or-public property setter from the component's own view.
/// It has the same atomic path rebuilding as `set_property`; only visibility
/// differs.
declare pub fn Transactor::set_member(
  self : Transactor,
  at : @tutuca.DispatchPath,
  name : String,
  value : @tutuca.Value,
) -> @tutuca.Outcome

///|
/// Apply a source-level member operation from the component's own view and
/// install its successor atomically. Generated mutator names are an
/// implementation detail below this API.
declare pub fn Transactor::mutate_member(
  self : Transactor,
  at : @tutuca.DispatchPath,
  name : String,
  operation : String,
  args : Array[@tutuca.Value],
) -> @tutuca.Outcome

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
  sender? : @tutuca.DispatchPath,
  origin? : @tutuca.Origin,
) -> Transaction

///|
/// One intent's whole walk, as state shared across its hops.
///
/// A flag would be enough to say "keep going up"; it cannot say WHERE the walk
/// is — which leg, how far along it, and whether the one answer the walk is
/// allowed has already been given. A route is a list and a position, so this is
/// a list and a position.
pub struct IntentWalk {
  /// The `seq` the walk's own raise was recorded under, 0 when nothing was
  /// recording. Every hop, every offer, every answer and the reply message
  /// point back at it — a walk is not a transaction, so this is the only thing
  /// its consequences have to name as their cause.
  mut raise_seq : Int
  /// This walk's identity, unique within the transactor.
  ///
  /// A walk had none, so an answer could not name the intent it answered: an
  /// observer saw an intent climb and an answer arrive and had to infer the
  /// pairing from the name. A recorded trace cannot infer it at all, because
  /// two walks of the same intent may be in flight at once.
  id : Int
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
  sender : @tutuca.DispatchPath
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
