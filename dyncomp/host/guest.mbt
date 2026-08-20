///| The bridge to a loaded guest bundle. One implementation per transport:
/// the wasm demo implements it over the `tcomp` JS-bridge externs; tests
/// implement it with an in-process fake. Handles are guest-instance ids;
/// values are full tutuca Values (the transport decides how they cross —
/// the wasm bridge uses JSON + a JS-side arena).

///|
/// A framework call the guest buffered during a dispatch (WIT `control`);
/// the DynObj handler drains these through the dispatching `&Ctx`.
///
/// Paths are RELATIVE to the dispatching instance — a guest addresses its own
/// subtree and nothing above it, so what crosses is steps to concat onto
/// `ctx.path()`, never an absolute path.
pub(all) enum ControlMsg {
  Send(String, Array[@tutuca.Value])
  SendAt(Array[@tutuca.Step], String, Array[@tutuca.Value])
  /// One routed channel: the ROUTE in the opts says which scope answers,
  /// rather than the verb saying it.
  Intent(String, Array[@tutuca.Value], @tutuca.IntentOpts)
  IntentAt(
    Array[@tutuca.Step],
    String,
    Array[@tutuca.Value],
    @tutuca.IntentOpts
  )
  /// Pass the message on, or continue the walk. Empty args means "the ones
  /// that arrived"; the opts carry the route the forwarder named, if any.
  Forward(Array[@tutuca.Value], @tutuca.IntentOpts)
  Reply(@tutuca.Value)
  Fail(@tutuca.Value)
  StopPropagation
} derive(Debug, Eq)

///|
/// Result of forwarding one event to the guest. `handled` distinguishes a
/// real no-op handler from an unknown input name, which lets the host fall
/// back to a generated field mutator only for the latter.
pub(all) struct DispatchResult {
  handled : Bool
  next : Int?
  msgs : Array[ControlMsg]
} derive(Debug, Eq)

///|
/// The wire number of a dispatch bucket: its case index in the WIT's `bucket`
/// enum.
///
/// The host's buckets and the wire's are the same two, so there is no separate
/// enum here and nothing to translate — this is a numbering, not a vocabulary.
pub fn bucket_ordinal(b : @tutuca.HandlerBucket) -> Int {
  match b {
    Receive => 0
    Intent => 1
  }
}

///|
pub(open) trait Guest {
  fn create(Self, component : String, args : Map[String, @tutuca.Value]) -> Int
  fn get_field(Self, handle : Int, name : String) -> @tutuca.Value?
  fn dispatch(
    Self,
    handle : Int,
    bucket : @tutuca.HandlerBucket,
    name : String,
    args : Array[@tutuca.Value],
  ) -> DispatchResult
  fn call_method(Self, handle : Int, name : String, args : Array[@tutuca.Value]) -> @tutuca.Value
  fn with_field(Self, handle : Int, name : String, v : @tutuca.Value) -> Int?
  /// Serve one of the intents the bundle declares on its own scope.
  /// Synchronous, like every call across this boundary: a guest that must wait
  /// dispatches an intent of its own and lets the host do the waiting.
  fn serve_intent(Self, name : String, args : Array[@tutuca.Value]) -> Result[
    @tutuca.Value,
    @tutuca.Value,
  ]
  /// This instance's state as bytes only the guest interprets (WIT
  /// `instance.persist`). Empty means the guest does not persist — not a
  /// failure, since the host can project the declared fields itself.
  fn persist(Self, handle : Int) -> Bytes
  /// Bytes from `persist`, back into a live instance (WIT
  /// `[static]instance.restore`). None is the guest REFUSING them, and the
  /// caller then rebuilds from the declared fields instead.
  fn restore(Self, component : String, state : Bytes) -> Int?
  fn drop_instance(Self, handle : Int) -> Unit
}
