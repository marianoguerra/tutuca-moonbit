///|
/// One loaded module, as the host speaks it.
///
/// It holds the runtime and the module's own exports, both as opaque JS values,
/// and a way to find whoever made an instance that comes out of a call — which
/// is the one thing a module cannot answer about itself, because the answer is
/// usually another module.
pub struct NativeModule {
  key : String
  rt : @core.Any
  ex : @core.Any
  /// The page's other modules, by the name their manifests give.
  ///
  /// An instance crossing OUT of a call may have been made anywhere — that is
  /// what holding a foreign component means — and it has to be wrapped with the
  /// schema and views of the module that made it. Its descriptor says which,
  /// and this is how that name becomes a module.
  peers : (String) -> NativeModule?
  /// The host's own record of this module, once it has one. Needed to wrap an
  /// instance as a `DynObj`, and set after `register_module` because that call
  /// takes the module and cannot also return into it.
  loaded : Ref[@host.Module?]
}

///|
pub fn NativeModule::new(
  key : String,
  rt : @core.Any,
  ex : @core.Any,
  peers : (String) -> NativeModule?,
) -> NativeModule {
  { key, rt, ex, peers, loaded: Ref(None), }
}

///|
pub fn NativeModule::adopted(self : NativeModule, m : @host.Module) -> Unit {
  self.loaded.val = Some(m)
}

///|
/// One live instance: the `&tg_inst` itself, and the module that made it.
pub struct NativeInst {
  owner : NativeModule
  inst : @core.Any
}

///|
/// What a component calls itself and where it came from, off its own descriptor.
///
/// `desc` is that component's slice of its module's manifest, so the name is
/// under `name` and the module under `module`. Reading it off the INSTANCE is
/// the point: an instance answering a call on one module may have been made by
/// another, and the descriptor is the only thing that travels with it.
fn desc_key(rt : @core.Any, inst : @core.Any, want : String) -> String {
  let desc = rt1(rt, "inst_desc", inst)
  let n = as_int(rt1(rt, "map_len", desc))
  for i in 0..<n {
    if text_of(rt, rt2(rt, "map_key", desc, of_int(i))) == want {
      return text_of(rt, rt1(rt, "as_str", rt2(rt, "map_val", desc, of_int(i))))
    }
  }
  ""
}

///|
/// The module that made this instance, or the one that answered for it.
///
/// The fallback is for a module built before descriptors carried `module`.
/// "I do not know" and "whoever happened to be decoding" are different answers
/// and guessing the second is the bug the key was added to end — but a wrong
/// schema is still better than dropping the value, so the fallback is named
/// rather than silent.
fn owner_of(from : NativeModule, inst : @core.Any) -> NativeModule {
  let named = desc_key(from.rt, inst, "module")
  if named == "" || named == from.key {
    return from
  }
  match (from.peers)(named) {
    Some(m) => m
    None => from
  }
}

///|
/// Wrap a `tg_inst` as the host's `&Obj`, through the module that made it.
fn wrap(from : NativeModule, inst : @core.Any) -> @tutuca.Value? {
  let owner = owner_of(from, inst)
  guard owner.loaded.val is Some(m) else { return None }
  let comp = desc_key(owner.rt, inst, "name")
  m.wrap_inst(comp, NativeInst::{ owner, inst, })
}

///|
/// Where an instance on its way BACK to a guest lands.
///
/// `@host.inst_of` answers an `&Inst`, and MoonBit has no downcast — so the
/// concrete reference comes out sideways, through `hand_over`, into this. One
/// slot, read on the statement after the call.
let crossing : Ref[@core.Any?] = Ref(None)

///|
/// The `tg_inst` behind a value, or None for a value no guest could hold.
///
/// A host component answers None, and that is the whole of the test now — an
/// instance of ANOTHER module is perfectly crossable, which is the change this
/// package is for.
fn hand_back(v : @tutuca.Value) -> @core.Any? {
  guard @host.inst_of(v) is Some(i) else { return None }
  crossing.val = None
  i.hand_over()
  let out = crossing.val
  crossing.val = None
  out
}

