// Spec for the typed-state component layer (the successor of the JS
// src/components.js + src/oo.js port): Component definitions built from a
// plain state struct S with derive(ToJson, FromJson), one Dispatch enum for
// all effectful buckets, the Components registry, and the lexical
// ComponentStack registration scope. READONLY by convention: types +
// `declare` stubs; implementations in separate files.
//
// Instances are TypedInstance[S] (instance.mbt, package-private): the state
// struct is the source of truth, an encoded fields map serves the render/
// path/Value seams, and encode/decode run inside @tutuca.with_value_stash so
// Obj/Fn values held by S survive the Json round-trip losslessly.

///|
/// Field kinds, inferred from the encoded init state (plus explicit `specs`
/// entries). FComp fields hold a child component instance created through
/// the registration scope; FSet/FOMap override mutator generation for
/// Map-backed set / ordered-map fields.
pub(all) enum FieldKind {
  FBool
  FText
  FInt
  FFloat
  FList
  FMap
  FAny
  FComp(comp~ : String, args~ : Map[String, @tutuca.Value])
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
/// A component-typed slot field: default instance made via the scope at make
/// time.
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
/// All effectful dispatches in one enum — the typed-state `update` bucket
/// pattern-matches it like a TEA Msg. The payload is (handler name, args).
pub(all) enum Dispatch {
  Input(String, Array[@tutuca.Value])
  Receive(String, Array[@tutuca.Value])
  Bubble(String, Array[@tutuca.Value])
  Response(String, Array[@tutuca.Value])
}

///|
/// The typed loopCtx handed to a @loop-with handler: `lookup` reads `@name`
/// binds from the render stack; `filter` applies the loop's own @when to a
/// (key, value, iter_data) triple (true when no @when is present).
pub(all) struct LoopCtx {
  lookup : (String) -> @tutuca.Value
  filter : (@tutuca.Value, @tutuca.Value, @tutuca.Value) -> Bool
}

///|
/// The typed @loop-with result (JS { iterData?, start?, end?, keys? }):
/// iter_data flows to every @when/@enrich-with call, start/end slice the
/// iteration (Array.slice semantics), an explicit keys list takes over
/// ordering entirely (skipping @when).
pub(all) struct LoopWith {
  iter_data : @tutuca.Value?
  start : Int?
  end : Int?
  keys : Array[@tutuca.Value]?
}

///|
declare pub fn LoopWith::new(
  iter_data? : @tutuca.Value,
  start? : Int,
  end? : Int,
  keys? : Array[@tutuca.Value],
) -> LoopWith

///|
/// Scope-registered request handler: root-typed twin of
/// @transactor.RequestHandler (the component package must not depend on the
/// transactor; the app layer adapts).
pub(all) struct RequestFn(
  (Array[@tutuca.Value], (Result[@tutuca.Value, @tutuca.Value]) -> Unit) -> Unit
)

///|
/// A compiled component: views + field specs + provide/lookup + styles, with
/// the typed-state half (S, handlers) erased behind the make closure.
/// `id` comes from a process-global counter (JS _compId) — tests must not
/// assert absolute ids.
pub struct Component {
  id : Int
  name : String
  views : Map[String, @anode.View]
  common_style : String
  global_style : String
  specs : Map[String, FieldSpec] // empty for for_type components
  // introspection metadata (the typed handlers themselves are erased behind
  // make_fn): bucket name lists + whether an update fn exists. update's
  // handled names are unknowable — it is one opaque pattern match.
  mutate_names : Array[String]
  compute_names : Array[String]
  swap_names : Array[String]
  alter_names : Array[String]
  generated_names : Array[String] // the per-field mutators gen_mutators built
  has_update : Bool
  mut make_fn : (Map[String, @tutuca.Value]) -> @tutuca.Value
  raw_provide : Map[String, String]
  raw_lookup : Map[String, LookupSpec]
  provide : Map[String, ProvideInfo] // filled by compile()
  lookup : Map[String, LookupInfo] // filled by compile()
  mut scope : ComponentStack?
}

///|
/// Define a typed-state component: `init` is a plain struct with
/// derive(ToJson, FromJson) — its fields become the component's fields,
/// compiler-checked in every handler. `update` folds input/receive/bubble/
/// response into one Dispatch match; `mutate`/`compute` are the $-callable
/// buckets (state change / value read). Render-time directives get their own
/// typed buckets: `when` (@when filters), `enrich` (@enrich-with inside a
/// loop — mutate the binds map), `enrich_scope` (@enrich-with without @each —
/// return the binds), `loop_with` (@loop-with — slice/order the iteration).
/// Generated per-field mutators (setX/updateX/...) stay; user entries win.
/// `specs` declares Value-level slots (FieldSpec::comp children) and
/// FSet/FOMap kind overrides.
declare pub fn[S : ToJson + @json.FromJson] component(
  name~ : String,
  view~ : String,
  init~ : S,
  style? : String,
  common_style? : String,
  global_style? : String,
  views? : Map[String, String],
  view_styles? : Map[String, String],
  update? : (S, Dispatch, &@tutuca.Ctx) -> S?,
  mutate? : Map[String, (S, Array[@tutuca.Value]) -> S],
  compute? : Map[String, (S, Array[@tutuca.Value]) -> @tutuca.Value],
  swap? : Map[String, (S, Array[@tutuca.Value], &@tutuca.Ctx) -> @tutuca.Value?],
  when? : Map[String, (S, @tutuca.Value, @tutuca.Value, @tutuca.Value) -> Bool],
  enrich? : Map[
    String,
    (S, Map[String, @tutuca.Value], @tutuca.Value, @tutuca.Value, @tutuca.Value) -> Unit,
  ],
  enrich_scope? : Map[String, (S) -> Map[String, @tutuca.Value]],
  loop_with? : Map[String, (S, @tutuca.Value, LoopCtx) -> LoopWith],
  specs? : Map[String, FieldSpec],
  provide? : Map[String, String],
  lookup? : Map[String, LookupSpec],
) -> Component

///|
/// Define a component whose instances are a user typed struct implementing
/// @tutuca.Obj directly (the fully-manual path): views/styles/provide/lookup
/// only — fields and handlers live on the struct itself. The struct's
/// component_id() must return this component's id. make() yields Null.
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
/// Build an instance Value: coerce args against field specs, fill defaults
/// (FComp children made through the scope), decode the typed state.
declare pub fn Component::make(
  self : Component,
  args : Map[String, @tutuca.Value],
) -> @tutuca.Value

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
