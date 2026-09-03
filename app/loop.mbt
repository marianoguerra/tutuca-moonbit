// The App runtime: compile the registered components, hold
// the transactor, re-render on every root swap (full re-render + vdom morph
// against the previous RenderResult), and dispatch DOM events. Backend
// generic over DomWalk (memdom on wasm-gc tests, BrowserNode via the js
// glue). Re-render is batched (one morph per drained cascade, via the dirty
// flag + on_drained). Time-sliced draining is exposed here as
// App::drain_batched:
// the pure layer is clock-free, so a backend supplies the yield (setTimeout on
// js); the default synchronous drain is drain_batched with a no-op yield.

///|
pub struct App[N] {
  scope : @component.ComponentStack
  transactor : @transactor.Transactor
  root_node : N
  opts : @vdom.RenderOpts[N]
  mut prev : @vdom.RenderResult[N]?
  /// state changed since the last render (batching flag)
  mut dirty : Bool
  /// renders performed (tests/diagnostics)
  mut render_count : Int
  /// live drag capture (dragstart .. dragend)
  mut drag : DragState[N]?
  /// the element currently carrying data-draggingover
  mut cur_drag_over : N?
  /// Component render-site cache, persisted across
  /// passes and generation-rolled each render, so a subtree whose instance did
  /// not change is reused instead of rebuilt.
  render_cache : @render.RenderCache
  /// The policy the built-in chain enforces. `set_sanitizer` replaces it, and
  /// that is the only thing a host can say about the built-in rules — see
  /// `set_sanitizer` for why the seam is a policy and not a filter.
  mut sanitizer : @sanitize.Sanitizer
  /// Which rule an `e.<path>` handler argument resolves under — see
  /// `@eventpath.EventPathProfile`. Open by default: an app's views are its
  /// author's own code. A host rendering guest-supplied views (the dyncomp
  /// bridge does) sets `Safe`, and every dispatch's rebuilt stacks carry it.
  mut event_paths : @eventpath.EventPathProfile
  /// Rules a host added, run after the built-in chain in the order they were
  /// added. Append-only: nothing can be taken out, and nothing can get in FRONT
  /// of the built-in chain.
  extra_filters : Array[&@filter.VdomFilter]
  /// The two above composed — `@mdfilter.filter_for(sanitizer)` with the extras
  /// behind it — rebuilt by `install_filter` whenever either changes.
  ///
  /// Runs over the freshly built tree, between evaluating anode and diffing
  /// against the last render: the one point where an attribute's VALUE is
  /// concrete and nothing has touched the DOM yet.
  ///
  /// Never absent. Every app filters; what an app can change is WHICH policy,
  /// not whether.
  mut filter : &@filter.VdomFilter
  /// Which of the root component's views to mount it under; "" is the ordinary
  /// resolution.
  ///
  /// The mounter's, not the value's. A component's `main` and its `row` hold
  /// the same fields, so nothing in the tree can say which one a host meant —
  /// which is why this is a field on the APP rather than something the root
  /// value could carry. Only the root: every site below it resolves its own
  /// view the way it always has.
  root_view : String
}

///|
/// `intents` replaces the host — the registered handlers an intent's lexical
/// leg asks. It defaults to the scope's own, which is what every ordinary mount
/// wants, and it is a parameter because the host is the one part of a mounted
/// app that is not in the scope: replaying a recording answers from what the
/// host said last time, and a fixture answers from what a test decided. Both
/// are the same substitution, and neither is something the scope can express.
pub fn[N : @vdom.DomWalk] App::new(
  scope : @component.ComponentStack,
  root_value : @tutuca.Value,
  root_node : N,
  opts : @vdom.RenderOpts[N],
  view? : String = "",
  intents? : &@transactor.Intents,
) -> App[N] raise {
  scope.compile_all()
  let tx = @transactor.Transactor::new(
    root_value,
    intents=match intents {
      Some(i) => i
      None => ScopeIntents::{ comps: scope.comps, }
    },
    names=ScopeNames::new(scope.comps),
  )
  let app : App[N] = {
    scope,
    transactor: tx,
    root_node,
    opts,
    prev: None,
    dirty: false,
    render_count: 0,
    drag: None,
    cur_drag_over: None,
    render_cache: @render.RenderCache::new(),
    // Safe by default and safe afterwards: `set_sanitizer` can change what the
    // chain enforces and `add_filter` can add to it, but nothing removes it.
    // `filter_for` under the default sanitizer is `MdFilter` in front of
    // `@filter.Baseline`: the URL and `on*` rules every app has had, plus the
    // one that makes `@setinnermd` render at all (`set_prop` fails closed on
    // its attribute otherwise).
    //
    // The cost is that every app links the vendored markdown parser, because
    // this call constructs the filter unconditionally and nothing about it is
    // dead — there is no escape hatch, and the reason is in `set_sanitizer`.
    sanitizer: @sanitize.Sanitizer::default(),
    event_paths: Open,
    extra_filters: [],
    filter: @mdfilter.default_filter(),
    root_view: view,
  }
  // Batched re-render (the setTimeout-scheduler analogue): swaps only
  // mark dirty; ONE morph runs per drained cascade.
  tx.on_change((_new_root, _old_root) => app.dirty = true)
  tx.on_drained(() => {
    if app.dirty {
      app.dirty = false
      app.render_now()
    }
  })
  app
}

