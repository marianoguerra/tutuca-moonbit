// Spec for the component-less renderer (see render-plan.md): parse a view
// with @anode, then render it to a @vdom.Vdom against a caller-supplied
// stack — no Comp/scope/App machinery. READONLY by convention: concrete
// public data types plus `declare` stubs; implementations live in separate
// files.
//
// Interface status (render-plan.md "keepers vs temporary"):
//  - @tutuca.Stack (value layer) — KEEPER: the evaluation seam.
//  - RenderStack — KEEPER shape; the lookup internals move to the component
//    layer later.
//  - ViewResolver — TEMPORARY: stands in for component/view lookup
//    (stack.lookupBestView + registry); replaced when components land.
//  - Event wiring, §Comp§/§Each§/§Scope§ meta comments, @loop-with iterData,
//    RenderOnce memoization — deferred (see Non-goals in render-plan.md).

///|
/// The render stack (JS Stack): the current item (fields/methods/handlers
/// resolve against it, per frame — instances via the Obj trait, plain maps
/// as the component-less fallback), one `@name` binds frame per enter(), the
/// `@push-view` trail, and the dynamic-binding chain published by component
/// frames.
pub(all) struct RenderStack {
  it : @tutuca.Value
  binds : Map[String, @tutuca.Value]
  parent : RenderStack?
  view_names : Array[String]
  /// Frame barrier (JS BindFrame.isFrame): a component boundary is a clean
  /// namespace — an `@name` lookup that misses here STOPS instead of walking
  /// to the parent frame. Scopes (@each items, @enrich-with) are transparent.
  is_frame : Bool
  /// Component registry; None = component-less mode (ViewMap/ViewRegistry).
  comps : @component.Components?
  /// Provide frames (JS dynBinds), consed by component-frame enters.
  dyn_binds : @component.DynBinds?
  /// The DOM event being dispatched, when this stack evaluates handler args
  /// (JS: the InputEvent as the stack's ctx). Bare names that miss the binds
  /// chain resolve against it (value/key/isCtrl/…).
  event : DomEvent?
}

///|
/// A dispatched DOM event, backend-agnostically extracted (JS InputEvent's
/// view of the raw event): `value` is JS getValue(e) — checkbox→Bool,
/// CustomEvent→detail, else target.value — captured at construction by the
/// backend glue. `ctrl_or_cmd` is JS isCtrl/isCmd: (mac && metaKey) ||
/// ctrlKey. `drag_info` carries the active DragInfo Obj while a drag is in
/// flight (the `dragInfo` handler arg); `target`/`event` are not exposed.
pub(all) struct DomEvent {
  name : String
  value : @tutuca.Value
  key : String
  key_code : Int
  alt : Bool
  shift : Bool
  ctrl_or_cmd : Bool
  meta : Bool
  /// The active DragInfo (an Obj exposing type/value/lookupBind), injected
  /// by the app while a drag is in flight; the `dragInfo` handler arg.
  drag_info : @tutuca.Value
} derive(Debug)

///|
declare pub fn DomEvent::new(
  name~ : String,
  value? : @tutuca.Value,
  key? : String,
  key_code? : Int,
  alt? : Bool,
  shift? : Bool,
  ctrl_or_cmd? : Bool,
  meta? : Bool,
  drag_info? : @tutuca.Value,
) -> DomEvent

///|
/// Root frame on the rendered value (publishes its provides when a registry
/// is present). `event` attaches the DOM event whose handler args this stack
/// will evaluate.
declare pub fn RenderStack::new(
  it : @tutuca.Value,
  binds? : Map[String, @tutuca.Value],
  comps? : @component.Components,
  event? : DomEvent,
) -> RenderStack

///|
/// New frame with a new current item and `@name` binds (JS
/// stack.enter(it, binds, isFrame)). is_frame defaults to true (component
/// boundary — bind-lookup barrier); pass false for transparent scopes
/// (@each items, @enrich-with).
declare pub fn RenderStack::enter(
  self : RenderStack,
  it : @tutuca.Value,
  binds : Map[String, @tutuca.Value],
  is_frame? : Bool,
) -> RenderStack

///|
declare pub fn RenderStack::push_view_name(
  self : RenderStack,
  name : String,
) -> RenderStack

