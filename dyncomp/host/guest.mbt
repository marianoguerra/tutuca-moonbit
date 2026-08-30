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
  /// Answer whoever sent the message being handled, under a name the guest
  /// picked. An ordinary message, so it buffers like `Send` and the host
  /// applies it the same way.
  SendReply(String, Array[@tutuca.Value])
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
pub(all) enum GuestPropertyResult {
  GuestPropertyMissing
  GuestPropertyUnchanged
  GuestPropertyRefused
  GuestPropertyChanged(Int)
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
  /// Forward one event to the guest.
  ///
  /// `bindings` is what this component's DECLARED lookups resolve to, at this
  /// position, right now — the guest's `control.lookup` reads them and nothing
  /// else. They are resolved by the caller and passed IN rather than fetched
  /// during the call, because every other thing a guest asks of the host is an
  /// effect applied afterwards, and a value a handler is in the middle of
  /// using cannot wait for that. Empty for a component that declares no
  /// lookup, which is most of them.
  fn handle_dispatch(
    Self,
    handle : Int,
    bucket : @tutuca.HandlerBucket,
    name : String,
    args : Array[@tutuca.Value],
    bindings : Map[String, @tutuca.Value],
  ) -> DispatchResult
  fn handle_message(
    Self,
    handle : Int,
    name : String,
    args : Array[@tutuca.Value],
    bindings : Map[String, @tutuca.Value],
  ) -> DispatchResult = _
  fn handle_intent(
    Self,
    handle : Int,
    name : String,
    args : Array[@tutuca.Value],
    bindings : Map[String, @tutuca.Value],
  ) -> DispatchResult = _
  /// Call one render-time method: a `compute`, a `pred`, a `@when` filter, an
  /// enricher. Pure — it must not mutate.
  ///
  /// `bindings` is `dispatch`'s, resolved for the RENDER position instead of
  /// the dispatch one, and it is here for the reason it is there: a value body
  /// that reads `*name` has nowhere else to get the answer, and
  /// `control.lookup` reads these and nothing else. Without it a card's `pred`
  /// compiled `tc_lookup` and read nil — silently, which is the failure this
  /// argument exists to remove.
  fn render_call(
    Self,
    handle : Int,
    category : String,
    name : String,
    args : Array[@tutuca.Value],
    bindings : Map[String, @tutuca.Value],
  ) -> @tutuca.Value
  fn compute(
    Self,
    handle : Int,
    name : String,
    args : Array[@tutuca.Value],
    bindings : Map[String, @tutuca.Value],
  ) -> @tutuca.Value = _
  fn when(
    Self,
    handle : Int,
    name : String,
    args : Array[@tutuca.Value],
    bindings : Map[String, @tutuca.Value],
  ) -> Bool = _
  fn enrich(
    Self,
    handle : Int,
    name : String,
    args : Array[@tutuca.Value],
    bindings : Map[String, @tutuca.Value],
  ) -> @tutuca.Value = _
  fn enrich_scope(
    Self,
    handle : Int,
    name : String,
    bindings : Map[String, @tutuca.Value],
  ) -> @tutuca.Value = _
  fn get_property(Self, handle : Int, name : String) -> @tutuca.Value? = _
  fn set_property(Self, handle : Int, name : String, value : @tutuca.Value) -> GuestPropertyResult = _
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

///|
impl Guest with fn get_property(_self, _handle, _name) {
  None
}

///|
impl Guest with fn set_property(_self, _handle, _name, _value) {
  GuestPropertyMissing
}

///|
impl Guest with fn handle_message(self, handle, name, args, bindings) {
  self.handle_dispatch(handle, Receive, name, args, bindings)
}

///|
impl Guest with fn handle_intent(self, handle, name, args, bindings) {
  self.handle_dispatch(handle, Intent, name, args, bindings)
}

///|
impl Guest with fn compute(self, handle, name, args, bindings) {
  self.render_call(handle, "compute", name, args, bindings)
}

///|
impl Guest with fn when(self, handle, name, args, bindings) {
  self.render_call(handle, "when", name, args, bindings).bool(default=false)
}

///|
impl Guest with fn enrich(self, handle, name, args, bindings) {
  self.render_call(handle, "enrich", name, args, bindings)
}

///|
impl Guest with fn enrich_scope(self, handle, name, bindings) {
  self.render_call(handle, "enrichScope", name, [], bindings)
}