///|
/// The mount sequence every host repeats: build the module's registration
/// scope, make `root` with `args`, mount on `root_node` and start. Raises
/// when the module has no component named `root`. Backend glue (event
/// listeners, style injection) stays with the caller.
pub fn[N : @vdom.DomWalk] App::from_module(
  m : @component.ModuleDef,
  root : String,
  root_node : N,
  opts : @vdom.RenderOpts[N],
  args? : Map[String, @tutuca.Value] = Map([]),
  view? : String = "",
) -> App[N] raise {
  let scope = @component.ComponentStack::new()
  m.register_into(scope)
  guard scope.lookup_component(root) is Some(comp) else {
    fail("mount: no component named '\{root}' in module '\{m.name}'")
  }
  let app = App::new(scope, comp.make(args), root_node, opts, view~)
  app.start()
  app
}

///|
/// Initial render minus listener installation — the backend
/// glue owns that; see event_names().
pub fn[N : @vdom.DomWalk] App::start(self : App[N]) -> Unit {
  self.render_now()
}

///|
/// Let go of everything the app holds, and unsubscribe from the transactor.
/// The app is dead afterwards: do not dispatch or render through it again.
///
/// App::new subscribes to the transactor with closures that capture the app,
/// so App -> transactor -> closure -> App is a reference cycle. The native
/// backend does not reclaim it, so a host that mounts and discards apps grows
/// until it is killed. Mount-once hosts (the browser glue, the storybook)
/// never need this; anything that mounts in a loop does.
///
/// The DOM tree is the backend's to release — App is generic over the node
/// type and cannot walk it from here. memdom hosts pair this with
/// `MemNode::destroy_tree` on the mount container; see @harness.Harness::destroy.
pub fn[N] App::destroy(self : App[N]) -> Unit {
  self.transactor.clear_subscriptions()
  self.prev = None
  self.render_cache.clear()
  self.drag = None
  self.cur_drag_over = None
}

///|
/// Dispatch a message at the ROOT component and drain.
///
/// Tutuca has no lifecycle: nothing in the framework calls `receive.init`. The
/// HOST decides when — this is that hook.
///
/// Goes through the Receive bucket, like any other send, so `receive.init` is an
/// ordinary handler and not a special case. The returned result makes the
/// default 10,000-transaction bound visible to hosts.
pub fn[N] App::send_at_root(
  self : App[N],
  name : String,
  args? : Array[@tutuca.Value] = [],
  max_turns? : Int = 10000,
) -> @transactor.SettleResult {
  let _ = self.transactor.push_send(@tutuca.DispatchPath::new(), name, args)
  self.transactor.settle(max_turns~)
}

///|
/// Write a member at the root, the way a view's `.field = v` writes one.
///
/// The host's door for a WRITE, beside `send_at_root`'s door for a dispatch.
/// The two were one before: a bare `setCount` sent from outside reached the
/// generated setter through a fallback in the dispatch path, so "ask the
/// component to decide" and "say what the field is" were the same call and
/// only the NAME told them apart.
pub fn[N] App::set_at_root(
  self : App[N],
  name : String,
  value : @tutuca.Value,
  max_turns? : Int = 10000,
) -> @transactor.SettleResult {
  ignore(self.transactor.set_member(@tutuca.DispatchPath::new(), name, value))
  self.transactor.settle(max_turns~)
}

///|
/// The current settled root value. Read-back for state-oriented tests (the
/// tutuca `drive()` return value).
pub fn[N] App::root_value(self : App[N]) -> @tutuca.Value {
  self.transactor.root
}

