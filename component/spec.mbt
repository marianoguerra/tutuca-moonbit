// Spec for the typed-state component layer: Component definitions built from a
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
  protocol_ids : Array[String]
  protocols : Array[@tutuca.ProtocolInfo]
}

///|
/// Coerce a write: a value of the matching shape passes through; anything
/// else falls back to the default (a silent keep-the-default).
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
/// The same table, minus the names that only READ.
///
/// `itemsLen` and `hasInTags` answer a scalar and touch nothing: they are
/// `$`-callables a view writes as `$itemsLen`, not messages. Dispatching one
/// does nothing, and the runtime says so — the receive path takes a generated
/// entry's result only when it is `Obj(_)`, so a reader falls through to
/// `Unhandled`. This is that distinction up front, for a caller deciding what
/// to SEND.
declare pub fn schema_writers(
  schema : SchemaInfo,
) -> Map[String, (FieldBox, Array[@tutuca.Value]) -> @tutuca.Value]

///|
/// A provided VALUE: the name it is published under and the addressable
/// expression that produces it.
///
/// There is no key beside the name any more. A lookup names what it WANTS
/// rather than who provides it, so a frame is keyed by the plain name and the
/// nearest one wins — which is the whole of what makes a provide an injection
/// rather than a wire.
pub(all) struct ProvideInfo {
  name : String
  val : @tutuca.Val
} derive(Debug)

///|
/// Raw `lookup:` entry. A name, and a `default` only when there is one.
///
/// A LIST of these rather than a map, because a lookup no longer names a
/// producer and so has nothing to be keyed BY except its own name. There is no
/// alias: the local name IS the provided name.
pub(all) struct LookupSpec {
  name : String
  default : String?
} derive(Debug)

///|
/// A `lookup` entry as written, with no default. The common case, and the one
/// worth a word rather than a record literal.
pub fn lookup_name(name : String) -> LookupSpec {
  { name, default: None, }
}

///|
/// A `lookup` entry with a fallback expression, used when no producer is above
/// the consumer at render time.
pub fn lookup_or(name : String, default : String) -> LookupSpec {
  { name, default: Some(default), }
}

///|
/// A compiled `lookup` entry: the name wanted, and the expression to fall back
/// on when nothing above provides it.
///
/// Everything that used to be here — the producer's name, the provide's name,
/// and the sticky memo of the scope walk that joined them — went away with the
/// qualified `"Producer.name"` target. A lookup that names only itself has
/// nothing to resolve ahead of time.
pub(all) struct LookupInfo {
  name : String
  default_val : @tutuca.Val?
} derive(Debug)

///|
/// One frame of the dynamic-binding stack: what the component being entered
/// publishes, pushed on entering it and popped with it.
///
/// Two maps and not one, which is where this parts company with the JS it is
/// ported from: there a Class and a value are both "a value" and share an
/// object. Here a component is not a `Value`, so a published TYPE is carried as
/// the component's id — the thing `Components` is already keyed by and
/// `Obj::component_id` already answers. The name rule (`@tutuca.is_type_name`)
/// still partitions the keyspace, so the two maps behave as one frame: a name
/// is looked for in exactly one of them, and nearest-ancestor-wins falls out of
/// frame order for both.
pub(all) struct LocatedValue {
  value : @tutuca.Value
  path : @tutuca.Path
} derive(Debug, Eq)

///|
pub(all) struct DynBinds {
  binds : Map[String, LocatedValue]
  types : Map[String, Int]
  parent : DynBinds?
}

///|
declare pub fn DynBinds::lookup_located(
  self : DynBinds,
  name : String,
) -> LocatedValue?

///|
declare pub fn DynBinds::lookup(
  self : DynBinds,
  name : String,
) -> @tutuca.Value?

///|
declare pub fn DynBinds::lookup_type(self : DynBinds, name : String) -> Int?

///|
/// All effectful dispatches in one enum — the typed-state `update` bucket
/// pattern-matches it like a TEA Msg. The payload is (handler name, args).
///
/// TWO of these, mirroring `@tutuca.HandlerBucket`: `Receive` for an ADDRESSED
/// message, whoever sent it, and `Intent` for a ROUTED one. An arm matches on
/// what the dispatch IS, never on where it came from — a view's `@on` name and
/// a parent's `ctx.send` of that name are the same message and reach the same
/// arm.
/// Debug because a dispatch is what a failing property REPORTS. A generated
/// message sequence that breaks a component is the counterexample, and one
/// that cannot be printed leaves the reader with "a property failed".
pub(all) enum Dispatch {
  Receive(String, Array[@tutuca.Value])
  Intent(String, Array[@tutuca.Value])
} derive(Eq, @debug.Debug)

