// Spec for the typed-state component layer (the successor of the JS
// src/components.js + src/oo.js port): Component definitions built from a
// plain state struct S with derive(ToJson, FromJson), one Dispatch enum for
// all effectful buckets, the Components registry, and the lexical
// ComponentStack registration scope. READONLY by convention: types +
// `declare` stubs; implementations in separate files.
//
// Instances are TypedInstance[S] (instance.mbt, package-private): the state
// struct is the source of truth, an encoded fields map serves the render/
// path/Value seams, and encode/decode are generated field by field so
// Obj/Fn values held by S survive the Json round-trip losslessly.

///|
/// The declared-description types live in `@tutuca` now, so that a holder of a
/// bare `Value` can reach them (`Obj::obj_schema`). Re-exported here because
/// `@component.SchemaInfo` is what 143 generated modules and every
/// hand-written descriptor already say.
///
/// One caveat this does NOT cover: an enum CONSTRUCTOR does not resolve
/// through a re-export, so `@component.FBool` is gone — write `@tutuca.FBool`,
/// or bare `FBool` wherever the expected type is known (a `FieldInfo` literal,
/// a `FieldInfo::new` argument).
pub using @tutuca {
  type FieldKind,
  type FieldInfo,
  type SchemaInfo,
  trait Fields,
}

///|
/// A field's runtime handling, DERIVED from the schema — its declared kind and
/// its type's zero. Not `pub` and not a parameter any more: `component()` used
/// to take a `specs~` map that could restate a kind the block had already
/// declared, and could disagree with it.
priv struct FieldSpec {
  kind : FieldKind
  default : @tutuca.Value
}

///|
/// Coerce a write: a value of the matching shape passes through; anything
/// else falls back to the default (the JS warn-and-keep path, silent here).
/// FComp accepts any Obj.
declare fn FieldSpec::coerce_or_default(
  self : FieldSpec,
  v : @tutuca.Value,
) -> @tutuca.Value

///|
/// The three things a generated mutator needs of the instance it runs on: read
/// a field, write one (answering with the SUCCESSOR as a Value), and name the
/// instance itself for the no-op paths.
///
/// It exists so `setX` / `toggleX` / `pushInX` / … are written once for every
/// kind of instance rather than once per implementation. A `TypedInstance`
/// supplies it over its encoded fields; the dynamic-component host supplies it
/// over `Obj::obj_field` / `Obj::obj_with_field`, which is what gives a wasm
/// guest that declares `count: s32` a working `setCount` with no guest code —
/// the same mutators, over the same declared schema, through a different seam.
pub(all) struct FieldBox {
  get : (String) -> @tutuca.Value
  /// The instance one field later. Answering with `value()` is how a write
  /// that changed nothing (or that the instance refused) stays a no-op.
  set : (String, @tutuca.Value) -> @tutuca.Value
  value : () -> @tutuca.Value
}

