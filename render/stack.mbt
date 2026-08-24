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
    it,
    binds,
    parent: None,
    view_names: [],
    is_frame: true,
    comps,
    dyn_binds: None,
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
) -> RenderStack {
  let stack : RenderStack = { ..self, it, binds, parent: Some(self), is_frame }
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
  let binds : Map[String, @tutuca.Value] = Map([])
  for _, p in comp.provide {
    binds[p.name] = p.val.eval(self)
  }
  let types : Map[String, Int] = Map([])
  for tname, cid in comp.provide_type {
    types[tname] = cid
  }
  { ..self, dyn_binds: Some({ binds, types, parent: self.dyn_binds }) }
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
/// `$name` in value position is the RESULT of the no-arg method call, with
/// the current item as `this` (Obj method Fns are pre-bound and drop it).
pub impl @tutuca.Stack for RenderStack with fn lookup_method(self, name) {
  match self.it.field(name) {
    Fn(_) as f => call_handler(f, self.it, [])
    _ => Null
  }
}

///|
/// Render-time handlers (@when / @enrich-with / @loop-with): the alter
/// bucket on instances, plain Fn fields on the Map fallback.
pub impl @tutuca.Stack for RenderStack with fn get_handler_for(self, name, ns) {
  match self.it {
    Obj(o) => o.obj_callable(name, ns).unwrap_or(Null)
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
  let bound : @tutuca.Value? = match self.dyn_binds {
    Some(db) => db.lookup(name)
    None => None
  }
  match bound {
    Some(v) => v
    None => {
      guard self.comps is Some(comps) else { return Null }
      guard comps.get_comp_for(self.it) is Some(comp) else { return Null }
      match comp.lookup.get(name) {
        Some(lk) =>
          match lk.default_val {
            Some(d) => d.eval(self)
            None => Null
          }
        None => Null
      }
    }
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
