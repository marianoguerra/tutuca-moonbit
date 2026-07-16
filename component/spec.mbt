// Spec for the component layer (src/components.js + the Record/field side of
// src/oo.js): Component definitions with views/buckets/provide/lookup, the
// Value-backed Instance (one hybrid half — typed structs implementing
// @tutuca.Obj are the other), the Components registry, and the lexical
// ComponentStack registration scope. READONLY by convention: types +
// `declare` stubs; implementations in separate files.
//
// Deferred: styles injection (only string compilation ships; the browser
// glue injects), Set/OMap field kinds (no Value cases), LookupInfo
// producer-key memoization, render caching hooks.

///|
/// Field kinds, inferred from defaults (JS classFromData). FComp fields hold
/// a child component instance created through the registration scope.
pub(all) enum FieldKind {
  FBool
  FText
  FInt
  FFloat
  FList
  FMap
  FAny
  FComp(comp~ : String, args~ : Map[String, @tutuca.Value])
  // JS FieldSet / FieldOMap (oo.js). Both are backed by @tutuca.Value::Map —
  // the port models an Immutable Set as a Map keyed by member (membership =
  // key-presence, value Bool(true); see examples/personal_site.mbt ps_set_of)
  // and an OrderedMap as a Map (MoonBit's Map iterates in insertion order).
  // Like FComp, they are declared via explicit constructors (FieldSpec::set /
  // ::omap), not inferred by of_default — a bare Value has no set/omap shape.
  FSet
  FOMap
} derive(Debug)

///|
pub(all) struct FieldSpec {
  kind : FieldKind
  default : @tutuca.Value
} derive(Debug)

///|
/// Infer the field kind from its default value (Null/Fn/Obj => FAny).
declare pub fn FieldSpec::of_default(v : @tutuca.Value) -> FieldSpec

///|
/// A component-typed field: default instance made via the scope at make time.
declare pub fn FieldSpec::comp(
  name : String,
  args? : Map[String, @tutuca.Value],
) -> FieldSpec

///|
/// A Map-backed set field (JS FieldSet): default is the set of `members`.
declare pub fn FieldSpec::set(members? : Array[String]) -> FieldSpec

///|
/// An ordered-map field (JS FieldOMap), backed by @tutuca.Value::Map.
declare pub fn FieldSpec::omap(
  default? : Map[String, @tutuca.Value],
) -> FieldSpec

///|
/// Coerce a write: a value of the matching shape passes through; anything
/// else falls back to the default (the JS warn-and-keep path, silent here).
/// FComp accepts any Obj.
declare pub fn FieldSpec::coerce_or_default(
  self : FieldSpec,
  v : @tutuca.Value,
) -> @tutuca.Value

///|
/// The JS provide Symbol: a per-(component, provide-name) identity used to
/// key dynamic-binding frames.
pub(all) struct ProvideKey {
  comp : Int
  name : String
} derive(Eq, Hash, Debug)

///|
pub(all) struct ProvideInfo {
  name : String
  val : @tutuca.Val
  key : ProvideKey
} derive(Debug)

///|
/// Raw `lookup:` spec entry: source is "Comp.provideName", default an
/// optional field expression parsed with parse_field.
pub(all) struct LookupSpec {
  source : String
  default : String?
} derive(Debug)

///|
/// Memoization state for a LookupInfo's resolved producer provide key (JS
/// LookupInfo._sym: `undefined` = not computed, `null`/symbol once resolved).
/// `Pending` = not computed; `Done(k)` caches the resolution (including a
/// negative `None`), so the scope walk runs at most once per lookup alias.
pub(all) enum ProducerKeyMemo {
  Pending
  Done(ProvideKey?)
} derive(Debug)

///|
pub(all) struct LookupInfo {
  name : String
  comp_name : String
  provide_name : String
  default_val : @tutuca.Val?
  mut producer_key : ProducerKeyMemo
} derive(Debug)

///|
/// Resolve (and memoize) the producer's provide key by walking `scope` for the
/// producer component and its provide entry — JS LookupInfo.getProducerSymbol.
/// Computed once; the scope is stable after compile(). None = unresolved.
pub fn LookupInfo::resolve_producer_key(
  self : LookupInfo,
  scope : ComponentStack?,
) -> ProvideKey? {
  match self.producer_key {
    Done(k) => k
    Pending => {
      let k : ProvideKey? = match scope {
        Some(s) =>
          match s.lookup_component(self.comp_name) {
            Some(producer) =>
              match producer.provide.get(self.provide_name) {
                Some(p) => Some(p.key)
                None => None
              }
            None => None
          }
        None => None
      }
      self.producer_key = Done(k)
      k
    }
  }
}

