// The App runtime (src/app.js core): compile the registered components, hold
// the transactor, re-render on every root swap (full re-render + vdom morph
// against the previous RenderResult), and dispatch DOM events. Backend
// generic over DomWalk (memdom on wasm-gc tests, BrowserNode via the js
// glue). Re-render is batched (one morph per drained cascade, via the dirty
// flag + on_drained). The JS setTimeout time-slicing scheduler
// (_transactNextBatch, maxRunTimeMs) is exposed here as App::drain_batched:
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
  /// Component render-site cache (JS _rValComp DomCache), persisted across
  /// passes and generation-rolled each render, so a subtree whose instance did
  /// not change is reused instead of rebuilt.
  render_cache : @render.RenderCache
  /// Runs over the freshly built tree, between evaluating anode and diffing
  /// against the last render — the one point where an attribute's VALUE is
  /// concrete and nothing has touched the DOM yet.
  ///
  /// `None` is the trusted case and costs one `if` per render rather than a
  /// check per attribute. A host that loads components it did not write
  /// installs one; see `set_filter` and docs/sanitizer.md.
  mut filter : &@filter.VdomFilter?
}

///|
pub fn[N : @vdom.DomWalk] App::new(
  scope : @component.ComponentStack,
  root_value : @tutuca.Value,
  root_node : N,
  opts : @vdom.RenderOpts[N],
) -> App[N] raise {
  scope.compile_all()
  let tx = @transactor.Transactor::new(root_value, requests=ScopeRequests::{
    comps: scope.comps,
  })
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
    filter: None,
  }
  // Batched re-render (the JS setTimeout-scheduler analogue): swaps only
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
) -> App[N] raise {
  let scope = @component.ComponentStack::new()
  m.register_into(scope)
  guard scope.lookup_component(root) is Some(comp) else {
    fail("mount: no component named '\{root}' in module '\{m.name}'")
  }
  let app = App::new(scope, comp.make(args), root_node, opts)
  app.start()
  app
}

///|
/// Initial render (JS app.start minus listener installation — the backend
/// glue owns that; see event_names()).
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
/// Dispatch a message at the ROOT component and drain (JS app.sendAtRoot).
///
/// Tutuca has no lifecycle: nothing in the framework calls `receive.init`. The
/// HOST decides when — the JS playground does `app.start(); app.sendAtRoot("init")`,
/// which is what makes the `init` handler in docs/examples/request-example.js
/// run. This is that hook.
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
/// The current settled root value. Read-back for state-oriented tests (the
/// tutuca `drive()` return value).
pub fn[N] App::root_value(self : App[N]) -> @tutuca.Value {
  self.transactor.root
}

///|
/// Drive queued transactions in bounded batches, calling `yield_between` after
/// each batch that leaves more work — the port of JS App._transactNextBatch's
/// time-slicing (maxRunTimeMs), count-based instead of clock-based so it runs
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
      return { processed, pending: batch.pending }
    }
    if batch.pending {
      yield_between()
    }
  }
  { processed, pending: false }
}

///|
fn[N : @vdom.DomWalk] App::render_now(self : App[N]) -> Unit {
  self.render_count += 1
  let root_val = self.transactor.root
  let stack = @render.RenderStack::new(root_val, comps=self.scope.comps)
  // Roll the cache to a fresh generation: subtrees reused this pass are
  // promoted, anything untouched falls out after the next one.
  self.render_cache.next_generation()
  let ctx = @render.RenderCtx::new(
    view_resolver=self.scope.comps,
    render_cache=self.render_cache,
  )
  match @render.render_root(root_val, stack, ctx) {
    Some(vdom) => {
      // Between evaluating anode and diffing: the tree is concrete and the DOM
      // is untouched, which is true at no other point in a render.
      if self.filter is Some(f) {
        f.filter_tree(vdom)
      }
      let prev = self.prev
      self.prev = Some(@vdom.render(vdom, self.root_node, self.opts, prev?))
    }
    None => ()
  }
}

///|
/// Install (or clear, with `None`) the filter that runs between building a
/// vdom tree and diffing it.
///
/// Takes effect from the next render. It is not retroactive — a value already
/// in the DOM stays there until something re-renders over it — for the same
/// reason a policy applies at load: retracting what is already on the page is
/// dropping it, not filtering it.
///
/// A filter MUTATES the tree it is given. `@filter.UrlFilter` is the one this
/// repo ships; a host may implement `@filter.VdomFilter` itself.
pub fn[N] App::set_filter(self : App[N], filter : &@filter.VdomFilter?) -> Unit {
  self.filter = filter
}

///|
/// Dispatch one DOM event from its target node; re-render happens through
/// the on_change subscription as transactions drain. Drag events run the
/// drag state machine and never abort on a missing handler; every dispatch
/// while a drag is active carries the dragInfo arg (JS transactInputNow).
pub fn[N : @vdom.DomWalk] App::dispatch(
  self : App[N],
  node : N,
  e : @render.DomEvent,
) -> Bool {
  let e2 : @render.DomEvent = { ..e, drag_info: self.drag_info_value() }
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
    let e3 : @render.DomEvent = { ..e2, drag_info: self.drag_info_value() }
    if !ed.handlers.is_empty() {
      run_handlers(self.transactor, ed, e3, self.scope.comps)
    }
    true
  } else {
    dispatch_event(self.transactor, node, e2, self.root_node, self.scope.comps)
  }
}

///|
/// Every event name any registered view listens to (JS genEventNames) — the
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
