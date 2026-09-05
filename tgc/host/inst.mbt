// What the host holds when it holds a loaded component.
//
// `&Guest` next door is a TRANSPORT: one object per module, every call carrying
// an integer that names an instance inside it. That is the shape a JSON seam
// forces, because JSON can carry an integer and cannot carry a reference — and
// it is not the shape `tgc/SPEC.md` §4 describes, where "a child is a
// `&tg_inst` in your own state" and the engine collects it.
//
// So the host speaks these two instead. `Inst` is ONE INSTANCE and knows how to
// reach itself; `GuestModule` is the module's own exports, which are the only
// three things that are not about a particular instance. Nothing above this
// line passes a handle any more, which is what makes the integer a detail of
// one transport rather than a fact about the format.
//
// `HandleInst` below is that transport, adapted. It is the only implementation
// today and it is deliberately thin: the point of this split is that the host
// stopped naming instances by integer BEFORE anything changed about how they
// cross, so a fault here is a refactoring fault and nothing else.

///|
/// Result of forwarding one event to an instance.
///
/// `DispatchResult`'s twin, and the difference is the whole point: `next` is
/// the successor ITSELF rather than a name for it.
pub(all) struct InstDispatch {
  handled : Bool
  next : &Inst?
  msgs : Array[ControlMsg]
}

///|
/// What a write to a public property answered.
///
/// `GuestPropertyResult`'s twin, for the same reason `InstDispatch` is
/// `DispatchResult`'s.
pub(all) enum InstProperty {
  InstPropertyMissing
  InstPropertyUnchanged
  InstPropertyRefused
  InstPropertyChanged(&Inst)
}

///|
/// One live instance of a loaded module.
pub(open) trait Inst {
  fn get_field(Self, name : String) -> @tutuca.Value?
  fn with_field(Self, name : String, v : @tutuca.Value) -> &Inst?
  fn get_property(Self, name : String) -> @tutuca.Value?
  fn set_property(Self, name : String, value : @tutuca.Value) -> InstProperty
  /// `bindings` is what this component's DECLARED lookups resolve to, at this
  /// position, right now. Resolved by the caller and passed IN rather than
  /// fetched during the call, because every other thing a guest asks of the
  /// host is an effect applied afterwards, and a value a handler is in the
  /// middle of using cannot wait for that.
  fn dispatch(
    Self,
    bucket : @tutuca.HandlerBucket,
    name : String,
    args : Array[@tutuca.Value],
    bindings : Map[String, @tutuca.Value],
  ) -> InstDispatch
  /// One render-time method: a `compute`, a `pred`, a `@when` filter, an
  /// enricher. Pure — it must not mutate.
  fn render_call(
    Self,
    category : String,
    name : String,
    args : Array[@tutuca.Value],
    bindings : Map[String, @tutuca.Value],
  ) -> @tutuca.Value
  /// State as bytes only the guest interprets. Empty means it does not
  /// persist — not a failure, since the host can project declared fields.
  fn persist(Self) -> Bytes
  /// Called for a successor the host REFUSED — an ill-typed public result, or
  /// one that could not be adopted — and at no other time. It is not a
  /// supersession signal: an ordinary transition's predecessor is never
  /// released, because the host that motivated this trait holds references and
  /// lets the engine collect them. A transport that keeps a table has to notice
  /// supersession itself; `tgc/SPEC.md` §11 says how.
  fn release(Self) -> Unit
  /// Publish this instance into whatever crossing slot its own transport
  /// keeps, for a caller that has an `&Inst` and needs the concrete thing.
  ///
  /// MoonBit has no trait-object downcast (`core/spec.mbt` says so where it
  /// matters), so a transport that can hand a real reference back cannot be
  /// asked for one through a return type this package is allowed to name — the
  /// type is the transport's, and this package is target-agnostic on purpose.
  /// So the value goes out sideways, into a slot the transport owns and reads
  /// on the statement after the call.
  ///
  /// A no-op for a transport with nothing to publish, which is every transport
  /// that names its instances rather than holding them.
  fn hand_over(Self) -> Unit = _
  /// What distinguishes this instance from every other one the host holds.
  ///
  /// It seeds the render cache's bucket (`@tutuca.ObjId`), and a collision
  /// there is a re-render that does not happen — silently, because two
  /// instances that hash alike are simply treated as one. `tgc/emit`'s own
  /// comment on the identity counter says the same thing about the guest side
  /// of it.
  ///
  /// The default is the transport's name for it, which is unique within one
  /// transport. A transport that can hold instances from several modules has
  /// to say which module too, because the counter each module carries starts
  /// at zero.
  fn identity(Self) -> String = _
  /// How this instance names itself to the transport it came over.
  ///
  /// TRANSPORT-SPECIFIC, and the one method here that is. A transport that
  /// names instances by integer — the in-process fake does, and so did the
  /// JSON seam this replaced — answers that name; one that hands the reference
  /// over answers 0, and nothing asks.
  fn token(Self) -> Int
}

///|
impl Inst with fn hand_over(_self) {

}

///|
impl Inst with fn identity(self) {
  self.token().to_string()
}

