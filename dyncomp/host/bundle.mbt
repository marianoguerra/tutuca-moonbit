///| A loaded guest bundle: its manifest, its bridge, and the components the
/// host synthesized from the manifest views. Registration follows the
/// storybook precedent: a fresh child scope per bundle (name isolation)
/// sharing the app's component registry (resolution by id).

///|
pub struct Bundle {
  guest : &Guest
  manifest : DynManifest
  comps : Map[String, (Int, DynComponentDef)]
}

///|
pub fn Bundle::module_name(self : Bundle) -> String {
  self.manifest.module_name
}

///|
/// The bundle's component names, in manifest (declaration) order. Used by
/// hosts that mount every declared component (e.g. the universal drop shell)
/// rather than naming specific ones.
pub fn Bundle::component_names(self : Bundle) -> Array[String] {
  self.manifest.components.map(def => def.name)
}

///|
/// Synthesize + register + compile the manifest's components into a child
/// scope of `scope`. Safe after App::new: the shared registry is live, and
/// compiling here means event_names()/styles reflect the new components.
/// Guest view parse errors surface as the compile error.
pub fn register_bundle(
  scope : @component.ComponentStack,
  guest : &Guest,
  manifest : DynManifest,
) -> Bundle raise {
  let child = scope.enter()
  let comps : Map[String, (Int, DynComponentDef)] = Map([])
  let synthesized = []
  for def in manifest.components {
    // Guest view HTML arrives at runtime from the manifest, so it is parsed
    // (View::new), not compiled ahead of time — the manifest's `main` view
    // carries the component's scoped style.
    let cviews : Map[String, @anode.View] = Map([])
    for v in def.views {
      let style = if v.name == "main" { def.style } else { "" }
      cviews[v.name] = @anode.View::new(v.name, raw_view=v.html, style~)
    }
    let comp = @component.Component::for_type(name=def.name, views=cviews)
    synthesized.push(comp)
    comps[def.name] = (comp.id, def)
  }
  child.register_components(synthesized)
  for comp in synthesized {
    comp.compile()
  }
  { guest, manifest, comps }
}

///|
/// Create a guest instance wrapped as a DynObj; seed `.to_value()` into any
/// host field and render it with `<x render=".field">`. None for an unknown
/// component name.
pub fn Bundle::make_instance(
  self : Bundle,
  component : String,
  args? : Map[String, @tutuca.Value] = Map([]),
) -> DynObj? {
  match self.comps.get(component) {
    Some((comp_id, def)) => {
      let handle = self.guest.create(component, args)
      Some({ comp_id, def, guest: self.guest, handle })
    }
    None => None
  }
}

///|
/// Wrap an EXISTING guest instance handle (e.g. a nested-child token the
/// guest produced) as a tree value. None for an unknown component name.
pub fn Bundle::wrap_instance(
  self : Bundle,
  component : String,
  handle : Int,
) -> @tutuca.Value? {
  match self.comps.get(component) {
    Some((comp_id, def)) =>
      Some(DynObj::new(comp_id, def, self.guest, handle).to_value())
    None => None
  }
}

///|
/// Rebuild an instance in THIS bundle from an old guest value's JSON state
/// projection (read through the state-json protocol field, so the old
/// value may belong to a different — e.g. superseded — bundle). The new
/// component's constructor decides which projected fields it accepts;
/// unknown fields are ignored. None if `old` is not a guest value, the
/// component is unknown, or the state projection is not valid JSON (the
/// caller then starts the new instance fresh instead of migrating).
pub fn Bundle::migrate_instance(
  self : Bundle,
  old : @tutuca.Value,
  component : String,
) -> DynObj? {
  guard old is Obj(o) else { return None }
  guard o.obj_field(state_json_field) is Some(Str(json)) else { return None }
  let j = @json.parse(json) catch { _ => return None }
  let args : Map[String, @tutuca.Value] = Map([])
  match j {
    Object(fields) =>
      for name, fv in fields {
        args[name] = @tutuca.Value::from_json(fv)
      }
    _ => ()
  }
  self.make_instance(component, args~)
}

///|
/// Drop one guest instance by handle (successor handles from dispatch are
/// collected automatically — see collect_superseded; this is for instances
/// the caller seeded and unmounted explicitly).
pub fn Bundle::drop_instance(self : Bundle, handle : Int) -> Unit {
  self.guest.drop_instance(handle)
}