///|
/// The generated per-field mutators a schema implies, by name — `setCount`,
/// `toggleDone`, `pushInItems`, `itemsLen`, … (the table in
/// skill/tutuca/schema.md). `component()` builds an instance's set from here,
/// and so does any other holder of a declared schema.
declare pub fn schema_mutators(
  schema : SchemaInfo,
) -> Map[String, (FieldBox, Array[@tutuca.Value]) -> @tutuca.Value]

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
/// What an `update` arm answers.
///
/// Three cases because the question has three answers, and an `S?` could only
/// spell two of them. `None` used to mean BOTH "no arm claimed this name" and
/// "my arm ran and chose not to change anything", and the dispatch site could
/// not tell them apart — so an author could not veto a write: an
/// `Input("setTitle", _) => None` fell through to the generated setter and the
/// change landed anyway. `Some(s)` where `s` was the same object was the only
/// way to say "handled, no change", which made `physical_equal` part of the
/// CONTRACT rather than an optimization the transactor happens to make.
///
/// The same three the refusal taxonomy names: nothing claimed it, a rule
/// refused it, nothing changed.
pub(all) enum Update[S] {
  /// No arm claimed this name. Try the next answerer — the generated
  /// mutators, for an `Input`.
  Unhandled
  /// This arm answered, and the state stays exactly as it is. Nothing further
  /// is tried, which is what makes a veto expressible.
  Unchanged
  /// This arm answered; here is the successor.
  Next(S)
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
/// the typed-state half (S, handlers) erased behind the make closure.
/// `id` comes from a process-global counter (JS _compId) — tests must not
/// assert absolute ids.
pub struct Component {
  id : Int
  name : String
  views : Map[String, @anode.View]
  common_style : String
  global_style : String
  priv specs : Map[String, FieldSpec] // empty for for_type components
  // What the AUTHOR wired, which the schema does not know: the schema lists
  // the names the VIEWS use, and these two say which of them this component
  // answered in the swap and alter buckets rather than in `update`. The other
  // three arrays that lived here — compute_names, generated_names, has_update
  // — were recoverable from the schema or read by nothing, and are gone.
  swap_names : Array[String]
  alter_names : Array[String]
  /// What this component DECLARES. Everything above this line is what a
  /// runtime descriptor could recover by reflection; this is the thing that
  /// was stated, and it is no longer optional — there is nothing left that
  /// reconstructs it.
  ///
  /// `mut` for ONE reason: `compile()` fills in `inputs` when nothing stated
  /// them, which is the case for a component whose views arrive at runtime
  /// (see `Component::view_handler_names`). Nothing else writes it.
  mut schema : SchemaInfo
  mut make_fn : (Map[String, @tutuca.Value]) -> @tutuca.Value
  raw_provide : Map[String, String]
  raw_lookup : Map[String, LookupSpec]
  provide : Map[String, ProvideInfo] // filled by compile()
  lookup : Map[String, LookupInfo] // filled by compile()
  mut scope : ComponentStack?
}

///|
/// Define a typed-state component: `init` is a plain struct — no derives —
/// whose fields become the component's fields, compiler-checked in every
/// handler. `update` folds input/receive/bubble/response into one Dispatch
/// match; `compute` answers `$name` in a value position. Render-time
/// directives get their own
/// typed buckets: `when` (@when filters), `enrich` (@enrich-with inside a
/// loop — mutate the binds map), `enrich_scope` (@enrich-with without @each —
/// return the binds), `loop_with` (@loop-with — slice/order the iteration).
/// Generated per-field mutators (setX/updateX/...) stay; user entries win.
/// `specs` declares Value-level slots (FieldSpec::comp children) and
/// FSet/FOMap kind overrides.
///
/// `S` states its own schema and codec through `@tutuca.Fields`. Those were
/// three required PARAMETERS, which meant three lines at every call site
/// restating what the state type already determines — and a state type that
/// could be passed here with somebody else's codec.
declare pub fn[S : @tutuca.Fields] component(
  name~ : String,
  views~ : Map[String, @anode.View],
  init~ : S,
  common_style? : String,
  global_style? : String,
  update? : (S, Dispatch, &@tutuca.Ctx) -> Update[S],
  compute? : Map[String, (S, Array[@tutuca.Value]) -> @tutuca.Value],
  swap? : Map[String, (S, Array[@tutuca.Value], &@tutuca.Ctx) -> @tutuca.Value?],
  when? : Map[String, (S, @tutuca.Value, @tutuca.Value, @tutuca.Value) -> Bool],
  enrich? : Map[
    String,
    (S, Map[String, @tutuca.Value], @tutuca.Value, @tutuca.Value, @tutuca.Value) -> Unit,
  ],
  enrich_scope? : Map[String, (S) -> Map[String, @tutuca.Value]],
  loop_with? : Map[String, (S, @tutuca.Value, LoopCtx) -> LoopWith],
  slots? : Map[String, String],
  slot_args? : Map[String, Map[String, @tutuca.Value]],
  provide? : Map[String, String],
  lookup? : Map[String, LookupSpec],
) -> Component

///|
/// Turn an exhaustive match over a generated handler-name enum into the
/// `Map[String, H]` bucket `component()` takes.
///
/// `all` is every case of the enum, `name` its source spelling, `f` the
/// author's match. A case answered `None` contributes no entry — that is what
/// lets a handler fall through to `update` or to a generated mutator.
///
/// One generic function rather than one generated per component per bucket:
/// `gen-views` used to emit this same 14-line loop 143 times across the corpus,
/// differing only in the two type names and the case list, which the call site
/// can simply pass.
declare pub fn[E, H] build_bucket(
  all : Array[E],
  name : (E) -> String,
  f : (E) -> H?,
) -> Map[String, H]

///|
/// Define a component whose instances are a user typed struct implementing
/// @tutuca.Obj directly (the fully-manual path): views/styles/provide/lookup
/// only — fields and handlers live on the struct itself. The struct's
/// component_id() must return this component's id. make() yields Null.
///
/// `schema` is required here for the same reason it is on `component`: being
/// hand-written is not being under-described. A `fields: []` schema is the
/// right answer when the instances really are opaque (the dyncomp contract),
/// and it still carries the handler channels the caller knows about.
declare pub fn Component::for_type(
  name~ : String,
  views~ : Map[String, @anode.View],
  schema~ : SchemaInfo,
  common_style? : String,
  global_style? : String,
  provide? : Map[String, String],
  lookup? : Map[String, LookupSpec],
  make? : (Map[String, @tutuca.Value]) -> @tutuca.Value,
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
/// tooling. getTests() joins with the test
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

///|
/// Encode a `@loop-with` return into the Map it crosses the `Obj::obj_callable`
/// boundary as; `of_value` reads one back. Both halves live in one file
/// (loop_codec.mbt) so the key names cannot drift apart.
declare pub fn LoopWith::to_value(self : LoopWith) -> @tutuca.Value

///|
/// Read a `@loop-with` return back out, with `seq` supplying the `iter_data`
/// default. Partial coercers throughout: an absent part stays absent.
declare pub fn LoopWith::of_value(
  v : @tutuca.Value,
  seq : @tutuca.Value,
) -> LoopWith

///|
/// Encode the loop context the renderer builds; `of_value` reads it back into
/// the typed form a handler receives.
declare pub fn LoopCtx::to_value(self : LoopCtx) -> @tutuca.Value

///|
declare pub fn LoopCtx::of_value(v : @tutuca.Value) -> LoopCtx
