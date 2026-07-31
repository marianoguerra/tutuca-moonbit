///| MoonBit guest SDK for `tutuca:component` (template file — copy into any
/// guest's generated guest package alongside the wit-bindgen output).
///
/// It implements every `declare` from top.mbt generically over a
/// `DynComponent` trait, so authoring a guest is: one struct per component
/// implementing `DynComponent`, plus one `dyn_module()` returning the
/// module's `ComponentDef`s and factories (see todo.mbt).
///
/// Canonical-ABI asymmetry this SDK hides: `Instance` values RETURNED to the
/// host (constructor, handler successors) must be handles made with
/// `Instance::new(rep)`, but `self`/params RECEIVED in methods and the dtor
/// carry the rep directly — never call `.rep()` on those.

///|
/// One guest component's behavior over opaque native state. Handlers are
/// functional: return the successor state (or None = unchanged). Every
/// method defaults to an empty answer.
///
/// There is no `to_json` and no `eq`: the host projects and compares an
/// instance through the fields the component's `ComponentDef` DECLARES, so a
/// guest states its shape once, in the manifest, instead of implementing the
/// two functions that would restate it.
pub(open) trait DynComponent {
  fn get_field(Self, name : String) -> @values.Value? = _
  fn seq_entries(Self) -> Array[(String, @values.Value)]? = _
  fn handle(Self, bucket : Bucket, name : String, args : Array[@values.Value]) -> &DynComponent? = _
  fn call_method(Self, name : String, args : Array[@values.Value]) -> @values.Value = _
  fn with_field(Self, name : String, v : @values.Value) -> &DynComponent? = _
}

///|
impl DynComponent with fn get_field(_self, _name) {
  None
}

///|
impl DynComponent with fn seq_entries(_self) {
  None
}

///|
impl DynComponent with fn handle(_self, _bucket, _name, _args) {
  None
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
pub(all) struct DynComponentDef {
  def : ComponentDef
  make : (Array[(String, @values.Value)]) -> &DynComponent
}

///|
pub(all) struct DynModule {
  name : String
  components : Array[DynComponentDef]
  /// Requests this bundle SERVES (the names its component-defs list in
  /// `requests`). Module-scoped, because a service belongs to the bundle
  /// rather than to any one instance; the default answers "no such request".
  serve : (String, Array[@values.Value]) -> RequestResult
}

///|
/// Implemented by the component author in this package (todo.mbt here).
declare fn dyn_module() -> DynModule

///|
let module_ : DynModule = dyn_module()

///|
let states : Map[Int, &DynComponent] = {}

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
pub fn get_manifest() -> Manifest {
  {
    api_version: 2,
    module_name: module_.name,
    components: module_.components.map(fn(c) { c.def }),
  }
}

///|
/// `DynModule::serve` for a bundle that declares no `requests` of its own.
fn no_requests(name : String, _args : Array[@values.Value]) -> RequestResult {
  RequestResult::Err(@values.Value::Text("no such request: \{name}"))
}

///|
/// Serve a request the bundle declared (WIT `handle-request`).
pub fn handle_request(
  name : String,
  args : Array[@values.Value],
) -> RequestResult {
  (module_.serve)(name, args)
}

///|
pub fn Instance::instance(
  component : String,
  args : Array[(String, @values.Value)],
) -> Instance {
  for c in module_.components {
    if c.def.name == component {
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
pub fn Instance::seq_entries(
  self : Instance,
) -> Array[(String, @values.Value)]? {
  state_of(self).seq_entries()
}

///|
pub fn Instance::handle_event(
  self : Instance,
  b : Bucket,
  name : String,
  args : Array[@values.Value],
) -> Instance? {
  match state_of(self).handle(b, name, args) {
    Some(next) => Some(alloc(next))
    None => None
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