///|
/// Value lookups against the binds chain / current item; lookup_dynamic
/// walks the provide frames; lookup_type stays at the Null default.
declare pub impl @tutuca.Stack for RenderStack

///|
/// A resolved render site: the view's root node plus the component identity
/// baked into the §Comp§ boundary meta (cid) and the effective view name
/// (vid) — what JS _rValComp reads off the matched Component/View pair.
pub(all) struct ResolvedView {
  node : @anode.ANode
  cid : Int
  vid : String
} derive(Debug)

///|
/// `<x render>`/`<x render-it>`'s component and view resolution. Receives
/// the candidate view names in priority order (the `as=` selector alone, or
/// the `@push-view` trail innermost-first — JS lookupBestView) and the value
/// being rendered; resolvers fall back to "main" and return None to suppress
/// the site (JS renderIt returns null when no component matches).
/// Implemented by ViewMap/ViewRegistry (component-less) and by
/// @component.Components (value → its component's views).
pub(open) trait ViewResolver {
  fn resolve_view(Self, Array[String], @tutuca.Value) -> ResolvedView?
}

///|
/// Name → view-root map for tests and simple embedding. A None view name
/// falls back to the "main" entry (mirroring the JS default view name).
pub(all) struct ViewMap {
  views : Map[String, @anode.ANode]
}

///|
declare pub impl ViewResolver for ViewMap

///|
/// Per-render context (JS Renderer instance state, minus comps). `render_once`
/// memoizes constant subtrees by their RenderOnce marker id (JS memoizes on
/// the RenderOnceNode instance). Hand the SAME map across render passes to get
/// JS's cross-render caching; a fresh map (the default) caches only within one
/// pass. Const subtrees never suppress, so only Some results are stored.
pub(all) struct RenderCtx {
  view_resolver : &ViewResolver
  render_once : Map[Int, @vdom.Vdom]
  /// Component render-site cache (JS _rValComp DomCache). None = uncached (the
  /// JS NullDomCache); the App supplies one persisted across passes.
  render_cache : RenderCache?
}

///|
declare pub fn RenderCtx::new(
  view_resolver? : &ViewResolver,
  render_once? : Map[Int, @vdom.Vdom],
  render_cache? : RenderCache,
) -> RenderCtx

///|
/// A `§{json}§` boundary marker parsed from / emitted into a comment node.
/// Comp marks a component boundary (nid = render-site node id in the PARENT
/// view, None at the app root); Each marks one keyed iteration entry; Scope
/// marks a loop-less @enrich-with subtree. One type shared by emission
/// (renderer) and parsing (event-path reconstruction) so they cannot drift.
pub(all) enum Meta {
  Comp(nid~ : Int?, cid~ : Int, vid~ : String)
  Each(nid~ : Int, key~ : @tutuca.PathKey)
  Scope(nid~ : Int)
} derive(Debug, Eq)

///|
declare pub fn Meta::to_comment_text(self : Meta) -> String

///|
/// Parse a comment's character data; None when it is not a §…§ meta.
declare pub fn Meta::parse(text : String) -> Meta?

///|
/// Render a value as the app root component (JS renderRoot → _rValComp with
/// no render-site node): resolve its view, emit the root §Comp§ boundary
/// meta, render the body. None when unresolved or the body renders nothing.
declare pub fn render_root(
  value : @tutuca.Value,
  stack : RenderStack,
  ctx : RenderCtx,
) -> @vdom.Vdom?

///|
/// Render a parsed node. None = suppressed subtree (JS null: a hidden @show/
/// @hide or an unresolvable render site inside a fragment simply drops out).
declare pub fn render(
  node : @anode.ANode,
  stack : RenderStack,
  ctx : RenderCtx,
) -> @vdom.Vdom?

///|
/// Convenience for a compiled View (View::compile ran): render its anode;
/// a suppressed root or uncompiled view yields a placeholder comment.
declare pub fn render_view(
  view : @anode.View,
  stack : RenderStack,
  ctx : RenderCtx,
) -> @vdom.Vdom

///|
/// A copy of a rendered tree without §…§ metas or internal data-* stamps
/// (JS renderToString's cleanup) — for headless/snapshot output. None when
/// the node itself is a meta comment.
declare pub fn clean_vdom(v : @vdom.Vdom) -> @vdom.Vdom?

