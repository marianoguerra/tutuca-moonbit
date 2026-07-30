// Spec for the port of tutuca's path traversal (src/path.js) plus the
// leaf-update core of the transactor (src/transactor.js updateRootValue).
// READONLY by convention: concrete public data types plus `declare` stubs.
// Implement the declares in separate files; this file and the *_test.mbt
// suites define the contract.
//
// Layering note: this package owns the path CORE (steps, resolve/update,
// dispatch-path compaction + teleporting via DispatchPath::to_transaction_path
// below). The pieces that need the view registry, the rendered DOM, or the
// component stack live one layer up, where they were implemented:
//   - frame-only steps + stack rebuild (JS enterFrame/buildStack) -> render's
//     build_stack (render/build_stack.mbt), one arm per Step kind;
//   - event-path reconstruction (JS Path.fromNodeAndEventName/fromEvent) ->
//     render's from_node_and_event_name (render/events.mbt), driven by the
//     backend glue + App::dispatch (which extract target/event-name, the job
//     of the JS Path.fromEvent wrapper);
//   - dispatch channels (send/bubble/request/response) -> the transactor
//     package.
// DynStep teleporting itself (JS toTransactionPath) IS here — see
// DispatchPath::to_transaction_path.

///|
/// Dispatch buckets a handler can live in (semantics.md §6). Alter is
/// render-time only and never dispatched, so it is not a bucket here.
pub(all) enum HandlerBucket {
  Receive // ctx.send targeted messages
  Input // DOM / @on.* handlers
  Bubble // ctx.bubble handlers
  Response // request-response handlers
} derive(Debug, Eq)

///|
/// Options for Ctx::request (JS pushRequest opts): response-handler routing
/// (on_ok_name / on_error_name / on_res_name) and live_path, which opts out
/// of pinning field-resolved keys at request time.
pub(all) struct RequestOpts {
  on_ok_name : String?
  on_error_name : String?
  on_res_name : String?
  live_path : Bool
} derive(Debug, Eq)

///|
declare pub fn RequestOpts::new(
  on_ok_name? : String,
  on_error_name? : String,
  on_res_name? : String,
  live_path? : Bool,
) -> RequestOpts

///|
/// What a handler can do besides transforming its leaf (JS EventContext).
/// Defined here so Handler can carry it without depending on the transactor;
/// every method defaults to a no-op so tests and Path::update can run
/// handlers without a dispatcher. The transactor implements the real thing.
pub(open) trait Ctx {
  fn path(Self) -> DispatchPath = _
  fn target_path(Self) -> DispatchPath = _
  fn name(Self) -> String? = _
  fn send(Self, name : String, args : Array[Value]) -> Unit = _
  fn bubble(Self, name : String, args : Array[Value]) -> Unit = _
  fn send_at_path(Self, path : DispatchPath, name : String, args : Array[Value]) -> Unit = _
  fn bubble_at_path(
    Self,
    path : DispatchPath,
    name : String,
    args : Array[Value],
  ) -> Unit = _
  fn request(Self, name : String, args : Array[Value], opts : RequestOpts) -> Unit = _
  fn stop_propagation(Self) -> Unit = _
  /// `ctx.at`: a relative-path builder rooted at this ctx's dispatch path.
  fn at(Self) -> PathChanges = _
  /// Walk the component instances on this ctx's path leaf→root (JS
  /// walkPath), invoking `callback(component_id, instance)` for each; return
  /// false to stop early. Non-component chain elements are skipped. The pure
  /// default walks nothing (no state root); the transactor implements it.
  fn walk_path(Self, callback : (Int, Value) -> Bool) -> Unit = _
}

///|
impl Ctx with fn path(_self) {
  DispatchPath::new()
}

///|
impl Ctx with fn target_path(_self) {
  DispatchPath::new()
}

///|
impl Ctx with fn name(_self) {
  None
}

///|
/// `ctx.send` is `send_at_path` at the ctx's OWN path, and `ctx.bubble` is
/// `bubble_at_path` there — which is what the transactor's ctx used to say
/// twice, once as a default that did nothing and once as an implementation.
/// Spelling them here leaves one pair of methods to implement, and no way for
/// the relative and absolute forms to disagree about what "here" means.
impl Ctx with fn send(self, name, args) {
  self.send_at_path(self.path(), name, args)
}