///|
/// Drive queued transactions in bounded batches, calling `yield_between` after
/// each batch that leaves more work — time-slicing,
/// count-based instead of clock-based so it runs
/// on every backend. A backend passes a real yield (setTimeout(0) on js) so a
/// large cascade doesn't block the host between renders; the synchronous
/// callers can pass a no-op yield. `max_per_batch` bounds transactions processed
/// before each yield; a non-positive value reports no progress and leaves the
/// queue pending.
pub fn[N] App::drain_batched(
  self : App[N],
  max_per_batch~ : Int,
  yield_between : () -> Unit,
) -> @transactor.SettleResult {
  let mut processed = 0
  while self.transactor.has_pending() {
    let batch = self.transactor.settle(max_turns=max_per_batch)
    processed += batch.processed
    if batch.processed == 0 {
      return { processed, pending: batch.pending, }
    }
    if batch.pending {
      yield_between()
    }
  }
  { processed, pending: false, }
}

///|
fn[N : @vdom.DomWalk] App::render_now(self : App[N]) -> Unit {
  self.render_count += 1
  let root_val = self.transactor.root
  let stack = @render.RenderStack::new(root_val, comps=self.scope.comps)
  // Roll the cache to a fresh generation: subtrees reused this pass are
  // promoted, anything untouched falls out after the next one.
  self.render_cache.next_generation()
  // The filter goes IN rather than being applied to what comes out: render
  // sanitizes each component subtree as it builds it, so a site the cache
  // returns unchanged is not walked again. See `RenderCtx.filter`.
  let ctx = @render.RenderCtx::new(
    view_resolver=self.scope.comps,
    render_cache=self.render_cache,
    filter=self.filter,
  )
  match @render.render_root(root_val, stack, ctx, view=self.root_view) {
    Some(vdom) => {
      let prev = self.prev
      self.prev = Some(@vdom.render(vdom, self.root_node, self.opts, prev?))
    }
    // The root rendered NOTHING this pass — its view root was omitted by an
    // `@show`/`@hide`, or every site inside a fragment dropped out. The mount
    // point has to follow: leaving the previous tree standing made a hidden
    // component look exactly like a handler that had stopped answering, and
    // the next Some would then morph against a `prev` describing DOM that is
    // no longer what the container holds.
    None =>
      if self.prev is Some(_) {
        @vdom.unmount(self.root_node)
        self.prev = None
      }
  }
}

///|
/// Change the POLICY the render-time rules enforce.
///
/// The seam a host gets, and it is deliberately not "here is my filter".
///
/// ## Why a policy and not a filter
///
/// A filter is opaque — `&VdomFilter` is a trait object, so "is this one at
/// least as strict as the one it replaces" is not a question any code here can
/// ask. An API that takes one can therefore only offer replacement, and
/// replacement includes removal.
///
/// A sanitizer is a VALUE with structure. Narrowing it is a thing a host can
/// write down and `SanitizerConfig::validate` can check, and whatever it says,
/// `@mdfilter.filter_for` puts the same rules around it — which is why the
/// pairing lives in that one function rather than in a host's call sequence
/// (order between the members is load-bearing: a filter that REPLACES a subtree
/// must run before the ones that inspect attributes).
///
/// So: the URL rule and the `on*` rule are not configurable and cannot be
/// removed, because neither has anything to configure — a view has no
/// legitimate `javascript:` URL and no legitimate `onclick`. What a policy
/// decides is names, raw markup and CSS.
///
/// ## What replaced the opt-out
///
/// Three reasons were documented for turning the filter off, and none of them
/// is one now:
///
/// - **a deliberate `javascript:` URL** — gone, and deliberately: it was rare,
///   and the alternative was an API where every app's defense could be removed
///   by one call somebody wrote for one link;
/// - **an all-developer-authored tree** — "hard to promise", as the doc that
///   proposed it said;
/// - **a render loop hot enough that one walk matters** — measured away. The
///   filter now asks the tree which rules could apply before doing anything
///   (`@sinks.SinkHints`), and what is left is inside the noise. See
///   `benchmarks/OPTIMIZATIONS.md` §13.
///
/// A host with a rule of its OWN — something no policy here describes — adds it
/// with `add_filter`, which can only ever remove more.
///
/// ## When it applies
///
/// From the next render. Not retroactive: a value already in the DOM stays
/// until something re-renders over it, for the same reason a dyncomp policy
/// applies at load — retracting what is already on the page is dropping it, not
/// filtering it.
pub fn[N] App::set_sanitizer(
  self : App[N],
  sanitizer : @sanitize.Sanitizer,
) -> Unit {
  self.sanitizer = sanitizer
  self.install_filter()
}

