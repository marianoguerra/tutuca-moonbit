///| MoonBit guest SDK for `tutuca:component`, alongside the wit-bindgen output.
///
/// CANONICAL COPY: `guests/sdk.mbt`. `gen-bindings.mjs` copies it verbatim into
/// every guest's generated guest package, and `tutuca new-guest` emits it — so
/// edit the canonical, never a copy. A copy edited by hand is overwritten on the
/// next regeneration, and the drift check fails the commit that did it.
///
/// It implements every `declare` from top.mbt generically over a
/// `DynComponent` trait, so authoring a guest is: one struct per component
/// implementing `DynComponent`, plus one `dyn_module()` returning names and
/// factories (see the sibling component source). Catalog/schema/view data is
/// static bundle metadata, not executable guest code.
///
/// Canonical-ABI asymmetry this SDK hides: `Instance` values RETURNED to the
/// host (constructor, handler successors) must be handles made with
/// `Instance::new(rep)`, but `self`/params RECEIVED in methods and the dtor
/// carry the rep directly — never call `.rep()` on those.

///|
/// One guest component's behavior over opaque native state. Handlers are
/// functional: return whether the name was handled and, when changed, the
/// successor state. Every method defaults to an empty answer.
///
/// There is no `to_json` and no `eq`: the host projects and compares an
/// instance through the fields the static manifest declares.
pub(all) enum HandleResult {
  Unhandled
  Unchanged
  Changed(&DynComponent)
}

///|
/// Adapt a COW helper that returns `None` for a refused/no-op update into a
/// handled event result. Useful for validation-heavy handlers.
pub fn handled(next : &DynComponent?) -> HandleResult {
  match next {
    Some(state) => Changed(state)
    None => Unchanged
  }
}

///|
pub(open) trait DynComponent {
  fn get_field(Self, name : String) -> @values.Value? = _
  fn handle(Self, bucket : Bucket, name : String, args : Array[@values.Value]) -> HandleResult = _
  fn call_method(Self, name : String, args : Array[@values.Value]) -> @values.Value = _
  fn with_field(Self, name : String, v : @values.Value) -> &DynComponent? = _
  /// This instance's state as bytes ONLY THIS GUEST reads (WIT
  /// `instance.persist`). The host stores them and hands them back to the
  /// component's `restore`; it never looks inside.
  ///
  /// The default is empty, which the host reads as "I do not persist" and
  /// answers by projecting the DECLARED fields itself — so a component whose
  /// state is exactly its fields should leave this alone rather than write the
  /// same list a second time.
  fn persist(Self) -> FixedArray[Byte] = _
}

///|
impl DynComponent with fn get_field(_self, _name) {
  None
}

///|
impl DynComponent with fn handle(_self, _bucket, _name, _args) {
  Unhandled
}

///|
impl DynComponent with fn call_method(_self, _name, _args) {
  @values.Value::Nil
}

///|
impl DynComponent with fn with_field(_self, _name, _v) {
  None
}

///|
impl DynComponent with fn persist(_self) {
  no_bytes()
}

///|
pub(all) struct ComponentFactory {
  name : String
  make : (Array[(String, @values.Value)]) -> &DynComponent
  /// The inverse of `DynComponent::persist`: bytes this component wrote, back
  /// into state. None REFUSES them — a format this guest no longer reads — and
  /// the host falls back to constructing from the declared fields, which is
  /// also what the default does.
  restore : (FixedArray[Byte]) -> &DynComponent?
}

///|
/// A component of this module: its static-manifest name, how to build one, and
/// (when it persists) how to read its bytes back.
pub fn dyn_comp(
  name : String,
  make : (Array[(String, @values.Value)]) -> &DynComponent,
  restore? : (FixedArray[Byte]) -> &DynComponent? = no_restore,
) -> ComponentFactory {
  { name, make, restore }
}

///|
/// `ComponentFactory::restore` for a component that does not persist.
fn no_restore(_state : FixedArray[Byte]) -> &DynComponent? {
  None
}

///|
/// The empty answer to `persist` — "I do not persist", which is a decision
/// rather than a failure (see the trait).
pub fn no_bytes() -> FixedArray[Byte] {
  FixedArray::make(0, b'\x00')
}