///|
/// dynBinds: cons list of frames keyed by ProvideKey (JS ObjectFrame chain).
pub(all) struct DynBinds {
  binds : Map[ProvideKey, @tutuca.Value]
  parent : DynBinds?
}

///|
declare pub fn DynBinds::lookup(
  self : DynBinds,
  key : ProvideKey,
) -> @tutuca.Value?

///|
/// anode.js resolveDynProducer result: the producer component id plus its
/// own addressing steps to the provided value (spliced by teleporting).
pub(all) struct DynProducer {
  producer : Int
  steps : Array[@tutuca.Step]
} derive(Debug, Eq)

///|
/// Bucket handler for Value-backed components: explicit self + explicit ctx
/// (JS appends ctx as the last argument); None = no change.
pub type InstanceHandler = (Instance, Array[@tutuca.Value], &@tutuca.Ctx) -> Instance?

///|
/// Methods & alter handlers: pure, self first (JS `this`).
pub type MethodFn = (Instance, Array[@tutuca.Value]) -> @tutuca.Value

///|
/// Scope-registered request handler: root-typed twin of
/// @transactor.RequestHandler (the component package must not depend on the
/// transactor; the app layer adapts).
pub(all) struct RequestFn(
  (Array[@tutuca.Value], (Result[@tutuca.Value, @tutuca.Value]) -> Unit) -> Unit
)

///|
/// A compiled component: views + dispatch buckets + provide/lookup + styles.
/// `id` comes from a process-global counter (JS _compId) — tests must not
/// assert absolute ids.
pub struct Component {
  id : Int
  name : String
  views : Map[String, @anode.View]
  common_style : String
  global_style : String
  fields : Map[String, FieldSpec] // empty for typed-struct components
  input : Map[String, InstanceHandler]
  receive : Map[String, InstanceHandler]
  bubble : Map[String, InstanceHandler]
  response : Map[String, InstanceHandler]
  alter : Map[String, MethodFn]
  methods : Map[String, MethodFn] // user methods + generated mutators
  raw_provide : Map[String, String]
  raw_lookup : Map[String, LookupSpec]
  provide : Map[String, ProvideInfo] // filled by compile()
  lookup : Map[String, LookupInfo] // filled by compile()
  mut scope : ComponentStack?
}

///|
/// Define a Value-backed component (JS component({...}) from oo.js).
/// Auto-mutators are generated per field into `methods` (setX / updateX /
/// resetX / toggleX / xLen / pushInX / setInXAt / updateInXAt / deleteInXAt);
/// user-supplied methods win over generated ones.
declare pub fn component(
  name~ : String,
  view~ : String,
  style? : String,
  common_style? : String,
  global_style? : String,
  views? : Map[String, String],
  view_styles? : Map[String, String],
  fields? : Map[String, FieldSpec],
  input? : Map[String, InstanceHandler],
  receive? : Map[String, InstanceHandler],
  bubble? : Map[String, InstanceHandler],
  response? : Map[String, InstanceHandler],
  alter? : Map[String, MethodFn],
  methods? : Map[String, MethodFn],
  provide? : Map[String, String],
  lookup? : Map[String, LookupSpec],
) -> Component

///|
/// Define a component whose instances are a user typed struct implementing
/// @tutuca.Obj (the other hybrid half): views/styles/provide/lookup only —
/// fields, buckets and methods live on the struct itself. The struct's
/// component_id() must return this component's id.
declare pub fn Component::for_type(
  name~ : String,
  view~ : String,
  style? : String,
  views? : Map[String, String],
  provide? : Map[String, String],
  lookup? : Map[String, LookupSpec],
) -> Component

///|
/// Compile every view (stamping data-cid/data-vid, registering nid/eid) with
/// this component's scope for macros, then parse provide/lookup specs.
declare pub fn Component::compile(self : Component) -> Unit raise

///|
/// Build an instance: coerce args against field specs, fill defaults, make
/// FComp defaults through the scope.
declare pub fn Component::make(
  self : Component,
  args : Map[String, @tutuca.Value],
) -> Instance

///|
declare pub fn Component::get_view(
  self : Component,
  name : String?,
) -> @anode.View?

///|
/// [data-cid] commonStyle, globalStyle, and per-view [data-cid][data-vid]
/// blocks (JS compileStyle). String only; injection is app territory.
declare pub fn Component::compile_style(self : Component) -> String

///|
/// A Value-backed component instance: COW fields map + its Component.
pub struct Instance {
  comp : Component
  fields : Map[String, @tutuca.Value]
}

///|
declare pub impl @tutuca.Obj for Instance

