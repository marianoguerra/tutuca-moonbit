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
//  - Event wiring, §Comp§/§Each§/§Scope§ meta comments, @loop-with iterData
//    — deferred (see Non-goals in render-plan.md).

///|
/// The render stack: the current item (fields/methods/handlers
/// resolve against it, per frame — instances via the Obj trait, plain maps
/// as the component-less fallback), one `@name` binds frame per enter(), the
/// `@push-view` trail, and the dynamic-binding chain published by component
/// frames.
pub(all) struct RenderStack {
  /// The current app state root; lexical paths are absolute from here.
  root : @tutuca.Value
  it : @tutuca.Value
  binds : Map[String, @tutuca.Value]
  parent : RenderStack?
  view_names : Array[String]
  /// Frame barrier: a component boundary is a clean
  /// namespace — an `@name` lookup that misses here STOPS instead of walking
  /// to the parent frame. Scopes (@each items, @enrich-with) are transparent.
  is_frame : Bool
  /// Component registry; None = component-less mode.
  comps : @component.Components?
  /// Provide frames, consed by component-frame enters.
  dyn_binds : @component.DynBinds?
  /// The current render continuation. Its active transaction path is where
  /// this component value lives; saved frames are its visual callers.
  render_path : @tutuca.DispatchPath
  /// A transparent item/scope crossed into a located path. The next component
  /// boundary must emit the active frame base, then clear this flag.
  pending_frame : Bool
  /// The DOM event being dispatched, when this stack evaluates handler args
  /// (the InputEvent as the stack's ctx). Bare names that miss the binds
  /// chain resolve against it (value/key/isCtrl/…).
  event : DomEvent?
  /// Which rule an `e.<path>` handler argument resolves under — see
  /// `@eventpath.EventPathProfile`. Open (the default) for an app rendering
  /// its own views; the dyncomp host hands its apps `Safe`, which is what
  /// makes the resolver refuse past the allowlist even though nothing at the
  /// call site did.
  event_paths : @eventpath.EventPathProfile
}

///|
/// A dispatched DOM event, backend-agnostically extracted:
/// `value` — checkbox→Bool,
/// CustomEvent→detail, else target.value — captured at construction by the
/// backend glue. `ctrl_or_cmd` is (mac && metaKey) ||
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
  /// by the app while a drag is in flight; the `dragInfo` handler arg, and
  /// the three narrow ones read off it (`dragKey`/`dragValue`/`dragType`).
  drag_info : @tutuca.Value
  /// Layer 2: read an ALREADY-PERMITTED path off the live event.
  ///
  /// A `DomEvent` is a snapshot of a few fixed fields, and an `e.` path can
  /// name anything the specifications give an event — so the glue that built
  /// this supplies a closure that reads the real object. The js and the
  /// wasm-gc backends each have one; a `DomEvent` built by a test has none,
  /// and a path through it answers `Null`, which is what a path that does not
  /// resolve answers anyway.
  ///
  /// The ALLOWLIST IS NOT ITS JOB. `event_path` in `dom_event.mbt` checks the
  /// path under the caller's profile before calling this, so a resolver only
  /// ever sees a walk that was already permitted — one place decides, and a
  /// backend cannot forget to ask.
  read_path : EventPathReader?
  /// Call `preventDefault()` on the live event — the `+prevent` modifier.
  ///
  /// Like `read_path`, this reaches the REAL event object through a closure
  /// the glue that built this supplies; a `DomEvent` built by a test has
  /// none, and the effect is then a no-op rather than a crash.
  prevent_default : EventEffect?
  /// Call `stopPropagation()` on the live event — the `+stop` modifier.
  stop_propagation : EventEffect?
} derive(Debug)

///|
/// One live-event side effect, as a named type.
///
/// A newtype for the same reason `EventPathReader` is: `DomEvent` derives
/// `Debug` and a function has none.
pub(all) struct EventEffect(() -> Unit)

///|
pub impl @debug.Debug for EventEffect with fn to_repr(_self) {
  @debug.Repr::Repr("<effect>")
}

///|
/// Layer 2's resolver, as a named type.
///
/// A newtype rather than a bare closure because `DomEvent` derives `Debug` and
/// a function has none. Printing it as `<reader>` is the honest answer: what a
/// reader DOES is read the live DOM, and there is nothing about it a snapshot
/// could show.
pub(all) struct EventPathReader((Array[String]) -> @tutuca.Value)

///|
pub impl @debug.Debug for EventPathReader with fn to_repr(_self) {
  @debug.Repr::Repr("<reader>")
}