///|
/// A guest that persists as TEXT (JSON, most often) writes it with this and
/// reads it back with `text_of`. UTF-8 both ways, because bytes that cross a
/// contract need an encoding named somewhere and this is the only place both
/// sides can see it.
pub fn bytes_of(text : String) -> FixedArray[Byte] {
  let bs = @utf8.encode(text)
  FixedArray::makei(bs.length(), i => bs[i])
}

///|
/// The inverse of `bytes_of`. "" for bytes that are not UTF-8, which a
/// `restore` reads as "refuse this".
pub fn text_of(state : FixedArray[Byte]) -> String {
  @utf8.decode(Bytes::from_array(state)) catch {
    _ => ""
  }
}

///|
pub(all) struct DynModule {
  components : Array[ComponentFactory]
  /// Intents this bundle SERVES on its own scope (the static manifest lists
  /// their names under `serves`). Module-scoped, because a service belongs to
  /// the bundle rather than to any one instance; the default answers
  /// "no such service".
  serve : (String, Array[@values.Value]) -> ServeResult
}

///|
/// A module that serves no intents of its own — the shape most guests want.
pub fn module_def(
  components : Array[ComponentFactory],
  serve? : (String, Array[@values.Value]) -> ServeResult = no_serves,
) -> DynModule {
  { components, serve }
}

///|
/// Implemented by the component author in this package — the sibling component
/// source, and the one file a guest author writes.
declare fn dyn_module() -> DynModule

///|
let module_ : DynModule = dyn_module()

///|
let states : Map[Int, &DynComponent] = Map([])

///|
let next_rep : Ref[Int] = { val: 0 }

///|
fn alloc(state : &DynComponent) -> Instance {
  let rep = next_rep.val
  next_rep.val = rep + 1
  states[rep] = state
  Instance::new(rep)
}

///|
fn state_of(inst : Instance) -> &DynComponent {
  let Instance(rep) = inst
  states.get(rep).unwrap()
}

// --- implementations of the generated declares ---

///|
/// `DynModule::serve` for a bundle that declares no `serves` of its own.
fn no_serves(name : String, _args : Array[@values.Value]) -> ServeResult {
  ServeResult::Err(@values.Value::Text("no such service: \{name}"))
}

///|
/// Serve an intent the bundle declared (WIT `serve-intent`).
pub fn serve_intent(name : String, args : Array[@values.Value]) -> ServeResult {
  (module_.serve)(name, args)
}

///|
pub fn Instance::instance(
  component : String,
  args : Array[(String, @values.Value)],
) -> Instance {
  for c in module_.components {
    if c.name == component {
      return alloc((c.make)(args))
    }
  }
  abort("tutuca:component guest: unknown component \{component}")
}

///|
pub fn Instance::dtor(self : Instance) -> Unit {
  let Instance(rep) = self
  states.remove(rep) |> ignore
}

///|
pub fn Instance::get_field(self : Instance, name : String) -> @values.Value? {
  state_of(self).get_field(name)
}

///|
pub fn Instance::handle_event(
  self : Instance,
  b : Bucket,
  name : String,
  args : Array[@values.Value],
) -> EventResult {
  match state_of(self).handle(b, name, args) {
    Unhandled => EventResult::Unhandled
    Unchanged => EventResult::Unchanged
    Changed(next) => EventResult::Changed(alloc(next))
  }
}

///|
pub fn Instance::call_method(
  self : Instance,
  name : String,
  args : Array[@values.Value],
) -> @values.Value {
  state_of(self).call_method(name, args)
}

///|
pub fn Instance::with_field(
  self : Instance,
  name : String,
  v : @values.Value,
) -> Instance? {
  match state_of(self).with_field(name, v) {
    Some(next) => Some(alloc(next))
    None => None
  }
}

///|
pub fn Instance::persist(self : Instance) -> FixedArray[Byte] {
  state_of(self).persist()
}

///|
/// Static, because there is no instance yet: the host hands over the component
/// name and the bytes it stored, and this bundle either rebuilds the instance
/// or says no.
pub fn Instance::restore(
  component : String,
  state : FixedArray[Byte],
) -> Instance? {
  for c in module_.components {
    if c.name == component {
      return match (c.restore)(state) {
        Some(next) => Some(alloc(next))
        None => None
      }
    }
  }
  None
}
