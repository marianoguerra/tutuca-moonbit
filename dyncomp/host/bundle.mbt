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
  /// Where minted persist ids come from (see `make_instance`). A counter
  /// rather than anything derived from the state, because two instances with
  /// equal state are still two instances, and a store keyed on their contents
  /// would silently keep one of them.
  next_pid : Ref[Int]
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
/// What a component of this bundle DECLARED, as it arrived — the docs,
/// keywords, category, per-field constraints and message-doc table that
/// `schema_of` has no room for.
///
/// `SchemaInfo` is the shape the runtime needs and this is the description a
/// catalog needs, and they are deliberately different: a host component has
/// the first and not the second, and everything generic over a schema must
/// keep working for it.
pub fn Bundle::def_of(self : Bundle, component : String) -> DynComponentDef? {
  match self.comps.get(component) {
    Some((_, _, def)) => Some(def)
    None => None
  }
}

///|
/// The bundle's own metadata: what it says it is, and what it asked the host
/// for. Advisory — see the `DynManifest` doc.
pub fn Bundle::manifest(self : Bundle) -> DynManifest {
  self.manifest
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
  policy? : @policy.Policy = @policy.Policy::untrusted(),
) -> Bundle raise ManifestError {
  // Everything the host decides about a bundle happens first and together, so
  // a refusal costs no parsing and leaves nothing behind. `@policy` owns the
  // decisions; this owns the mechanics — see dyncomp/SECURITY.md.
  refuse_if_any(policy.check_quotas(facts_of(manifest)))
  refuse_if_any(policy.check_capabilities(manifest.capabilities))
  let child = scope.enter()
  let comps : Map[String, (Int, @tutuca.SchemaInfo, DynComponentDef)] = Map([])
  let synthesized = []
  let diagnostics : Array[String] = []
  for def in manifest.components {
    refuse_if_any(policy.check_style(def.name, def.style))
    // Guest view HTML arrives at runtime from the manifest, so it is parsed
    // (View::new), not compiled ahead of time — the manifest's `main` view
    // carries the component's scoped style.
    let cviews : Map[String, @anode.View] = Map([])
    for v in def.views {
      let style = if v.name == "main" { def.style } else { "" }
      cviews[v.name] = @anode.View::new(v.name, raw_view=v.html, style~)
      screen_view(policy, diagnostics, "\{def.name}/\{v.name}", v.html)
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
    // A view that will not compile is a bundle that will not render, and the
    // parser's message is the only thing that says WHY. Rewrapping it keeps
    // this function's raise type to one error, so a caller can read the reason
    // out instead of catching an abstract one and reporting "something failed".
    comp.compile() catch {
      e =>
        raise ManifestError(
          "bundle refused: \{comp.name} failed to compile: \{e}",
        )
    }
  }
  // compile() filled in the `@on` names the views raise; the instances read
  // their schema from `comps`, so it takes the completed one.
  for comp in synthesized {
    match comps.get(comp.name) {
      Some((id, _, def)) => comps[comp.name] = (id, comp.schema, def)
      None => ()
    }
  }
  { guest, manifest, comps, diagnostics, next_pid: { val: 1 } }
}

///|
/// Everything the host checks about one guest view before it will render it.
///
/// Two lint passes, which `gen-views` also runs and which only ADVISE (they
/// land in `into` as printable lines): the structural HTML linter, and the
/// parse-issue / deprecation / bare-directive rules. Then one rule that
/// REFUSES, over the same shadow tree.
///
/// The shadow parse is what makes the refusal cheap and correct here: it is a
/// throwaway tree in a throwaway ParseContext, so this runs before anything is
/// registered. Deciding after `compile()` would mean the components were
/// already in the shared registry — contributing event names and CSS classes —
/// by the time the host said no.
fn screen_view(
  policy : @policy.Policy,
  into : Array[String],
  where_ : String,
  html : String,
) -> Unit raise ManifestError {
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
  let tree = @anode.ANode::parse(html, px)
  for f in @lint.check_collected(collector) {
    line(f)
  }
  // What the host will RENDER is the policy's decision, taken over this same
  // throwaway tree.
  if tree is Some(t) {
    refuse_if_any(policy.check_view(where_, t))
  }
}

///|
/// Turn a policy's refusals into the error a load reports.
///
/// One raise per decision point rather than a collected list, because a
/// refusal is terminal: there is no partially-registered bundle to report the
/// rest of the problems against, and a guest author fixing the first thing
/// will re-run and see the second.
fn refuse_if_any(refusals : Array[@policy.Refusal]) -> Unit raise ManifestError {
  if refusals.is_empty() {
    return
  }
  let shown = refusals.map(r => r.to_string()).join("; ")
  raise ManifestError("bundle refused: \{shown}")
}

///|
/// The numbers a quota is about. The policy takes five integers rather than
/// the manifest, so that it can stay a leaf this package depends on.
fn facts_of(manifest : DynManifest) -> @policy.BundleFacts {
  let mut max_views = 0
  let mut max_view_bytes = 0
  let mut max_style_bytes = 0
  let mut max_types = 0
  for def in manifest.components {
    if def.views.length() > max_views {
      max_views = def.views.length()
    }
    if def.types.length() > max_types {
      max_types = def.types.length()
    }
    if def.style.length() > max_style_bytes {
      max_style_bytes = def.style.length()
    }
    for v in def.views {
      if v.html.length() > max_view_bytes {
        max_view_bytes = v.html.length()
      }
    }
  }
  {
    components: manifest.components.length(),
    max_views,
    max_view_bytes,
    max_style_bytes,
    max_types,
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
  pid? : String = "",
) -> DynObj? {
  match self.comps.get(component) {
    Some((comp_id, schema, def)) => {
      let handle = self.guest.create(component, args)
      Some(
        DynObj::new(
          comp_id,
          def,
          self.guest,
          handle,
          schema~,
          pid=if pid == "" { self.mint_pid(component) } else { pid },
        ),
      )
    }
    None => None
  }
}

///|
/// A name for an instance nobody named: the module, the component, and a
/// number that counts within this session.
///
/// Minting one rather than leaving it blank is what makes "every instance has
/// an identity" true, and the shape says how far to trust it: it is stable
/// across the successors of one instance and NOT across a reload, so a host
/// that wants a key it can find again after a refresh — a slot in a saved
/// document, a row id — passes its own through `pid~` or `with_persist_id`.
/// What the minted one buys is that a snapshot is never anonymous: it says
/// which component of which bundle it came from, and a restore honours the id
/// it was stored with rather than minting a second one.
fn Bundle::mint_pid(self : Bundle, component : String) -> String {
  let n = self.next_pid.val
  self.next_pid.val = n + 1
  "\{self.manifest.module_name}/\{component}#\{n}"
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

// --- persistence (dyncomp/persist) ------------------------------------------

///|
/// What this instance would be stored as: the guest's own bytes AND the
/// declared-field projection, so the restore can go either way.
///
/// Takes a `Value` rather than a `DynObj` because that is what a host holds —
/// a field of a component, an entry in a map — and everything it needs is on
/// the `Obj` seam: the component name from the schema, the guest handle from
/// the protocol field, the identity from `obj_persist_id`. None for a value
/// that is not an instance of THIS bundle.
pub fn Bundle::snapshot(self : Bundle, v : @tutuca.Value) -> @persist.Snapshot? {
  guard v is Obj(o) else { return None }
  guard o.obj_schema() is Some(schema) else { return None }
  guard self.comps.get(schema.name) is Some(_) else { return None }
  let state = match o.obj_field(handle_field) {
    Some(Num(h)) => self.guest.persist(h.to_int())
    _ => b""
  }
  let fields = v.to_json()
  // An instance that answers NOTHING is not an empty instance — it is a
  // handle the bridge no longer has, which is a host bookkeeping slip
  // somewhere upstream. Storing what it "said" would overwrite a good
  // snapshot with a blank one, so this refuses instead and the caller keeps
  // what it had.
  if state.length() == 0 && !says_something(fields) {
    return None
  }
  Some({
    module_: self.manifest.module_name,
    component: schema.name,
    id: o.obj_persist_id().unwrap_or(""),
    state,
    fields,
  })
}

///|
/// Whether a field projection has anything in it. `{}` and `null` are what a
/// dead handle projects to, and neither is worth storing.
fn says_something(fields : Json) -> Bool {
  match fields {
    Object(m) => !m.is_empty()
    Null => false
    _ => true
  }
}

///|
/// The inverse: a stored snapshot, back into a live instance of this bundle.
///
/// The guest gets first refusal on its own bytes; if it declines them (a
/// format it no longer reads) or never wrote any, the declared fields rebuild
/// it instead. Either way the instance comes back under the id it was stored
/// with, so saving it again lands on the same key.
///
/// None only when the component is unknown here — which is the honest answer
/// for a snapshot from a bundle that is not this one.
pub fn Bundle::restore(self : Bundle, snap : @persist.Snapshot) -> DynObj? {
  guard self.comps.get(snap.component) is Some((comp_id, schema, def)) else {
    return None
  }
  let pid = if snap.id == "" { self.mint_pid(snap.component) } else { snap.id }
  if snap.has_state() {
    if self.guest.restore(snap.component, snap.state) is Some(handle) {
      return Some(DynObj::new(comp_id, def, self.guest, handle, schema~, pid~))
    }
  }
  self.make_instance(snap.component, args=snap.field_args(), pid~)
}