///|
fn NativeInst::decode(self : NativeInst, v : @core.Any) -> @tutuca.Value? {
  value_of(self.owner.rt, v, inst => wrap(self.owner, inst))
}

///|
fn NativeInst::encode(self : NativeInst, v : @tutuca.Value) -> @core.Any {
  val_of(self.owner.rt, v, hand_back)
}

///|
fn NativeInst::args(
  self : NativeInst,
  args : Array[@tutuca.Value],
) -> @core.Any {
  vals_of(self.owner.rt, args, hand_back)
}

///|
/// The bindings a guest's `control.lookup` reads, as the call's fifth slot.
fn NativeInst::binds(
  self : NativeInst,
  bindings : Map[String, @tutuca.Value],
) -> @core.Any {
  if bindings.is_empty() {
    null_any()
  } else {
    self.encode(Map(bindings))
  }
}

///|
pub impl @host.Inst for NativeInst with fn get_field(self, name) {
  self.decode(
    rt2(
      self.owner.rt,
      "get_field",
      self.inst,
      bytes_of_text(self.owner.rt, name),
    ),
  )
}

///|
/// `call(self, op, name, args, v)` — the signature, exactly.
///
/// The JSON seam had eleven functions where this has one, and the difference is
/// not tidiness: `category` existed only to pick an op across a string
/// boundary, and the fifth slot was "the bindings, except when it is the
/// written value". Here it is the fifth slot.
fn NativeInst::call(
  self : NativeInst,
  op : Int,
  name : String,
  args : @core.Any,
  v : @core.Any,
) -> @core.Any {
  rt5(
    self.owner.rt,
    "call_op",
    self.inst,
    of_int(op),
    bytes_of_text(self.owner.rt, name),
    args,
    v,
  )
}

///|
pub impl @host.Inst for NativeInst with fn with_field(self, name, v) {
  let out = self.call(1, name, self.args([]), self.encode(v))
  if is_absent(out) {
    None
  } else {
    Some(NativeInst::{
      owner: self.owner,
      inst: rt1(self.owner.rt, "as_inst", out),
    })
  }
}

///|
pub impl @host.Inst for NativeInst with fn get_property(self, name) {
  self.decode(self.call(8, name, self.args([]), null_any()))
}

///|
pub impl @host.Inst for NativeInst with fn set_property(self, name, value) {
  let out = self.call(9, name, self.args([]), self.encode(value))
  if is_absent(out) {
    InstPropertyMissing
  } else {
    InstPropertyChanged(NativeInst::{
      owner: self.owner,
      inst: rt1(self.owner.rt, "as_inst", out),
    })
  }
}

///|
pub impl @host.Inst for NativeInst with fn dispatch(
  self,
  bucket,
  name,
  args,
  bindings,
) {
  let op = match bucket {
    Receive => 2
    Intent => 3
  }
  clear_control(self.owner.key)
  let out = self.call(op, name, self.args(args), self.binds(bindings))
  let next = if is_absent(out) {
    None
  } else {
    Some(
      (
        NativeInst::{
          owner: self.owner,
          inst: rt1(self.owner.rt, "as_inst", out),
        } : &@host.Inst),
    )
  }
  { handled: next is Some(_), next, msgs: drained(self.owner), }
}

///|
pub impl @host.Inst for NativeInst with fn render_call(
  self,
  category,
  name,
  args,
  bindings,
) {
  let op = match category {
    "when" => 5
    "enrich" => 6
    "enrichScope" => 7
    _ => 4
  }
  self
  .decode(self.call(op, name, self.args(args), self.binds(bindings)))
  .unwrap_or(Null)
}

///|
pub impl @host.Inst for NativeInst with fn persist(self) {
  let out = self.call(12, "", self.args([]), null_any())
  match self.decode(out) {
    Some(Bin(b)) => b
    _ => b""
  }
}

///|
/// Nothing to release.
///
/// THE WHOLE POINT, and the row `tgc/SPEC.md` §4 claims: an instance is a GC
/// struct and the engine collects it. There is no table row to remove because
/// there is no table — the host held a reference all along, and when it stops
/// holding it, it is gone.
pub impl @host.Inst for NativeInst with fn release(_self) {

}