///|
declare pub fn DomEvent::new(
  name~ : String,
  value? : @tutuca.Value,
  read_path? : EventPathReader,
  key? : String,
  key_code? : Int,
  alt? : Bool,
  shift? : Bool,
  ctrl_or_cmd? : Bool,
  meta? : Bool,
  drag_info? : @tutuca.Value,
  prevent_default? : EventEffect,
  stop_propagation? : EventEffect,
) -> DomEvent

///|
/// Coerce the browser value for a checked `@bind`. `None` means the edit is
/// invalid and the synthesized setter must not be dispatched.
declare pub fn DomEvent::bind_value(
  self : DomEvent,
  coercion : @anode.BindCoercion,
) -> @tutuca.Value?

///|
/// Root frame on the rendered value (publishes its provides when a registry
/// is present). `event` attaches the DOM event whose handler args this stack
/// will evaluate. `event_paths` says which rule an `e.<path>` argument
/// resolves under — Open unless a host that renders guest-supplied views says
/// otherwise.
declare pub fn RenderStack::new(
  it : @tutuca.Value,
  binds? : Map[String, @tutuca.Value],
  comps? : @component.Components,
  event? : DomEvent,
  event_paths? : @eventpath.EventPathProfile,
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
  render_path? : @tutuca.DispatchPath,
  pending_frame? : Bool,
) -> RenderStack

///|
/// Resolve `*name` to both its value and absolute state path: nearest runtime
/// provide, then nearest lexical registered path, then an addressable default.
declare pub fn RenderStack::lookup_dynamic_located(
  self : RenderStack,
  name : String,
) -> @component.LocatedValue?

///|
declare pub fn RenderStack::push_view_name(
  self : RenderStack,
  name : String,
) -> RenderStack

///|
/// Value lookups against the binds chain / current item; lookup_dynamic
/// walks the provide frames.
declare pub impl @tutuca.Stack for RenderStack

///|
/// A resolved render site: the view's root node plus the component identity
/// baked into the §Comp§ boundary meta (cid) and the effective view name
/// (vid) — the effective view name of the matched Component/View pair.
pub(all) struct ResolvedView {
  node : @anode.ANode
  cid : Int
  vid : String
} derive(Debug)

///|
/// `<x render>`/`<x render-it>`'s component and view resolution. Receives
/// the candidate view names in priority order (the `as=` selector alone, or
/// the `@push-view` trail innermost-first) and the value
/// being rendered; resolvers fall back to "main" and return None to suppress
/// the site (a hidden component matches nothing).
/// Implemented by @component.Components in production.
pub(open) trait ViewResolver {
  fn resolve_view(Self, Array[String], @tutuca.Value) -> ResolvedView?
}

///|
/// Per-render context.
///
/// ONE memo, and it is optional. This one is a field, and `None` renders
/// exactly as the uncached port did.
pub(all) struct RenderCtx {
  view_resolver : &ViewResolver
  /// Component render-site cache. None = uncached; the App supplies one persisted across passes.
  render_cache : RenderCache?
  /// The sanitizing filter, applied to each element as it is CONSTRUCTED.
  ///
  /// It lives here rather than being applied to the finished tree because of
  /// the cache above: a cached site hands back the same `Vdom` object, and
  /// `@vdom`'s morph then short-circuits it by physical identity. A filter over
  /// the finished tree re-walks every one of those on every render for no
  /// result — O(whole tree) work beside a pipeline that is otherwise
  /// O(changed).
  ///
  /// Hooked to construction rather than to a traversal of what was rebuilt,
  /// because there is no subtree to traverse: `@vdom.fragment` flattens nested
  /// fragments (`normalize_childs`), so a nested component's `§Comp§` boundary
  /// is spliced inline into its parent's children and there is nothing left to
  /// stop at. `render` builds an element in exactly one place, so filtering
  /// there is both exactly-once and free of any walk at all.
  ///
  /// The App owns installing it. `None` renders exactly as it did before the
  /// filter existed.
  filter : &@filter.VdomFilter?
}

///|
declare pub fn RenderCtx::new(
  view_resolver? : &ViewResolver,
  render_cache? : RenderCache,
  filter? : &@filter.VdomFilter,
) -> RenderCtx

///|
/// A `§{json}§` boundary marker parsed from / emitted into a comment node.
/// Comp marks a component boundary (nid = render-site node id in the PARENT
/// view, None at the app root); Each marks one keyed iteration entry; Scope
/// marks a loop-less @enrich-with subtree. One type shared by emission
/// (renderer) and parsing (event-path reconstruction) so they cannot drift.
pub(all) enum Meta {
  Comp(nid~ : Int?, cid~ : Int, vid~ : String, base~ : @tutuca.Path?)
  Each(nid~ : Int, key~ : @tutuca.PathKey)
  Scope(nid~ : Int)
} derive(Debug, Eq)