///|
/// What an `update` arm answers.
///
/// Three cases because the question has three answers, and an `S?` could only
/// spell two of them.
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
/// The typed @loop-with result:
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
/// Scope-registered intent handler: root-typed twin of
/// `@transactor.IntentHandler` (the component package must not depend on the
/// transactor; the app layer adapts).
///
/// It receives an `IntentCall` — carrying `from`, the sender's position, which
/// is what lets a host decide whether this sender may ask — and it may answer
/// `Pass`. `Pass` DECLINES: a handler with nothing to say hands the intent to
/// its parent scope instead of inventing an error to satisfy an obligation to
/// answer. That is the whole of why `lookup_intent` is a walk rather than a
/// lookup — declining only means something if there is somewhere left to go.
pub(all) struct IntentFn(
  (@tutuca.IntentCall, (@tutuca.IntentAnswer) -> Unit) -> Unit
)

///|
/// the typed-state half (S, handlers) erased behind the make closure.
/// `id` comes from a process-global counter — tests must not
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
  /// was stated, and nothing reconstructs it.
  ///
  /// `mut` for ONE reason: `compile()` fills in `inputs` when nothing stated
  /// them, which is the case for a component whose views arrive at runtime
  /// (see `Component::view_handler_names`). Nothing else writes it.
  mut schema : SchemaInfo
  /// The `<script type="tutuca/spec">` block this component was declared in,
  /// as SOURCE. Empty for a component that had none, and for every component
  /// built by hand rather than by `gen-views`.
  ///
  /// The schema beside it is the block's PROJECTION, and the projection is
  /// lossy in the two places a generator needs: a rule reaches it as a name
  /// (`invariants`, `methods`) with no body, and a message reaches it as a
  /// name (`receives`) with no payload. Re-parsing this recovers both — see
  /// `testing/fuzz`, which derives a component's generators from it at
  /// runtime, on whatever backend it is running on.
  ///
  /// The whole block rather than this component's `state` arm: a `struct` or
  /// `enum` in it is file-level, and `@statedef.parse_state` folds those into
  /// every `StateDef` it returns. Read it back by matching `StateDef::component`
  /// against this component's name.
  spec : String
  mut make_fn : (Map[String, @tutuca.Value]) -> @tutuca.Value
  raw_provide : Map[String, String]
  raw_lookup : Array[LookupSpec]
  provide : Map[String, ProvideInfo] // filled by compile()
  /// Component TYPES this component publishes to its subtree, name -> id.
  /// Kept apart from `provide` because a type is not addressable: it can never
  /// be a render target and carries no located value for a `*name` read.
  /// Filled by compile().
  provide_type : Map[String, Int]
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
  get_property? : Map[String, (S) -> @tutuca.Value],
  set_property? : Map[String, (S, @tutuca.Value) -> Update[S]],
  compute? : Map[
    String,
    (S, Array[@tutuca.Value], &@tutuca.Stack) -> @tutuca.Value,
  ],
  swap? : Map[String, (S, Array[@tutuca.Value], &@tutuca.Ctx) -> @tutuca.Value?],
  when? : Map[
    String,
    (S, @tutuca.Value, @tutuca.Value, @tutuca.Value, &@tutuca.Stack) -> Bool,
  ],
  enrich? : Map[
    String,
    (
      S,
      Map[String, @tutuca.Value],
      @tutuca.Value,
      @tutuca.Value,
      @tutuca.Value,
      &@tutuca.Stack,
    ) -> Unit,
  ],
  enrich_scope? : Map[String, (S, &@tutuca.Stack) -> Map[String, @tutuca.Value]],
  loop_with? : Map[String, (S, @tutuca.Value, LoopCtx) -> LoopWith],
  slots? : Map[String, String],
  slot_args? : Map[String, Map[String, @tutuca.Value]],
  provide? : Map[String, String],
  lookup? : Array[LookupSpec],
  spec? : String,
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
/// the two type names and the case list are what the call site passes.
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
  lookup? : Array[LookupSpec],
  make? : (Map[String, @tutuca.Value]) -> @tutuca.Value,
  spec? : String,
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
/// A tagged JSON document back into an instance, resolved through THIS
/// component's registration scope — the same namespace a view resolves a child
/// through, so a document names a component the way a template does.
///
/// None for a component that was never registered: `scope` is filled by
/// `ComponentStack::register_components`, and a `Component` still in hand from
/// `component()` has nowhere to look a name up.
declare pub fn Component::from_json(
  self : Component,
  j : Json,
) -> @tutuca.Value?

///|
/// The inverse. On `Component` for symmetry only — an instance describes
/// itself, so `@tutuca.Value::to_component_json` is the same call.
declare pub fn Component::to_json(self : Component, v : @tutuca.Value) -> Json