///|
/// Which rule an `e.<path>` handler argument resolves under, from the next
/// dispatch on.
///
/// Open is what an app starts with and what an author of their own views
/// wants: the template is code they wrote, and the same read one line out in
/// JS was never anybody's to gate. `Safe` holds every traversed step of every
/// handler-arg path to `@eventpath`'s allowlist — a path that goes past it
/// answers `Null`, exactly as ALL paths did before profiles existed. It is
/// what a host that renders guest-supplied views sets; the dyncomp bridge
/// applies its policy's answer in `set_app`, so a page never has to.
///
/// Like `set_sanitizer`, this is not retroactive: it governs dispatches, and
/// an event already in flight finishes under the profile it started with.
pub fn[N] App::set_event_paths(
  self : App[N],
  event_paths : @eventpath.EventPathProfile,
) -> Unit {
  self.event_paths = event_paths
}

///|
/// Add a rule of the host's own, run after everything built in.
///
/// The only shape an addition can take, and the reason the whole API is
/// monotone: an appended filter sees a tree the built-in chain has already
/// been over, so it can remove more and can never put back what was removed.
/// There is no `remove_filter` and no way to get in front of the chain.
///
/// What it is for: a rule this repo does not have — a host that refuses a
/// `target` it did not write, or one counting what it renders. What it is NOT
/// for is replacing a built-in rule with a laxer version of itself; that is
/// what the policy is for, and it cannot reach the two rules that have nothing
/// to configure.
///
/// One consequence worth knowing: by the time an addition runs, the built-in
/// rules have already dropped what they drop, so a filter added to "watch for
/// `javascript:` URLs" will never see one. It is behind the defense, not
/// beside it.
pub fn[N] App::add_filter(self : App[N], filter : &@filter.VdomFilter) -> Unit {
  self.extra_filters.push(filter)
  self.install_filter()
}

///|
/// Compose the policy's chain with the host's additions, and start clean.
///
/// **Clears the render cache**, which is not an optimization detail leaking
/// out. Filtering happens where a subtree is BUILT, so a cached subtree carries
/// the verdict of whichever filter was installed when it was built. Keeping
/// those would mean a newly installed rule silently never saw most of the tree
/// — the next render would be hits all the way down. Dropping them costs one
/// full rebuild, on a call a host makes about once.
fn[N] App::install_filter(self : App[N]) -> Unit {
  let built = @mdfilter.filter_for(self.sanitizer)
  self.filter = if self.extra_filters.is_empty() {
    built
  } else {
    // The built-in chain first, always. `Chain` is one traversal for all of
    // them, so an addition costs a call and no extra walk.
    let all : Array[&@filter.VdomFilter] = [built]
    for extra in self.extra_filters {
      all.push(extra)
    }
    @filter.Chain::new(all)
  }
  self.render_cache.clear()
}

///|
/// Everything the installed filter dropped since the last call, and clears its
/// log. Empty when no filter is installed.
///
/// The default filter is one the host never constructed, so this is the only
/// handle on what it removed. By render time there is no author to report to —
/// a dropped value may have come from application state rather than from
/// anyone's template — so "why did my link vanish" is answered here or nowhere.
pub fn[N] App::take_filter_reports(self : App[N]) -> Array[@filter.Dropped] {
  self.filter.take_reports()
}

///|
/// Dispatch one DOM event from its target node; re-render happens through
/// the on_change subscription as transactions drain. Drag events run the
/// drag state machine and never abort on a missing handler; every dispatch
/// while a drag is active carries the dragInfo arg.
pub fn[N : @vdom.DomWalk] App::dispatch(
  self : App[N],
  node : N,
  e : @render.DomEvent,
) -> Bool {
  let e2 : @render.DomEvent = { ..e, drag_info: self.drag_info_value(), }
  if is_drag_event(e.name) {
    guard @render.from_node_and_event_name(
        node,
        e.name,
        self.root_node,
        self.scope.comps,
        stop_on_no_event=false,
      )
      is Some(ed) else {
      return false
    }
    self.handle_drag(node, e.name, ed.path)
    // dragstart just captured: dispatch with the FRESH dragInfo
    let e3 : @render.DomEvent = { ..e2, drag_info: self.drag_info_value(), }
    if !ed.handlers.is_empty() {
      run_handlers(self.transactor, ed, e3, self.scope.comps, self.event_paths)
    }
    true
  } else {
    dispatch_event(
      self.transactor,
      node,
      e2,
      self.root_node,
      self.scope.comps,
      self.event_paths,
    )
  }
}

///|
/// Every event name any registered view listens to — the
/// set the backend glue installs listeners for.
pub fn[N] App::event_names(self : App[N]) -> Array[String] {
  let seen : Map[String, Unit] = Map([])
  for _, comp in self.scope.comps.by_id {
    for _, view in comp.views {
      match view.ctx {
        Some(px) =>
          for ne in px.events {
            for h in ne.handlers {
              seen[h.name] = ()
            }
          }
        None => ()
      }
    }
  }
  let out : Array[String] = []
  for k, _u in seen {
    out.push(k)
  }
  out
}
