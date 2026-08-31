// RenderStack: the @tutuca.Stack implementation over component instances.
// Fields/methods/handlers resolve against the CURRENT item (`it`, per frame):
// Obj instances answer through the Obj trait, plain
// Value::Map keeps the component-less mode working. `@name` binds resolve
// along the frame chain with frame barriers.

///|
pub fn RenderStack::new(
  it : @tutuca.Value,
  binds? : Map[String, @tutuca.Value] = Map([]),
  comps? : @component.Components,
  event? : DomEvent,
  event_paths? : @eventpath.EventPathProfile = Open,
) -> RenderStack {
  let stack : RenderStack = {
    root: it,
    it,
    binds,
    parent: None,
    view_names: [],
    is_frame: true,
    comps,
    dyn_binds: None,
    render_path: @tutuca.DispatchPath::new(),
    pending_frame: false,
    event,
    event_paths,
  }
  stack.push_provides()
}

///|
pub fn RenderStack::enter(
  self : RenderStack,
  it : @tutuca.Value,
  binds : Map[String, @tutuca.Value],
  is_frame? : Bool = true,
  render_path? : @tutuca.DispatchPath,
  pending_frame? : Bool,
) -> RenderStack {
  let stack : RenderStack = {
    ..self,
    it,
    binds,
    parent: Some(self),
    is_frame,
    render_path: render_path.unwrap_or(self.render_path),
    pending_frame: pending_frame.unwrap_or(
      if is_frame {
        false
      } else {
        self.pending_frame
      },
    ),
  }
  // only frames publish provides (JS: enter() calls _pushProvides when
  // isFrame — dynamic vars come from component boundaries, not scopes)
  if is_frame {
    stack.push_provides()
  } else {
    stack
  }
}

///|
/// Evaluate the entered component's provides against the post-enter stack and
/// cons one DynBinds frame. No-op without a registry, a component, or
/// anything to publish.
///
/// Values are EVALUATED here and types are copied: a `provide {Cell: "self"}`
/// is already resolved by `compile()` into the publisher's own id. Both halves
/// go in the one frame, keyed by plain name — see `DynBinds`.
fn RenderStack::push_provides(self : RenderStack) -> RenderStack {
  guard self.comps is Some(comps) else { return self }
  guard comps.get_comp_for(self.it) is Some(comp) else { return self }
  if comp.provide.is_empty() && comp.provide_type.is_empty() {
    return self
  }
  let binds : Map[String, @component.LocatedValue] = Map([])
  let base = self.publish_base()
  for _, p in comp.provide {
    match p.val.to_path_item() {
      Some(step) =>
        binds[p.name] = {
          value: p.val.eval(self),
          path: match base {
            Some(b) => Some(b.concat([step]))
            None => None
          },
        }
      None => () // compile() already drops this shape
    }
  }
  let types : Map[String, Int] = Map([])
  for tname, cid in comp.provide_type {
    types[tname] = cid
  }
  { ..self, dyn_binds: Some({ binds, types, parent: self.dyn_binds, }), }
}

///|
/// The absolute address of the position being rendered, or None when it cannot
/// be written down as one.
///
/// Frame-only steps carry bindings and address nothing, so they are compacted
/// away first; what is left is then CHECKED against the value actually being
/// rendered, because a scope can move the render position without contributing
/// an addressing step. Publishing an address that does not resolve to `it` is
/// worse than publishing none: an unwritable path compacts to the empty one,
/// which addresses the ROOT, so a consumer would silently resume the whole app
/// there and drop every edit made inside it.
fn RenderStack::publish_base(self : RenderStack) -> @tutuca.Path? {
  let base = self.render_path.compact().to_transaction_path()
  match base.lookup(self.root) {
    Some(at) if physical_equal(at, self.it) => Some(base)
    _ => None
  }
}

///|
/// Would entering `value` as a component frame render something that is
/// already rendering? The nearest enclosing FRAME is the test: a component
/// whose own body renders its own value again never terminates, because the
/// second pass reaches the same node with the same value and does it again.
///
/// Scopes are transparent and skipped, which is what keeps the ordinary
/// `@each` + `<x render-it>` shape working: there the entered value is the
/// ITEM and the enclosing frame holds the collection's owner, so the two
/// differ. It is the loop-less `<x render-it>` — the one an author writes by
/// mistake, or is left with when a dropped `@each` was the only thing bounding
/// it — that hits this.
fn RenderStack::would_recurse(
  self : RenderStack,
  value : @tutuca.Value,
) -> Bool {
  if self.is_frame {
    // The bottom frame is the mount itself: `RenderStack::new` opens it on the
    // very value `render_root` then renders, so a match there is the root site
    // standing one frame deeper than every other rather than recursion. A root
    // component that does name itself is still caught on the next pass, one
    // level in and long before the stack is in danger.
    self.parent is Some(_) && physical_equal(self.it, value)
  } else {
    match self.parent {
      Some(p) => p.would_recurse(value)
      None => false
    }
  }
}

///|
pub fn RenderStack::push_view_name(
  self : RenderStack,
  name : String,
) -> RenderStack {
  let view_names = self.view_names.copy()
  view_names.push(name)
  { ..self, view_names, }
}

///|
/// The pushed-view trail, innermost first.
fn RenderStack::view_trail(self : RenderStack) -> Array[String] {
  self.view_names.rev()
}

