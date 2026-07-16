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
// - Handler resolution lives on the leaf (PathNode::handler); only request
//   handlers use an external registry (in JS they resolve through the scope
//   chain, not the component).
//
// walk_path (over Path::resolve_chain, leaf->root) and the ctx.at PathChanges
// builder have shipped — walk_path is implemented on EventContext
// (transactor.mbt), ctx.at / PathChanges live in the root package
// (path_changes.mbt) since they need only Ctx::path + send_at_path.
// (Observers and DOM InputEvent lookups also shipped: see ObserveRecord below
// and render/dom_event.mbt.)

///|
/// A request handler: receives its args and a one-shot `respond`
/// continuation (the promise-less port of an async request). Calling respond
/// enqueues the response transaction and drains the queue; calling it twice
/// is ignored. A handler that never responds leaves its parent's subtree
/// permanently unsettled (the JS analogue is a promise that never resolves).
pub(all) struct RequestHandler(
  (Array[@tutuca.Value], (Result[@tutuca.Value, @tutuca.Value]) -> Unit) -> Unit
)

///|
/// External request registry (JS comps.getRequestFor). Defaults to None:
/// an unknown request responds with an error (JS mkReq404).
pub(open) trait Requests {
  fn request_for(Self, leaf : &@tutuca.PathNode, name : String) -> RequestHandler? = _
}

///|
impl Requests with fn request_for(_self, _leaf, _name) {
  None
}

///|
pub(all) struct NoRequests {}

///|
pub impl Requests for NoRequests

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
declare pub fn Completion::new() -> Completion

///|
/// Run `cb` once this transaction's own handler has run (immediately if it
/// already has).
declare pub fn Completion::on_settled(
  self : Completion,
  cb : () -> Unit,
) -> Unit

///|
/// Run `cb` once this transaction AND all transitively-derived work (sends,
/// bubbles, requests and their responses) have settled.
declare pub fn Completion::on_subtree_settled(
  self : Completion,
  cb : () -> Unit,
) -> Unit

///|
/// Register an outstanding unit; returns a one-shot release.
declare pub fn Completion::track(self : Completion) -> () -> Unit

///|
declare pub fn Completion::mark_self_settled(self : Completion) -> Unit

///|
declare pub fn Completion::ensure_self_settled(self : Completion) -> Unit

///|
declare pub fn Completion::release_self(self : Completion) -> Unit

///|
/// What an observer record describes (JS observeKind strings as an enum).
pub(all) enum ObserveKind {
  Receive
  Input
  Bubble
  Response
  Request
} derive(Debug, Eq)

///|
/// How the handler was resolved (JS _matched): an exact bucket entry, the
/// $unknown fallback, or nothing (silent no-op).
pub(all) enum ObserveMatch {
  Exact
  Unknown
  NoHandler
} derive(Debug, Eq)

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
/// One queued dispatch (JS Transaction subclasses collapsed onto
/// HandlerBucket): `path` drives dispatch and bubbling, `target_path` stays
/// the fixed origin across bubble hops, `txn_path` is a pre-pinned
/// transaction path (responses), `bubbles`/`skip_self` are the send options.
pub struct Transaction {
  priv transactor : Transactor
  path : @tutuca.DispatchPath
  bucket : @tutuca.HandlerBucket
  name : String
  args : Array[@tutuca.Value]
  target_path : @tutuca.DispatchPath
  mut bubbles : Bool
  skip_self : Bool
  txn_path : @tutuca.Path?
  parent : Transaction?
  priv mut cmpl : Completion?
  // observer capture (JS _matched/_before/_after); obs_matched None means no
  // handler resolution ran (skipSelf sends emit no record)
  priv mut obs_matched : ObserveMatch?
  priv mut obs_before : @tutuca.Value?
  priv mut obs_after : @tutuca.Value?
}

///|
/// Lazily-created completion scope (a transaction nobody awaits never
/// allocates one). Subscribe BEFORE draining — a completion first requested
/// after the transaction ran can no longer settle.
declare pub fn Transaction::completion(self : Transaction) -> Completion

///|
/// The dispatcher: a queue of transactions over a mutable root &PathNode.
/// Handlers resolve on the leaf (PathNode::handler); requests resolve via
/// the external registry.
pub struct Transactor {
  priv requests : &Requests
  mut root : &@tutuca.PathNode
  priv queue : Array[Transaction]
  priv change_subs : Array[(&@tutuca.PathNode, &@tutuca.PathNode) -> Unit]
  priv mut draining : Bool
  priv observers : Array[(ObserveRecord) -> Unit]
  priv mut obs_seq : Int
  priv drain_subs : Array[() -> Unit]
}

///|
declare pub fn Transactor::new(
  root : &@tutuca.PathNode,
  requests? : &Requests,
) -> Transactor

///|
/// Subscribe to a normalized record for every handler invocation
/// (send/receive, bubble, response, input, request). Returns an unsubscribe
/// function. Purely observational; empty by default (zero overhead).
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
  cb : (&@tutuca.PathNode, &@tutuca.PathNode) -> Unit,
) -> Unit

///|
/// Queue a targeted send (bucket Receive). skip_self queues the transaction
/// without running its own handler (the no-op first hop of ctx.bubble);
/// bubbles makes it pop one component per hop through the Bubble bucket
/// afterward. Returns the transaction (subscribe to its completion, then
/// settle()).
declare pub fn Transactor::push_send(
  self : Transactor,
  path : @tutuca.DispatchPath,
  name : String,
  args : Array[@tutuca.Value],
  parent? : Transaction,
  skip_self? : Bool,
  bubbles? : Bool,
) -> Transaction

///|
/// Queue a named input dispatch (bucket Input; JS InputDispatchEvent).
declare pub fn Transactor::push_input(
  self : Transactor,
  path : @tutuca.DispatchPath,
  name : String,
  args : Array[@tutuca.Value],
  parent? : Transaction,
) -> Transaction

///|
/// Resolve and invoke a request handler NOW (pinning the transaction path's
/// field-resolved keys against the current root unless opts.live_path); its
/// respond continuation queues the response (bucket Response, name routed
/// via opts) and drains.
declare pub fn Transactor::push_request(
  self : Transactor,
  path : @tutuca.DispatchPath,
  name : String,
  args : Array[@tutuca.Value],
  opts? : @tutuca.RequestOpts,
  parent? : Transaction,
) -> Unit

///|
/// Drain queued transactions until quiescent (`max_turns` backstops a
/// non-terminating cascade). Re-entrant calls (a respond firing mid-drain)
/// are no-ops — the outer loop picks the new work up.
declare pub fn Transactor::settle(self : Transactor, max_turns? : Int) -> Unit

///|
/// Whether transactions remain queued (JS hasPendingTransactions): the pending
/// check a time-slicing backend loops on alongside bounded settle(max_turns).
declare pub fn Transactor::has_pending(self : Transactor) -> Bool