///|
declare pub fn Meta::to_comment_text(self : Meta) -> String

///|
/// Parse a comment's character data; None when it is not a §…§ meta.
declare pub fn Meta::parse(text : String) -> Meta?

///|
/// Encode/decode the address stored on fragment-root siblings of a resumed
/// component. The comment meta uses the same representation.
declare fn render_path_text(path : @tutuca.Path) -> String

///|
declare fn parse_render_path_text(text : String) -> @tutuca.Path?

///|
/// Render a value as the app root component: resolve its view, emit the root §Comp§ boundary
/// meta, render the body. None when unresolved or the body renders nothing.
///
/// `view~` names which view to render the root under; "" is the ordinary
/// resolution, and a name the component does not declare falls back to `main`.
declare pub fn render_root(
  value : @tutuca.Value,
  stack : RenderStack,
  ctx : RenderCtx,
  view? : String = "",
) -> @vdom.Vdom?

///|
/// Render a parsed node. None = suppressed subtree (a hidden @show/
/// @hide or an unresolvable render site inside a fragment simply drops out).
declare pub fn render(
  node : @anode.ANode,
  stack : RenderStack,
  ctx : RenderCtx,
) -> @vdom.Vdom?

///|
/// A copy of a rendered tree without §…§ metas or internal data-* stamps
/// — for headless/snapshot output. None when
/// the node itself is a meta comment.
declare pub fn clean_vdom(v : @vdom.Vdom) -> @vdom.Vdom?

///|
/// Whether `name` is one of the renderer's own bookkeeping attributes rather
/// than something a view wrote.
///
/// Public because `clean_vdom` is not the only place a tree gets cleaned: a
/// headless driver holds a serialized DOM rather than a `Vdom`, and the whole
/// point of this predicate is that the list lives in ONE place. A second copy
/// of it somewhere else is a stamp that stops being stripped the day a new one
/// is added here.
declare pub fn is_internal_attr(name : String) -> Bool

///|
/// Whether a comment is one of the renderer's `§…§` boundary markers. The
/// other half of the pair above, and public for the same reason.
declare pub fn is_meta_comment(text : String) -> Bool

// ---------------------------------------------------------------------------
// Event-path reconstruction: walk up from an
// event target reading §…§ metas and data-* stamps, crossing component
// boundaries, resolving one path step per crossed component. A resumed render
// site carries its absolute base in the boundary metadata; reconstruction
// pushes that base as a new dispatch frame.

///|
/// Registry seam for reconstruction: resolve a compiled view's parse node /
/// event registrations by (cid, vid, nid|eid). Defaults answer None so test
/// mocks implement only what they use.
pub(open) trait Boundaries {
  fn node_for(Self, cid : Int, vid : String, nid : Int) -> @anode.ANode? = _
  fn events_for(Self, cid : Int, vid : String, eid : Int) -> @anode.NodeEvents? = _
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
/// A reconstructed event: the dispatch path (one Plain step per crossed
/// component, frame-only steps included for stack rebuild) and the handlers
/// registered for the event name on the innermost element that carried
/// data-eid. None = no handler on the leaf component.
pub(all) struct EventDispatch {
  path : @tutuca.DispatchPath
  handlers : Array[@anode.NodeEvent]
}

///|
/// Walk up from `node` to `root_node` reconstructing the event path.
/// `stop_on_no_event=false` keeps walking even
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
/// Rebuild the evaluation stack a rendered path described:
/// walk the steps entering the EXACT same frames the
/// renderer pushed — one Step kind per render context (component steps are
/// barriers; Bind/Scope/EachBind replay transparent scopes with lazily
/// evaluated binds; EachRenderItStep pushes the item scope then the
/// component frame). Call on one ordinary transaction path; use
/// `build_dispatch_stack` when continuation frames must be retained.
/// None when a step no longer resolves against the stack's values.
declare pub fn build_stack(
  path : @tutuca.Path,
  stack : RenderStack,
) -> RenderStack?

///|
/// Rebuild every frame of a dispatch path. A resumed frame begins at its
/// app-root-relative base while retaining the visual caller as its parent, so
/// dynamic bindings still follow render ancestry.
declare pub fn build_dispatch_stack(
  path : @tutuca.DispatchPath,
  stack : RenderStack,
) -> RenderStack?

// NOTE: truthiness and `${v}` display moved to the value layer as
// @tutuca.Value::is_truthy / @tutuca.Value::to_display_string.
