// RenderStack: the @tutuca.Stack implementation over component instances.
// Fields/methods/handlers resolve against the CURRENT item (`it`, per frame —
// JS reads this.it[name]): Obj instances answer through the Obj trait, plain
// Value::Map keeps the component-less mode working. `@name` binds resolve
// along the frame chain with frame barriers.

///|
pub fn RenderStack::new(
  it : @tutuca.Value,
  binds? : Map[String, @tutuca.Value] = Map([]),
  comps? : @component.Components,
  event? : DomEvent,
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
/// Evaluate the entered component's provides against the post-enter stack
/// and cons one DynBinds frame (JS _pushProvides). No-op without a registry,
/// a component, or provides.
fn RenderStack::push_provides(self : RenderStack) -> RenderStack {
  guard self.comps is Some(comps) else { return self }
  guard comps.get_comp_for(self.it) is Some(comp) else { return self }
  if comp.provide.is_empty() {
    return self
  }
  let binds : Map[@component.ProvideKey, @tutuca.Value] = Map([])
  for _, p in comp.provide {
    binds[p.key] = p.val.eval(self)
  }
  { ..self, dyn_binds: Some({ binds, parent: self.dyn_binds }) }
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
/// The pushed-view trail, innermost first (JS lookupBestView walks it).
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
    // A frame is a barrier (JS BindFrame STOP): binds never cross a
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
pub impl @tutuca.Stack for RenderStack with fn lookup_name(self, name) {
  match self.lookup_bind_chain(name) {
    // binds shadow event fields (an @each `value` bind wins over the DOM
    // event's value, like JS bind-frame lookup running before ctx.lookupName)
    Null =>
      match self.event {
        Some(e) => event_field(e, name)
        None => Null
      }
    v => v
  }
}

///|
/// `e.<segments>`: the two-layer resolve, and NOT a name lookup.
///
/// Deliberately not routed through `lookup_name`, which is where a bind
/// shadows an event field. An `e.` path names the event outright, so nothing
/// may shadow it — that is the point of writing the root. The v1 spelling, a
/// bare `value`, still goes through `lookup_name` and is still shadowable by an
/// `@each` bind called `value`; the two spellings mean different things, which
/// is one more reason v2 asks for the prefix.
pub impl @tutuca.Stack for RenderStack with fn lookup_event_path(self, segments) {
  match self.event {
    Some(e) => event_path(e, segments)
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
/// `*name` (JS stack.js lookupDynamic): resolve through the current
/// component's lookup alias (producer's provide key walked through the
/// dynBinds chain, else the lookup default) or its own provide.
pub impl @tutuca.Stack for RenderStack with fn lookup_dynamic(self, name) {
  guard self.comps is Some(comps) else { return Null }
  guard comps.get_comp_for(self.it) is Some(comp) else { return Null }
  match comp.lookup.get(name) {
    Some(lk) => {
      // Memoized on the LookupInfo (JS getProducerSymbol): the scope walk runs
      // once per lookup alias, not on every `*name` read.
      let producer_key : @component.ProvideKey? = lk.resolve_producer_key(
        comp.scope,
      )
      let bound : @tutuca.Value? = match (producer_key, self.dyn_binds) {
        (Some(key), Some(db)) => db.lookup(key)
        _ => None
      }
      match bound {
        Some(v) => v
        None =>
          match lk.default_val {
            Some(d) => d.eval(self)
            None => Null
          }
      }
    }
    None =>
      match comp.provide.get(name) {
        Some(p) =>
          match self.dyn_binds {
            Some(db) =>
              match db.lookup(p.key) {
                Some(v) => v
                None => p.val.eval(self)
              }
            None => p.val.eval(self)
          }
        None => Null
      }
  }
}
