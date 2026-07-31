///| A loaded guest bundle: its manifest, its bridge, and the components the
/// host synthesized from the manifest views. Registration follows the
/// storybook precedent: a fresh child scope per bundle (name isolation)
/// sharing the app's component registry (resolution by id).

///|
pub struct Bundle {
  guest : &Guest
  manifest : DynManifest
  /// What the linter said about this bundle's views, as
  /// `CODE (level) Comp/view: message` lines (the shape `gen-views` prints).
  ///
  /// A guest's views are the one part of a component that arrives as SOURCE at
  /// runtime, so they are the one part no build step ever checked. The rules
  /// are pure functions over that source, so running them at load costs a
  /// parse the host was going to do anyway — and it is the only feedback a
  /// guest author gets.
  diagnostics : Array[String]
  /// name -> (synthesized component id, its declared schema, manifest def).
  /// The schema is built ONCE here and carried: every instance reads it (its
  /// fields, its fingerprint, its mutators), and rebuilding it per
  /// `make_instance` would pay for a value that cannot change.
  comps : Map[String, (Int, @tutuca.SchemaInfo, DynComponentDef)]
}

///|
pub fn Bundle::module_name(self : Bundle) -> String {
  self.manifest.module_name
}

///|
/// What a component of this bundle declares: its fields, the message buckets
/// it answers, the `@on` names its views raise, its fingerprint. None for a
/// component this bundle does not have.
pub fn Bundle::schema_of(
  self : Bundle,
  component : String,
) -> @tutuca.SchemaInfo? {
  match self.comps.get(component) {
    Some((_, schema, _)) => Some(schema)
    None => None
  }
}

///|
/// What the linter said about this bundle's views (see the field).
pub fn Bundle::diagnostics(self : Bundle) -> Array[String] {
  self.diagnostics
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
  let comps : Map[String, (Int, @tutuca.SchemaInfo, DynComponentDef)] = Map([])
  let synthesized = []
  let diagnostics : Array[String] = []
  for def in manifest.components {
    // Guest view HTML arrives at runtime from the manifest, so it is parsed
    // (View::new), not compiled ahead of time — the manifest's `main` view
    // carries the component's scoped style.
    let cviews : Map[String, @anode.View] = Map([])
    for v in def.views {
      let style = if v.name == "main" { def.style } else { "" }
      cviews[v.name] = @anode.View::new(v.name, raw_view=v.html, style~)
      lint_view(diagnostics, "\{def.name}/\{v.name}", v.html)
    }
    // The schema the guest DECLARED, which is the whole difference between a
    // guest component that is a name with handlers hanging off it and one the
    // generic layers can describe, compare, project and mutate. `inputs` is
    // absent on purpose: `compile()` reads those off the compiled views.
    let declared = @component.SchemaInfo::new(
      name=def.name,
      fingerprint="",
      fields=def.field_infos(),
      receives=def.receives,
      bubbles=def.bubbles,
      responses=def.responses,
      methods=def.methods,
      view_names=def.views.map(v => v.name),
      init_names=def.inits.map(i => i.name),
    )
    // Hashed from the shape that just crossed, by the same function any other
    // runtime schema uses — a guest ships no generated `<v>_schema_fingerprint`
    // and this is what stands in for it.
    let schema : @tutuca.SchemaInfo = {
      ..declared,
      fingerprint: declared.shape_fingerprint(),
    }
    let comp = @component.Component::for_type(
      name=def.name,
      views=cviews,
      schema~,
    )
    synthesized.push(comp)
    comps[def.name] = (comp.id, schema, def)
  }
  // Requests the bundle SERVES, in its own scope: `lookup_request` walks
  // child -> parent, so a guest component finds its bundle's handler first and
  // falls through to the host's for anything the bundle does not serve. A host
  // component never sees these — it is not in this scope — which is what makes
  // a bundle's services its own.
  let served : Map[String, @component.RequestFn] = Map([])
  for def in manifest.components {
    for name in def.requests {
      served[name] = RequestFn((args, respond) => {
        respond(guest.handle_request(name, args))
      })
    }
  }
  if !served.is_empty() {
    child.register_request_handlers(served)
  }
  child.register_components(synthesized)
  for comp in synthesized {
    comp.compile()
  }
  // compile() filled in the `@on` names the views raise; the instances read
  // their schema from `comps`, so it takes the completed one.
  for comp in synthesized {
    match comps.get(comp.name) {
      Some((id, _, def)) => comps[comp.name] = (id, comp.schema, def)
      None => ()
    }
  }
  { guest, manifest, comps, diagnostics }
}

///|
/// The two lint passes `gen-views` runs over a view's source, appended to
/// `into` as printable lines: the structural HTML linter, and the parse-issue
/// / deprecation / bare-directive rules over a fresh SHADOW parse (never the
/// live tree the component renders from).
fn lint_view(into : Array[String], where_ : String, html : String) -> Unit {
  let line = (f : @lint.Finding) => {
    let level = match f.level {
      Error => "error"
      Warn => "warning"
      Hint => "hint"
    }
    into.push(
      "\{@lint.lint_code_name(f.code)} (\{level}) \{where_}: \{@lint.finding_message(f)}",
    )
  }
  for f in @lint.lint_html(html) {
    line(f)
  }
  let collector = @lint.LintCollector::new()
  let px = @anode.ParseContext::new(handler=collector)
  let _ = @anode.ANode::parse(html, px)
  for f in @lint.check_collected(collector) {
    line(f)
  }
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
    Some((comp_id, schema, def)) => {
      let handle = self.guest.create(component, args)
      Some(DynObj::new(comp_id, def, self.guest, handle, schema~))
    }
    None => None
  }
}

///|
/// Create an instance from one of the component's NAMED initial states (see
/// `DynInitDef`). None when the component or the fixture is unknown — the
/// caller then decides whether a bare instance will do.
pub fn Bundle::make_init(
  self : Bundle,
  component : String,
  init : String,
) -> DynObj? {
  guard self.comps.get(component) is Some((_, _, def)) else { return None }
  for i in def.inits {
    if i.name == init {
      return self.make_instance(component, args=i.args)
    }
  }
  None
}

///|
/// The named initial states a component declares, in declaration order.
pub fn Bundle::init_names(self : Bundle, component : String) -> Array[String] {
  match self.comps.get(component) {
    Some((_, _, def)) => def.inits.map(i => i.name)
    None => []
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
    Some((comp_id, schema, def)) =>
      Some(DynObj::new(comp_id, def, self.guest, handle, schema~).to_value())
    None => None
  }
}

///|
/// Rebuild an instance in THIS bundle from an old guest value's state — the
/// hot-swap path, where the old value may belong to a different (superseded)
/// bundle. The new component's constructor decides which of the old fields it
/// accepts; the rest are ignored. None if `old` is not a described instance or
/// the component is unknown (the caller then starts fresh instead of
/// migrating).
///
/// The projection is `Value::to_json` over the old instance's own schema:
/// every field it declared, read through `get-field`. The guest used to
/// project its state itself (`to-json` plus a protocol field to reach it),
/// which is the same list of fields written a second time, in a second
/// language, with no check that the two agreed.
pub fn Bundle::migrate_instance(
  self : Bundle,
  old : @tutuca.Value,
  component : String,
) -> DynObj? {
  guard old is Obj(o) else { return None }
  guard o.obj_schema() is Some(schema) else { return None }
  let args : Map[String, @tutuca.Value] = Map([])
  for f in schema.fields {
    match o.obj_field(f.name) {
      Some(v) => args[f.name] = v
      None => ()
    }
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