///|
fn RenderStack::lookup_bind_chain(
  self : RenderStack,
  name : String,
) -> @tutuca.Value {
  match self.binds.get(name) {
    Some(v) => v
    // A frame is a barrier: binds never cross a
    // component boundary. Scopes are transparent and keep walking.
    None =>
      if self.is_frame {
        Null
      } else {
        match self.parent {
          Some(p) => p.lookup_bind_chain(name)
          None => Null
        }
      }
  }
}

///|
/// A bare name resolves against the BIND chain and nothing else.
pub impl @tutuca.Stack for RenderStack with fn lookup_name(self, name) {
  self.lookup_bind_chain(name)
}

///|
/// `e.<segments>`: the two-layer resolve, under this stack's profile, and NOT
/// a name lookup.
///
/// Deliberately not routed through `lookup_name`: an `e.` path names the event
/// outright, so a bind cannot shadow it. That is the point of writing the root,
/// and it is why the root is required.
///
/// The profile rides the root frame (`enter` spreads it forward like every
/// other field), so a host that mounts with `Safe` holds every handler arg to
/// the allowlist without anything at the call site changing.
pub impl @tutuca.Stack for RenderStack with fn lookup_event_path(self, segments) {
  match self.event {
    Some(e) => event_path(e, segments, profile=self.event_paths)
    None => Null
  }
}

///|
pub impl @tutuca.Stack for RenderStack with fn lookup_bind(self, name) {
  self.lookup_bind_chain(name)
}

///|
pub impl @tutuca.Stack for RenderStack with fn lookup_field_raw(self, name) {
  self.it.field(name)
}

///|
pub impl @tutuca.Stack for RenderStack with fn lookup_member(self, name) {
  self.it.member_at(name, self).unwrap_or(Null)
}

///|
/// `$name` in value position is the RESULT of the no-arg method call, with
/// the current item as `this` (Obj method Fns are pre-bound and drop it).
pub impl @tutuca.Stack for RenderStack with fn lookup_method(self, name) {
  // `method_at` rather than `field`: the pre-bound `Fn` a compute surfaces as
  // carries arguments and nothing else, and a `compute` whose body reads
  // `*name` has to be handed the stack it is being asked from. That stack is
  // `self`.
  match self.it.method_at(name, self) {
    Some(Fn(_) as f) => call_handler(f, self.it, [])
    _ => Null
  }
}

///|
/// Render-time handlers (@when / @enrich-with / @loop-with): the alter
/// bucket on instances, plain Fn fields on the Map fallback.
pub impl @tutuca.Stack for RenderStack with fn get_handler_for(self, name, ns) {
  match self.it {
    // The render-time twin of `lookup_method` above, and the stack is handed
    // over for the same reason: a `@when` or an `enrich` reading `*name` is
    // asking THIS position.
    Obj(o) => o.obj_callable_at(name, ns, self).unwrap_or(Null)
    _ =>
      match self.it.field(name) {
        Fn(_) as f => f
        _ => Null
      }
  }
}

///|
/// `*name`: the nearest binding above — which INCLUDES this component's own
/// provides, pushed on entering it — else this component's declared default,
/// else Null.
///
/// One chain walk and no producer resolution: a lookup names what it wants, so
/// the frame it wants is keyed by that name. The default belongs to the
/// CONSUMER's declaration and is evaluated against the consumer's stack, which
/// is why it is consulted only after the whole chain has missed.
pub impl @tutuca.Stack for RenderStack with fn lookup_dynamic(self, name) {
  match self.lookup_dynamic_located(name) {
    Some(v) => v.value
    None => {
      guard self.comps is Some(comps) else { return Null }
      guard comps.get_comp_for(self.it) is Some(comp) else { return Null }
      match comp.lookup.get(name) {
        Some({ default_val: Some(d), .. }) => d.eval(self)
        _ => Null
      }
    }
  }
}

///|
pub fn RenderStack::lookup_dynamic_located(
  self : RenderStack,
  name : String,
) -> @component.LocatedValue? {
  match self.dyn_binds {
    Some(db) =>
      match db.lookup_located(name) {
        Some(v) => return Some(v)
        None => ()
      }
    None => ()
  }
  guard self.comps is Some(comps) else { return None }
  guard comps.get_comp_for(self.it) is Some(comp) else { return None }
  match comp.scope {
    Some(scope) =>
      match scope.lookup_path(name) {
        Some(path) =>
          match path.lookup(self.root) {
            Some(value) => return Some({ value, path: Some(path), })
            None => ()
          }
        None => ()
      }
    None => ()
  }
  match comp.lookup.get(name) {
    // The default belongs to the CONSUMER, so it is located from the consumer's
    // own position — and only when that position is writable. A constant
    // default (`'gray'`) has no step at all: it reads fine and can never be
    // resumed at.
    Some({ default_val: Some(d), .. }) =>
      Some({
        value: d.eval(self),
        path: match (d.to_path_item(), self.publish_base()) {
          (Some(step), Some(base)) => Some(base.concat([step]))
          _ => None
        },
      })
    _ => None
  }
}

///|
/// The type half of `lookup_dynamic`: the nearest component an ancestor
/// published under `name` with `provide {Name: "self"}`, as its id.
///
/// Not on the `@tutuca.Stack` trait, because the value language has no way to
/// write one — a type left the value language with `K_TYPE`. A handler asks
/// for it through `ctx.make`.
pub fn RenderStack::lookup_dyn_type(self : RenderStack, name : String) -> Int? {
  match self.dyn_binds {
    Some(db) => db.lookup_type(name)
    None => None
  }
}