// ---------------------------------------------------------------------------
// Event-path reconstruction (JS Path.fromNodeAndEventName): walk up from an
// event target reading §…§ metas and data-* stamps, crossing component
// boundaries, resolving one path step per crossed component. Dynamic-var
// (`*dyn`) render targets produce Dyn markers, which the dispatch path
// teleports to the producing component (DispatchPath::to_transaction_path).

///|
/// Registry seam for reconstruction (JS Components.getComponentForId +
/// comp.getNodeForId/getEventForId): resolve a compiled view's parse node /
/// event registrations by (cid, vid, nid|eid). Defaults answer None so test
/// mocks implement only what they use.
pub(open) trait Boundaries {
  fn node_for(Self, cid : Int, vid : String, nid : Int) -> @anode.ANode? = _
  fn events_for(Self, cid : Int, vid : String, eid : Int) -> @anode.NodeEvents? = _
  /// Which component produces `*name` for component `cid`, plus the
  /// producer's addressing steps (anode.js resolveDynProducer). Default None
  /// keeps mocks and component-less registries working — dynamic render
  /// targets then simply contribute no step.
  fn dyn_producer(Self, cid : Int, name : String) -> @component.DynProducer? = _
}

///|
impl Boundaries with fn node_for(_self, _cid, _vid, _nid) {
  None
}

///|
impl Boundaries with fn events_for(_self, _cid, _vid, _eid) {
  None
}

///|
impl Boundaries with fn dyn_producer(_self, _cid, _name) {
  None
}

///|
/// A view compiled under a component id: the render root plus the
/// ParseContext holding its nid/eid registries.
pub(all) struct CompiledView {
  cid : Int
  vid : String
  node : @anode.ANode
  px : @anode.ParseContext
}

///|
/// Name-keyed registry serving BOTH render-time view resolution
/// (ViewResolver) and reconstruction-time boundary lookups (Boundaries), so
/// the cid baked into §Comp§ metas and the cid looked up afterwards cannot
/// disagree. Registration compiles the view (stamping data-cid/data-vid)
/// with the next sequential cid.
pub(all) struct ViewRegistry {
  by_name : Map[String, CompiledView]
}

///|
declare pub fn ViewRegistry::new() -> ViewRegistry

///|
declare pub fn ViewRegistry::add(
  self : ViewRegistry,
  name : String,
  raw_view : String,
) -> Unit raise

///|
declare pub impl ViewResolver for ViewRegistry

///|
declare pub impl Boundaries for ViewRegistry

///|
/// A reconstructed event: the dispatch path (one Plain step per crossed
/// component, frame-only steps included for stack rebuild) and the handlers
/// registered for the event name on the innermost element that carried
/// data-eid. None = no handler on the leaf component (JS NO_EVENT_INFO).
pub(all) struct EventDispatch {
  path : @tutuca.DispatchPath
  handlers : Array[@anode.NodeEvent]
}

///|
/// Walk up from `node` to `root_node` reconstructing the event path (JS
/// Path.fromNodeAndEventName). `stop_on_no_event=false` keeps walking even
/// when the leaf component has no handler (used by two-way binds).
declare pub fn[N : @vdom.DomWalk] from_node_and_event_name(
  node : N,
  event_name : String,
  root_node : N,
  comps : &Boundaries,
  max_depth? : Int,
  stop_on_no_event? : Bool,
) -> EventDispatch?

///|
/// Rebuild the evaluation stack a rendered path described (JS
/// Path.buildStack): walk the steps entering the EXACT same frames the
/// renderer pushed — one Step kind per render context (component steps are
/// barriers; Bind/Scope/EachBind replay transparent scopes with lazily
/// evaluated binds; EachRenderItStep pushes the item scope then the
/// component frame). Call on a transaction path (Dyn steps teleported).
/// None when a step no longer resolves against the stack's values.
declare pub fn build_stack(
  path : @tutuca.Path,
  stack : RenderStack,
) -> RenderStack?

// NOTE: JS truthiness and `${v}` display moved to the value layer as
// @tutuca.Value::is_truthy / @tutuca.Value::to_display_string.