///|
/// A loaded module's own exports: the three calls that are not about a
/// particular instance.
pub(open) trait GuestModule {
  fn make(Self, component : String, args : Map[String, @tutuca.Value]) -> &Inst?
  /// Bytes from `persist`, back into a live instance. None is the guest
  /// REFUSING them, and the caller rebuilds from the declared fields instead.
  fn restore(Self, component : String, state : Bytes) -> &Inst?
  /// Serve one of the intents the module declares on its own scope.
  /// Synchronous, like every call across this boundary: a guest that must wait
  /// dispatches an intent of its own and lets the host do the waiting.
  fn serve_intent(Self, name : String, args : Array[@tutuca.Value]) -> Result[
    @tutuca.Value,
    @tutuca.Value,
  ]
  /// The instance this transport names by `token`, wrapped again.
  ///
  /// Transport-specific for the same reason `Inst::token` is, and the inverse
  /// of it: a decoder holding an integer out of a `$dyn` marker needs the
  /// instance back, and only the module that minted the integer can say.
  fn of_token(Self, token : Int) -> &Inst
}

///|
/// One instance, named by an integer inside a `&Guest`.
///
/// The JSON transport, adapted to the two traits above and nothing more. Every
/// method is one call through, which is the property worth having while this
/// exists: it cannot change behaviour because there is nowhere for behaviour
/// to live.
pub struct HandleInst {
  guest : &Guest
  handle : Int
}

///|
/// The handle names an instance INSIDE ONE TRANSPORT, so a host that mints a
/// table per module — or per card, or per embed — hands two different
/// instances the same `identity`, because the default identity is that
/// integer. `DynObj` seeds its render-cache bucket from it, and two instances
/// that hash alike are treated as one: a redraw that silently does not happen.
///
/// `Inst::identity` says this too and this is where it gets read, so it is said
/// twice on purpose. Either make the handle page-wide — the runtime is shared,
/// so a handle can be — or override `identity` to say which module. A
/// downstream host hit exactly this with a counter per card, and its symptom
/// was a stale component rather than an error.
pub fn HandleInst::new(guest : &Guest, handle : Int) -> HandleInst {
  { guest, handle, }
}

///|
pub impl Inst for HandleInst with fn get_field(self, name) {
  self.guest.get_field(self.handle, name)
}

///|
pub impl Inst for HandleInst with fn with_field(self, name, v) {
  match self.guest.with_field(self.handle, name, v) {
    Some(h) => Some(HandleInst::{ guest: self.guest, handle: h, })
    None => None
  }
}

///|
pub impl Inst for HandleInst with fn get_property(self, name) {
  self.guest.get_property(self.handle, name)
}

///|
pub impl Inst for HandleInst with fn set_property(self, name, value) {
  match self.guest.set_property(self.handle, name, value) {
    GuestPropertyMissing => InstPropertyMissing
    GuestPropertyUnchanged => InstPropertyUnchanged
    GuestPropertyRefused => InstPropertyRefused
    GuestPropertyChanged(h) =>
      InstPropertyChanged(HandleInst::{ guest: self.guest, handle: h, })
  }
}

///|
pub impl Inst for HandleInst with fn dispatch(
  self,
  bucket,
  name,
  args,
  bindings,
) {
  // Through the BUCKET method rather than `handle_dispatch` directly, so an
  // implementation that overrode one of the two still gets its override. They
  // are defaulted in terms of `handle_dispatch`, which is exactly why routing
  // past them would be a silent behaviour change.
  let out = match bucket {
    Receive => self.guest.handle_message(self.handle, name, args, bindings)
    Intent => self.guest.handle_intent(self.handle, name, args, bindings)
  }
  {
    handled: out.handled,
    next: match out.next {
      Some(h) => Some(HandleInst::{ guest: self.guest, handle: h, })
      None => None
    },
    msgs: out.msgs,
  }
}

///|
pub impl Inst for HandleInst with fn render_call(
  self,
  category,
  name,
  args,
  bindings,
) {
  // Through the CATEGORY method rather than `render_call` directly, so an
  // implementation that overrode one of the four still gets its override. They
  // are defaulted in terms of `render_call`, which is exactly why routing past
  // them would be a silent behaviour change.
  match category {
    "compute" => self.guest.compute(self.handle, name, args, bindings)
    "when" => Bool(self.guest.when(self.handle, name, args, bindings))
    "enrich" => self.guest.enrich(self.handle, name, args, bindings)
    "enrichScope" => self.guest.bind_with(self.handle, name, bindings)
    _ => self.guest.render_call(self.handle, category, name, args, bindings)
  }
}

///|
pub impl Inst for HandleInst with fn persist(self) {
  self.guest.persist(self.handle)
}

///|
pub impl Inst for HandleInst with fn release(self) {
  self.guest.drop_instance(self.handle)
}

///|
pub impl Inst for HandleInst with fn token(self) {
  self.handle
}

///|
/// A module reached through one `&Guest`.
pub struct HandleModule {
  guest : &Guest
}

///|
pub fn HandleModule::new(guest : &Guest) -> HandleModule {
  { guest, }
}

///|
pub impl GuestModule for HandleModule with fn make(self, component, args) {
  // A guest that could not build one answers a handle no instance has. `-1` is
  // the transport's spelling of that and it is the only place it is read.
  let h = self.guest.create(component, args)
  if h < 0 {
    None
  } else {
    Some(HandleInst::{ guest: self.guest, handle: h, })
  }
}

///|
pub impl GuestModule for HandleModule with fn restore(self, component, state) {
  match self.guest.restore(component, state) {
    Some(h) => Some(HandleInst::{ guest: self.guest, handle: h, })
    None => None
  }
}

///|
pub impl GuestModule for HandleModule with fn serve_intent(self, name, args) {
  self.guest.serve_intent(name, args)
}

///|
pub impl GuestModule for HandleModule with fn of_token(self, token) {
  HandleInst::{ guest: self.guest, handle: token, }
}
