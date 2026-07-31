///| MoonBit guest SDK for `tutuca:component` (template file — copy into any
/// guest's generated guest package alongside the wit-bindgen output).
///
/// It implements every `declare` from top.mbt generically over a
/// `DynComponent` trait, so authoring a guest is: one struct per component
/// implementing `DynComponent`, plus one `dyn_module()` returning the
/// module's `ComponentDef`s and factories (see counter.mbt).
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
impl DynComponent with fn persist(_self) {
  no_bytes()
}

///|
pub(all) struct DynComponentDef {
  def : ComponentDef
  make : (Array[(String, @values.Value)]) -> &DynComponent
  /// The inverse of `DynComponent::persist`: bytes this component wrote, back
  /// into state. None REFUSES them — a format this guest no longer reads — and
  /// the host falls back to constructing from the declared fields, which is
  /// also what the default does.
  restore : (FixedArray[Byte]) -> &DynComponent?
}

///|
/// A component of this module: what it declares, how to build one, and (when
/// it persists) how to read its bytes back.
pub fn dyn_comp(
  def : ComponentDef,
  make : (Array[(String, @values.Value)]) -> &DynComponent,
  restore? : (FixedArray[Byte]) -> &DynComponent? = no_restore,
) -> DynComponentDef {
  { def, make, restore }
}

///|
/// `DynComponentDef::restore` for a component that does not persist.
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
  @utf8.decode(Bytes::from_fixedarray(state)) catch {
    _ => ""
  }
}

///|
pub(all) struct DynModule {
  name : String
  components : Array[DynComponentDef]
  /// Requests this bundle SERVES (the names its component-defs list in
  /// `requests`). Module-scoped, because a service belongs to the bundle
  /// rather than to any one instance; the default answers "no such request".
  serve : (String, Array[@values.Value]) -> RequestResult
  /// Catalog metadata, all advisory: the host shows it, nothing resolves
  /// against it, and the bundle's identity is the hash of the archive it
  /// arrived in. Blank is a legal answer for every one of them.
  doc : String
  version : String
  homepage : String
  authors : Array[String]
  /// What this bundle asks the host for. An ungranted capability refuses the
  /// bundle, so ask for what you use and nothing more.
  capabilities : Array[CapabilityReq]
}

///|
/// A module that states no metadata and serves no requests — the shape most
/// guests want, so that `dyn_module()` names only what it actually has.
pub fn module_def(
  name : String,
  components : Array[DynComponentDef],
  serve? : (String, Array[@values.Value]) -> RequestResult = no_requests,
  doc? : String = "",
  version? : String = "",
  homepage? : String = "",
  authors? : Array[String] = [],
  capabilities? : Array[CapabilityReq] = [],
) -> DynModule {
  { name, components, serve, doc, version, homepage, authors, capabilities }
}

///|
/// A declared field. `doc` is the one thing worth spelling out even when the
/// rest is default: it is what a catalog search ranks on and what a model
/// reads before choosing this component.
pub fn field(
  name : String,
  ty : UInt,
  doc? : String = "",
  required? : Bool = false,
  constraint? : Constraint? = None,
) -> FieldDef {
  { name, ty, doc, required, constraint }
}

///|
/// A constraint with nothing set — spread it (`{ ..no_limits(), max: … }`)
/// rather than writing eight blanks.
pub fn no_limits() -> Constraint {
  {
    min: None,
    max: None,
    min_len: None,
    max_len: None,
    pattern: "",
    format: "",
    enum_json: "",
    default_json: "",
  }
}

///|
/// A component that states no catalog metadata beyond its doc. The six
/// message-bucket lists and the type table are the interesting part of a
/// `ComponentDef`; this keeps the four v3 metadata fields from burying them.
pub fn component_def(
  name : String,
  views~ : Array[ViewDef],
  types? : Array[TyDef] = [],
  fields? : Array[FieldDef] = [],
  handlers? : Array[String] = [],
  receives? : Array[String] = [],
  bubbles? : Array[String] = [],
  responses? : Array[String] = [],
  methods? : Array[String] = [],
  whens? : Array[String] = [],
  requests? : Array[String] = [],
  inits? : Array[InitDef] = [],
  style? : String = "",
  doc? : String = "",
  keywords? : Array[String] = [],
  category? : String = "",
  message_docs? : Array[NamedDoc] = [],
) -> ComponentDef {
  {
    name,
    doc,
    keywords,
    category,
    message_docs,
    views,
    types,
    fields,
    handlers,
    receives,
    bubbles,
    responses,
    methods,
    whens,
    requests,
    inits,
    style,
  }
}

///|
/// Implemented by the component author in this package (counter.mbt here).
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
    api_version: 4,
    module_name: module_.name,
    doc: module_.doc,
    version: module_.version,
    homepage: module_.homepage,
    authors: module_.authors,
    capabilities: module_.capabilities,
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
    if c.def.name == component {
      return match (c.restore)(state) {
        Some(next) => Some(alloc(next))
        None => None
      }
    }
  }
  None
}