///|
declare pub fn Component::get_view(
  self : Component,
  name : String?,
) -> @anode.View?

///|
/// [data-cid] commonStyle, globalStyle, and per-view [data-cid][data-vid]
/// blocks. String only; injection is app territory.
declare pub fn Component::compile_style(self : Component) -> String

///|
/// The component registry: id → Component plus the
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
/// Sorted class names the compiled views can show, for a margaui scanner.
/// tutuca collects; margaui compiles.
declare pub fn Components::collect_classes(self : Components) -> Array[String]

///|
/// Lexical registration scope tree: components, macros
/// and request handlers resolve through the parent chain; every registered
/// component gets a FRESH child scope so siblings' registrations stay
/// invisible to each other.
pub struct ComponentStack {
  comps : Components
  parent : ComponentStack?
  by_name : Map[String, Component]
  paths : Map[String, @tutuca.Path]
  intents : Map[String, Array[IntentFn]]
  macros : Map[String, @anode.Macro]
}

///|
declare pub fn ComponentStack::new(comps? : Components) -> ComponentStack

///|
declare pub fn ComponentStack::enter(self : ComponentStack) -> ComponentStack

///|
/// Register lowercase value names as absolute paths from the mounted app's
/// state root. A later registration in this frame replaces an earlier one.
declare pub fn ComponentStack::register_paths(
  self : ComponentStack,
  paths : Map[String, @tutuca.Path],
) -> Unit

///|
/// The nearest app-root-relative path registered under `name`.
declare pub fn ComponentStack::lookup_path(
  self : ComponentStack,
  name : String,
) -> @tutuca.Path?

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
declare pub fn ComponentStack::lookup_component(
  self : ComponentStack,
  name : String,
) -> Component?

///|
/// Every name registered along this chain, innermost first.
declare pub fn ComponentStack::component_names(
  self : ComponentStack,
) -> Array[String]

///|
/// The name-wiring findings for every component in this scope and the scopes
/// below it: a provide that is not addressable, a published type that is not
/// `"self"`, a lookup with no dynamic provider or lexical path, an
/// uppercase lookup that names no registered component.
///
/// Run after `compile_all`. Half of what it reports is the difference between
/// what was written and what survived compilation, which is exactly why
/// `compile()` drops a bad declaration instead of raising on it.
declare pub fn ComponentStack::check_names(
  self : ComponentStack,
) -> Array[@lint.Finding]

///|
/// A registration scope is where a `$component` name resolves when a document
/// is read back. `describe` answers the declared schema so a tagged object's
/// fields decode BY TYPE; `build` goes through `Component::make`, which is
/// what applies the default-on-absent rule the codec defers to.
declare pub impl @tutuca.ComponentSource for ComponentStack

///|
declare pub fn ComponentStack::register_intent_handlers(
  self : ComponentStack,
  handlers : Map[String, Array[IntentFn]],
) -> Unit

///|
/// Every handler for `name` visible from this scope, innermost frame first.
///
/// A LIST rather than the first match, because `IntentAnswer::Pass` means a
/// declining handler hands the intent to its parent scope: the walk needs every
/// candidate, not just the innermost one. It asks them itself, inside the
/// transaction already running, which is why this returns them rather than
/// taking a continuation.
///
/// A single frame may hold several handlers for one name, and that is not an
/// error: two modules registered into one scope both offering `loadRows` is an
/// ordered pair of candidates, the second reached when the first passes.
declare pub fn ComponentStack::lookup_intent(
  self : ComponentStack,
  name : String,
) -> Array[IntentFn]

///|
declare pub impl @anode.MacroScope for ComponentStack

///|
/// Compile every registered component (call after ALL registration).
declare pub fn ComponentStack::compile_all(self : ComponentStack) -> Unit raise

///|
/// One renderable example (a Section item): make `args`
/// for `component`, rendered under `view` (None = default view resolution).
pub(all) struct ExampleDef {
  component : String
  title : String
  args : Map[String, @tutuca.Value]
  view : String?
}

///|
/// The module-shape convention: a native binary cannot load user code,
/// so a "module" is a VALUE user projects build programmatically and hand to
/// tooling; the test runner joins with getTests()-style test lists.
pub(all) struct ModuleDef {
  name : String
  components : Array[Component]
  /// Lowercase lexical value names, as absolute paths from the mounted root.
  paths : Map[String, @tutuca.Path]
  macros : Map[String, @anode.Macro]
  intents : Map[String, Array[IntentFn]]
  examples : Array[ExampleDef]
}

///|
declare pub fn ModuleDef::new(
  name~ : String,
  components~ : Array[Component],
  paths? : Map[String, @tutuca.Path],
  macros? : Map[String, @anode.Macro],
  intents? : Map[String, Array[IntentFn]],
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
