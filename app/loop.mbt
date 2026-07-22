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
  /// RenderOnce memo, persisted across render passes (JS RenderOnceNode's
  /// per-view cache) so constant subtrees are built once for the app's life.
  render_once : Map[Int, @vdom.Vdom]
  /// Component render-site cache (JS _rValComp DomCache), persisted across
  /// passes; generation-rolled each render so unchanged subtrees are reused.
  render_cache : @render.RenderCache
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
    render_once: Map([]),
    render_cache: @render.RenderCache::new(),
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
/// Dispatch a message at the ROOT component and drain (JS app.sendAtRoot).
///
/// Tutuca has no lifecycle: nothing in the framework calls `receive.init`. The
/// HOST decides when — the JS playground does `app.start(); app.sendAtRoot("init")`,
/// which is what makes the `init` handler in docs/examples/request-example.js
/// run. This is that hook.
///
/// Goes through the Receive bucket, like any other send, so `receive.init` is an
/// ordinary handler and not a special case.
pub fn[N] App::send_at_root(
  self : App[N],
  name : String,
  args? : Array[@tutuca.Value] = [],
) -> Unit {
  let _ = self.transactor.push_send(@tutuca.DispatchPath::new(), name, args)
  self.transactor.settle()
}

///|
/// The current settled root value — the transactor's root as a `Value`, or
/// `None` if the root is not a value node. Read-back for state-oriented tests
/// (the tutuca `drive()` return value).
pub fn[N] App::root_value(self : App[N]) -> @tutuca.Value? {
  self.transactor.root.as_value()
}

///|
/// Drive queued transactions in bounded batches, calling `yield_between` after
/// each batch that leaves more work — the port of JS App._transactNextBatch's
/// time-slicing (maxRunTimeMs), count-based instead of clock-based so it runs
/// on every backend. A backend passes a real yield (setTimeout(0) on js) so a
/// large cascade doesn't block the host between renders; the synchronous
/// callers (send_at_root, the on_drained re-render) simply drain fully in one
/// batch. `max_per_batch` bounds transactions processed before each yield.
pub fn[N] App::drain_batched(
  self : App[N],
  max_per_batch~ : Int,
  yield_between : () -> Unit,
) -> Unit {
  while self.transactor.has_pending() {
    self.transactor.settle(max_turns=max_per_batch)
    if self.transactor.has_pending() {
      yield_between()
    }
  }
}

///|
fn[N : @vdom.DomWalk] App::render_now(self : App[N]) -> Unit {
  self.render_count += 1
  guard self.transactor.root.as_value() is Some(root_val) else { return }
  let stack = @render.RenderStack::new(root_val, comps=self.scope.comps)
  // Roll the render cache to a fresh generation: subtrees reused this pass are
  // promoted, anything untouched falls out after the next pass.
  self.render_cache.next_generation()
  let ctx = @render.RenderCtx::new(
    view_resolver=self.scope.comps,
    render_once=self.render_once,
    render_cache=self.render_cache,
  )
  match @render.render_root(root_val, stack, ctx) {
    Some(vdom) => {
      let prev = self.prev
      self.prev = Some(@vdom.render(vdom, self.root_node, self.opts, prev?))
    }
    None => ()
  }
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
  let e2 : @render.DomEvent = {
    name: e.name,
    value: e.value,
    key: e.key,
    key_code: e.key_code,
    alt: e.alt,
    shift: e.shift,
    ctrl_or_cmd: e.ctrl_or_cmd,
    meta: e.meta,
    drag_info: self.drag_info_value(),
  }
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
    let e3 : @render.DomEvent = {
      name: e2.name,
      value: e2.value,
      key: e2.key,
      key_code: e2.key_code,
      alt: e2.alt,
      shift: e2.shift,
      ctrl_or_cmd: e2.ctrl_or_cmd,
      meta: e2.meta,
      drag_info: self.drag_info_value(),
    }
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