///|
impl Ctx with fn bubble(self, name, args) {
  self.bubble_at_path(self.path(), name, args)
}

///|
impl Ctx with fn send_at_path(_self, _path, _name, _args) {

}

///|
impl Ctx with fn bubble_at_path(_self, _path, _name, _args) {

}

///|
impl Ctx with fn request(_self, _name, _args, _opts) {

}

///|
impl Ctx with fn stop_propagation(_self) {

}

///|
impl Ctx with fn at(self) {
  PathChanges::of(self)
}

///|
impl Ctx with fn walk_path(_self, _callback) {

}

///|
/// A Ctx that dispatches nothing (JS `eval(null)` analogue for handlers).
pub(all) struct NullCtx {}

///|
pub impl Ctx for NullCtx

///|
/// A leaf-update handler, resolved ON the leaf so `self` is pre-bound (the JS
/// `handler.apply(instance, args)` binds `this` at call time; binding at
/// resolution time is equivalent — same instance either way). Receives its
/// args and the dispatch Ctx (JS appends ctx as the last handler argument).
/// Returns the new leaf, or None for "no change" (the port of the JS
/// `newLeaf !== curLeaf` identity check — answering None lets the traversal
/// skip the spine rebuild without comparing anything).
pub(all) struct Handler((Array[Value], &Ctx) -> Value?)

///|
/// Resolve one addressing step against a node: the child it addresses, or
/// None when unresolvable (missing field, bad index, key field not a key…).
/// One interpreter over the `value_dyn.mbt` accessors, so step semantics —
/// especially SeqAccessStep's live key resolution — are written once.
///
/// The tree used to be addressed through a `PathNode` TRAIT, so that a node
/// could be something other than a `Value`. Nothing ever was: the only
/// implementation outside the tests was `Value` itself, while typed component
/// instances travelled — as they still do — inside `Value::Obj`. What the
/// trait did buy was a box per traversal step, an `as_value` unwrap at every
/// consumer (with an impossible failure branch each time), and a `same_node`
/// that existed because two boxes carrying the SAME value are not
/// `physical_equal` — which is the one comparison the whole copy-on-write
/// design is keyed on.
declare pub fn step_get(node : Value, step : Step) -> Value?

///|
/// Rebuild one spine level: a new node with the child this step addresses
/// replaced by `child`. None when the step is unaddressable on `node`
/// (the caller leaves the tree untouched).
declare fn step_put(node : Value, step : Step, child : Value) -> Value?

///|
/// A generic `{field, key?}` descriptor of an addressing step (JS
/// Step.toKey), so tooling can introspect a path without matching on Step.
pub(all) struct StepKey {
  field : String
  key : PathKey?
} derive(Debug, Eq)

///|
/// An address into the component/state tree: a sequence of steps root→leaf.
pub(all) struct Path {
  steps : Array[Step]
} derive(Debug, Eq)

///|
declare pub fn Path::new(steps? : Array[Step]) -> Path

///|
declare pub fn Path::concat(self : Path, steps : Array[Step]) -> Path

///|
/// The path one component closer to the root (bubbling walks this).
declare pub fn Path::pop_step(self : Path) -> Path

///|
/// The value this path resolves to, or None at the first unresolvable step.
declare pub fn Path::lookup(self : Path, root : Value) -> Value?

///|
/// Replace the leaf: walk down collecting intermediates, rebuild the spine
/// bottom-up via step_put (structural sharing). If any step is unresolvable
/// the SAME `root` object is returned (physically — callers detect "nothing
/// happened" by `physical_equal`, matching JS setValue).
declare pub fn Path::set_value(self : Path, root : Value, v : Value) -> Value

///|
/// The nodes entered along the path, root included (index 0), stopping at
/// the first unresolvable step. JS Path.resolveChain. Powers the
/// transactor's `ctx.walk_path` (leaf→root component walk).
declare pub fn Path::resolve_chain(self : Path, root : Value) -> Array[Value]

