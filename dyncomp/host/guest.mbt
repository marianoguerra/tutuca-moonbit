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
  /// v2. `Emit` and `Request` both became this: one channel, and the ROUTE in
  /// the opts says which scope answers rather than the verb saying it.
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
  /// v1, and all three go in the contract step.
  Emit(String, Array[@tutuca.Value])
  BubbleAt(Array[@tutuca.Step], String, Array[@tutuca.Value])
  Request(String, Array[@tutuca.Value], RequestOpts)
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
/// The WIT's `request-opts`, which a bundle built against 0.7 still sends.
///
/// It used to be `@tutuca.RequestOpts` — the host's own authoring type — and
/// v2 deleted that, because a host handler writes `IntentOpts` now and the
/// combined `[res, err]` arm `on_res_name` selected is gone with the bug it
/// caused. The record survives HERE, as what it always was on this side: a
/// wire shape somebody else's build fills in. `DynObj` translates it to an
/// `IntentOpts` on the `lex` leg, which is what a `request` was.
pub(all) struct RequestOpts {
  on_ok_name : String?
  on_error_name : String?
  on_res_name : String?
  live_path : Bool
} derive(Debug, Eq)

///|
pub fn RequestOpts::new(
  on_ok_name? : String,
  on_error_name? : String,
  on_res_name? : String,
  live_path? : Bool = false,
) -> RequestOpts {
  { on_ok_name, on_error_name, on_res_name, live_path }
}

///|
/// The bucket a GUEST is dispatched through: the WIT's `bucket` enum, in its
/// case order.
///
/// It is deliberately NOT `@tutuca.HandlerBucket`, which v2 cut to two. A
/// loaded bundle is somebody else's build against a published contract — a
/// `.tutuca.tar.gz` compiled last year still has its view names in the `input`
/// bucket, and deleting the case here would stop it loading rather than
/// migrate it. So the host's buckets are two and the wire's are five, and
/// `DynObj::obj_handler` is the one place that translates.
pub(all) enum GuestBucket {
  Input
  Receive
  Response
  Bubble
  Intent
} derive(Debug, Eq)

///|
/// Its case index, which is its wire number.
pub fn GuestBucket::ordinal(self : GuestBucket) -> Int {
  match self {
    Input => 0
    Receive => 1
    Response => 2
    Bubble => 3
    Intent => 4
  }
}

///|
pub(open) trait Guest {
  fn create(Self, component : String, args : Map[String, @tutuca.Value]) -> Int
  fn get_field(Self, handle : Int, name : String) -> @tutuca.Value?
  fn dispatch(
    Self,
    handle : Int,
    bucket : GuestBucket,
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
