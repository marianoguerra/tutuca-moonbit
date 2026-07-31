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
  Emit(String, Array[@tutuca.Value])
  Send(String, Array[@tutuca.Value])
  SendAt(Array[@tutuca.Step], String, Array[@tutuca.Value])
  BubbleAt(Array[@tutuca.Step], String, Array[@tutuca.Value])
  Request(String, Array[@tutuca.Value], @tutuca.RequestOpts)
  StopPropagation
} derive(Debug, Eq)

///|
/// Result of forwarding one event to the guest: the successor instance
/// handle (None = unchanged) plus any buffered control messages.
pub(all) struct DispatchResult {
  next : Int?
  msgs : Array[ControlMsg]
} derive(Debug, Eq)

///|
pub(open) trait Guest {
  fn create(Self, component : String, args : Map[String, @tutuca.Value]) -> Int
  fn get_field(Self, handle : Int, name : String) -> @tutuca.Value?
  fn seq_entries(Self, handle : Int) -> Array[(String, @tutuca.Value)]?
  fn dispatch(
    Self,
    handle : Int,
    bucket : @tutuca.HandlerBucket,
    name : String,
    args : Array[@tutuca.Value],
  ) -> DispatchResult
  fn call_method(Self, handle : Int, name : String, args : Array[@tutuca.Value]) -> @tutuca.Value
  fn with_field(Self, handle : Int, name : String, v : @tutuca.Value) -> Int?
  /// Serve one of the requests the bundle declares. Synchronous, like every
  /// call across this boundary: a guest that must wait asks the host instead.
  fn handle_request(Self, name : String, args : Array[@tutuca.Value]) -> Result[
    @tutuca.Value,
    @tutuca.Value,
  ]
  fn drop_instance(Self, handle : Int) -> Unit
}