///|
/// Freeze every field-resolved key (SeqAccessStep) against `root` as it is
/// NOW: SeqAccessStep(seq, keyField) becomes SeqStep(seq, key) so a later
/// lookup/set_value lands on the same item even if keyField changes meanwhile
/// (async response races). Returns `self` (physically) when nothing pinned.
declare pub fn Path::pin_keys(self : Path, root : Value) -> Path

///|
/// Flat StepKey list of the addressing steps (JS Path.toKeys). SeqAccessStep
/// reports its seq field with no key (the key is live; pin_keys first for a
/// concrete one) rather than being dropped, which would shift later indices.
declare pub fn Path::to_keys(self : Path) -> Array[StepKey]

///|
/// One hop of a dispatch path — the component-boundary projection of an event
/// path. Plain wraps an addressing step with its origin (the id of the
/// component that contributed it — teleport provenance); Dyn marks a dynamic
/// variable (`*dyn`) used as a render target: the rendered data lives at the
/// PRODUCER component (where the dynamic was defined), not at the consumer
/// that wrote `<x render="*dyn">`, so `interior` lists the component ids
/// crossed between producer and consumer, and `steps` is the producer's own
/// path to the data. `key` is set when the dynamic is ITERATED (the item lives
/// at the producer's sequence field under that key) — the one thing that used
/// to be a whole second variant, `DynEach`, which differed in nothing else and
/// so was matched alongside `Dyn` everywhere except the one line that reads
/// the key.
pub(all) enum DispatchStep {
  Plain(step~ : Step, origin~ : Int?)
  Dyn(
    producer~ : Int,
    steps~ : Array[Step],
    interior~ : Array[Int],
    key~ : PathKey?
  )
} derive(Debug, Eq)

///|
/// A path that still knows which component contributed each hop. Bubbling
/// pops one hop per component; converting to a transaction Path teleports
/// every Dyn marker so mutations land on the data's real location.
pub(all) struct DispatchPath {
  items : Array[DispatchStep]
} derive(Debug, Eq)

///|
declare pub fn DispatchPath::new(items? : Array[DispatchStep]) -> DispatchPath

///|
/// Wrap plain addressing steps (no origins, no dynamics).
declare pub fn DispatchPath::of_steps(steps : Array[Step]) -> DispatchPath

///|
/// Append plain addressing steps (ctx.at-style refinement of a handler path).
declare pub fn DispatchPath::concat(
  self : DispatchPath,
  steps : Array[Step],
) -> DispatchPath

///|
/// One component closer to the root (bubbling walks this).
declare pub fn DispatchPath::pop_step(self : DispatchPath) -> DispatchPath

///|
/// The dispatch projection: frame-only plain steps dropped, EachRenderItStep
/// abstracted, Dyn markers KEPT (bubbling must still visit the components
/// interior to a dynamic-var render). Origins are preserved.
declare pub fn DispatchPath::compact(self : DispatchPath) -> DispatchPath

///|
/// The abstract path used to apply a transaction: every Dyn marker is
/// teleported — the trailing steps whose origin is interior to the
/// producer..consumer span are dropped and the producer's own steps spliced
/// in (stamped with the producer id, so a Dyn nested inside another
/// teleports correctly). An iterated Dyn splices a keyed SeqStep for its last
/// FieldStep; a seq-access dynamic cannot be iterated and splices unchanged.
declare pub fn DispatchPath::to_transaction_path(self : DispatchPath) -> Path

///|
/// The transactor's updateRootValue: resolve the leaf, resolve its handler by
/// exact name — ONE lookup, with no fallback sentinel behind it (see
/// path_path.mbt) — invoke it, and rebuild the spine only when the handler
/// produced a new leaf. Unresolvable path,
/// missing handler, a handler answering None, or a physically-unchanged leaf
/// all return the SAME `root` object — the spine is not rebuilt when nothing
/// changed.
declare pub fn Path::update(
  self : Path,
  root : Value,
  bucket : HandlerBucket,
  name : String,
  args : Array[Value],
) -> Value