///|
/// Coerced field write; unknown names keep the instance unchanged.
declare pub fn Instance::set(
  self : Instance,
  name : String,
  v : @tutuca.Value,
) -> Instance

///|
declare pub fn Instance::get(self : Instance, name : String) -> @tutuca.Value

///|
declare pub fn Instance::to_value(self : Instance) -> @tutuca.Value

///|
/// The component registry (JS Components): id → Component plus the
/// value → component association via Obj::component_id.
pub struct Components {
  by_id : Map[Int, Component]
}

///|
declare pub fn Components::new() -> Components

///|
declare pub fn Components::register(self : Components, comp : Component) -> Unit

///|
declare pub fn Components::get_component_for_id(
  self : Components,
  id : Int,
) -> Component?

///|
declare pub fn Components::get_comp_for(
  self : Components,
  v : @tutuca.Value,
) -> Component?

///|
declare pub fn Components::compile_styles(self : Components) -> String

///|
/// Sorted class names the compiled views can show, for a margaui scanner
/// (JS collectAppClassesInSet). tutuca collects; margaui compiles.
declare pub fn Components::collect_classes(self : Components) -> Array[String]

///|
/// Lexical registration scope tree (JS ComponentStack): components, macros
/// and request handlers resolve through the parent chain; every registered
/// component gets a FRESH child scope so siblings' registrations stay
/// invisible to each other.
pub struct ComponentStack {
  comps : Components
  parent : ComponentStack?
  by_name : Map[String, Component]
  reqs : Map[String, RequestFn]
  macros : Map[String, @anode.Macro]
}

///|
declare pub fn ComponentStack::new(comps? : Components) -> ComponentStack

///|
declare pub fn ComponentStack::enter(self : ComponentStack) -> ComponentStack

///|
/// Register components in this scope: each gets scope = self.enter(), an id
/// slot in the registry, and a by_name entry. `aliases` maps alias → the
/// registered component's name. Does NOT compile (macros may be registered
/// after); call compile_all() when registration is done.
declare pub fn ComponentStack::register_components(
  self : ComponentStack,
  comps : Array[Component],
  aliases? : Map[String, String],
) -> Unit

///|
declare pub fn ComponentStack::register_macros(
  self : ComponentStack,
  macros : Map[String, @anode.Macro],
) -> Unit

///|
declare pub fn ComponentStack::register_request_handlers(
  self : ComponentStack,
  handlers : Map[String, RequestFn],
) -> Unit

///|
declare pub fn ComponentStack::lookup_component(
  self : ComponentStack,
  name : String,
) -> Component?

///|
declare pub fn ComponentStack::lookup_request(
  self : ComponentStack,
  name : String,
) -> RequestFn?

///|
declare pub impl @anode.MacroScope for ComponentStack

///|
/// Compile every registered component (call after ALL registration).
declare pub fn ComponentStack::compile_all(self : ComponentStack) -> Unit raise

///|
/// anode.js resolveDynProducer: which component produces `*name` for `comp`
/// — through its lookup: entry (alias) or its own provide: — plus the
/// producer's addressing steps to the value.
declare pub fn resolve_dyn_producer(
  comp : Component,
  name : String,
) -> DynProducer?

///|
/// One renderable example (the JS getExamples() Section item): make `args`
/// for `component`, rendered under `view` (None = default view resolution).
pub(all) struct ExampleDef {
  component : String
  title : String
  args : Map[String, @tutuca.Value]
  view : String?
}

///|
/// The module-shape convention (the port of the JS getComponents()/
/// getExamples() ES-module contract): a native binary cannot load user code,
/// so a "module" is a VALUE user projects build programmatically and hand to
/// tooling (e.g. @cli.plan_with_module). getTests() joins with the test
/// runner port.
pub(all) struct ModuleDef {
  name : String
  components : Array[Component]
  macros : Map[String, @anode.Macro]
  requests : Map[String, RequestFn]
  examples : Array[ExampleDef]
}

///|
declare pub fn ModuleDef::new(
  name~ : String,
  components~ : Array[Component],
  macros? : Map[String, @anode.Macro],
  requests? : Map[String, RequestFn],
  examples? : Array[ExampleDef],
) -> ModuleDef

///|
/// Registration half of build_scope (no compile), for callers whose boot
/// compiles later (App::new).
declare pub fn ModuleDef::register_into(
  self : ModuleDef,
  scope : ComponentStack,
) -> Unit

///|
/// Register macros, request handlers and components in a fresh scope and
/// compile everything — the boot sequence tooling and apps share.
declare pub fn ModuleDef::build_scope(self : ModuleDef) -> ComponentStack raise
