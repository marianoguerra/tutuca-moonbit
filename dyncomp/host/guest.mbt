///| The bridge to a loaded guest bundle. One implementation per transport:
/// the wasm demo implements it over the `tcomp` JS-bridge externs; tests
/// implement it with an in-process fake. Handles are guest-instance ids;
/// values are full tutuca Values (the transport decides how they cross —
/// the wasm bridge uses JSON + a JS-side arena).

///|
/// A framework call the guest buffered during a dispatch (WIT `control`);
/// the DynObj handler drains these through the dispatching `&Ctx`.
pub(all) enum ControlMsg {
  Emit(String, Array[@tutuca.Value])
  Send(String, Array[@tutuca.Value])
  Request(String, Array[@tutuca.Value])
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
  fn to_json_string(Self, handle : Int) -> String
  fn drop_instance(Self, handle : Int) -> Unit
}