///|
/// No integer names this instance. Nothing asks for one.
pub impl @host.Inst for NativeInst with fn token(_self) {
  0
}

///|
/// The module that made it, and its own counter within that module.
///
/// BOTH halves are needed. `tg_inst.id` is a per-module counter starting at
/// zero — `tgc/emit/state.mbt` says so where it is emitted — so two modules'
/// first instances share an id, and an id is what the render cache buckets on.
pub impl @host.Inst for NativeInst with fn identity(self) {
  self.owner.key + "#" + i64_text(rt1(self.owner.rt, "inst_id", self.inst))
}

///|
pub impl @host.Inst for NativeInst with fn hand_over(self) {
  crossing.val = Some(self.inst)
}

///|
pub impl @host.GuestModule for NativeModule with fn make(self, component, args) {
  // `<C>_make_fields` takes `&?tg_val` and reads a MAP out of it, so "no
  // arguments" is `ref.null` rather than an empty map — the same distinction
  // SPEC §9 keeps everywhere else.
  let a = if args.is_empty() {
    null_any()
  } else {
    val_of(self.rt, Map(args), hand_back)
  }
  // `tgc.make` answers an INSTANCE, not a `tg_comp` wrapping one — the
  // generated shell returns `<C>_inst(...)` directly. `call_op` is the other
  // way round, because a transition answers `tg_comp(successor)`.
  let out = tgc_make(self.ex, bytes_of_text(self.rt, component), a)
  if is_absent(out) {
    None
  } else {
    Some(NativeInst::{ owner: self, inst: out, })
  }
}

///|
/// A module's own `tgc.serve`.
///
/// The JSON seam never called it: `card.js` installed no path to it, so a
/// module declaring `serve` had nothing on the other end. It is one call here,
/// and the capability arrives with the seam rather than needing a design.
pub impl @host.GuestModule for NativeModule with fn serve_intent(
  self,
  name,
  args,
) {
  let out = tgc_serve(
    self.ex,
    bytes_of_text(self.rt, name),
    vals_of(self.rt, args, hand_back),
  )
  if is_absent(out) {
    Err(Str("the module answered nothing for `\{name}`"))
  } else {
    Ok(value_of(self.rt, out, inst => wrap(self, inst)).unwrap_or(Null))
  }
}

///|
/// Bytes from `persist`, back into a live instance.
///
/// Op 13's protocol is not pinned by anything today, so this declines rather
/// than inventing one — and declining is a real answer: the caller rebuilds
/// from the declared fields, which is what it does for every guest that does
/// not persist.
pub impl @host.GuestModule for NativeModule with fn restore(
  _self,
  _component,
  _state,
) {
  None
}

///|
/// No integer names an instance here, so nothing can be found by one.
pub impl @host.GuestModule for NativeModule with fn of_token(self, _token) {
  NativeInst::{ owner: self, inst: null_any(), }
}

///|
/// `tgc.make` and `tgc.serve` — the module's OWN exports, named with the dot
/// the format spells them with, which is why they are externs rather than
/// `rt2` calls.
extern "js" fn tgc_make(
  ex : @core.Any,
  comp : @core.Any,
  args : @core.Any,
) -> @core.Any =
  #|(ex, comp, args) => ex["tgc.make"](comp, args)

///|
extern "js" fn tgc_serve(
  ex : @core.Any,
  name : @core.Any,
  args : @core.Any,
) -> @core.Any =
  #|(ex, name, args) => ex["tgc.serve"](name, args)

///|
/// The manifest, as the module describes itself.
pub fn NativeModule::manifest_json(self : NativeModule) -> String {
  match value_of(self.rt, tgc_describe(self.ex), _inst => None) {
    Some(v) => v.to_json().stringify()
    None => "{}"
  }
}

///|
extern "js" fn tgc_describe(ex : @core.Any) -> @core.Any =
  #|(ex) => ex["tgc.describe"]()
