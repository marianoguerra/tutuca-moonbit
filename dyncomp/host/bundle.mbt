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
  /// runtime, so they are the one part no build step ever checked. The lint
  /// rules are pure functions over that source, so running them at load costs a
  /// parse the host was going to do anyway — and it is the only feedback a
  /// guest author gets.
  ///
  /// `screen_method_names` adds one line that is NOT a function of the source
  /// alone: it needs the manifest beside the view to say that a `$name` the
  /// view calls is a name nothing will answer. Load is the first moment both
  /// halves exist, which is why it lands here rather than in `@lint`.
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
  /// The child scope this bundle registered into, kept so `make_instance` can
  /// resolve a declared PLACEHOLDER (see `DynObj.owned`). `lookup_component`
  /// walks to the parent, so a guest naming a component the HOST registered
  /// finds it — which is the whole point, and also the only cross-module reach
  /// a bundle gets: it names a component, the host builds it, and the guest
  /// never holds the result.
  scope : @component.ComponentStack
  /// What this registration decided its variables are (`bundle_config.mbt`):
  /// the guest's whole table, and the origins its views may name.
  config : ResolvedConfig
  /// This registration's identity — see `Bundle::key`.
  key : String
}

///|
pub fn Bundle::module_name(self : Bundle) -> String {
  self.manifest.module_name
}

///|
/// What identifies this registration: the bundle AND the variables it was
/// registered with.
///
/// The module name alone is not an identity, and treating it as one is what
/// made two configurations of one bundle impossible: loading the second
/// retired the first, because `by_name` had room for exactly one. A mastodon
/// reader pointed at mastodon.social and one pointed at hachyderm.io are the
/// same code and different components, and this is the string that says so.
///
/// It also makes hot-swap mean what it looked like it meant. Reloading a
/// bundle with the SAME config still replaces the old one — same key — while
/// reloading it with different config now adds a sibling instead of evicting
/// something a page was still drawing.
///
/// FNV-1a, like `SchemaInfo::shape_fingerprint`, and not cryptographic for the
/// same reason: it separates registrations a host made, not ones an attacker
/// did. A host that binds attacker-chosen config has already made a decision
/// this hash is not the boundary for.
pub fn Bundle::key(self : Bundle) -> String {
  self.key
}

///|
/// The variables this bundle runs with, by name. What a consent dialog or a
/// catalog shows beside the capability list, and what `config.get` answers.
pub fn Bundle::config(self : Bundle) -> Map[String, String] {
  self.config.all
}

///|
fn bundle_key(manifest : DynManifest, config : ResolvedConfig) -> String {
  let sb = StringBuilder::new()
  sb.write_string("m:\{manifest.module_name}\nv:\{manifest.version}\n")
  sb.write_string(config.canonical())
  let mut h : UInt64 = 0xcbf29ce484222325UL
  for c in sb.to_string().to_array() {
    h = (h ^ c.to_int().reinterpret_as_uint().to_uint64()) * 0x100000001b3UL
  }
  let digits = "0123456789abcdef".to_array()
  let out = StringBuilder::new()
  for i in 0..<16 {
    out.write_char(digits[((h >> ((15 - i) * 4)) & 0xfUL).to_int()])
  }
  "\{manifest.module_name}@\{out.to_string()}"
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
  let diagnostics : Array[String] = []
  // Before anything is parsed, because the parse depends on it: a `$$name` in
  // a view resolves against `config.view`, and the policy the views are then
  // JUDGED against may have grown an origin from a manifest default this host
  // said it trusts. Both have to be settled first or the two disagree.
  let (config, policy) = resolve_config(manifest, policy, diagnostics)
  let child = scope.enter()
  let comps : Map[String, (Int, @tutuca.SchemaInfo, DynComponentDef)] = Map([])
  let synthesized = []
  for def in manifest.components {
    refuse_if_any(policy.check_style(def.name, def.style))
    // Guest view HTML arrives at runtime from the manifest, so it is parsed
    // (View::new), not compiled ahead of time — the manifest's `main` view
    // carries the component's scoped style.
    let cviews : Map[String, @anode.View] = Map([])
    for v in def.views {
      let style = if v.name == "main" { def.style } else { "" }
      cviews[v.name] = @anode.View::new(
        v.name,
        raw_view=v.html,
        style~,
        config_vars=config.view,
      )
      screen_view(
        policy,
        diagnostics,
        "\{def.name}/\{v.name}",
        v.html,
        config.view,
      )
    }
    // The schema the guest DECLARED, which is the whole difference between a
    // guest component that is a name with handlers hanging off it and one the
    // generic layers can describe, compare, project and mutate.
    // `view_handlers` is absent on purpose: `compile()` reads those off the
    // compiled views.
    let declared = @component.SchemaInfo::new(
      name=def.name,
      fingerprint="",
      fields=def.field_infos(),
      receives=def.receives,
      intents=def.intents,
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
  // What the bundle SERVES, registered in its own scope as intent handlers on
  // the `lex` leg: `lookup_intent` walks child -> parent, so a guest component
  // finds its bundle's handler first and falls through to the host's for
  // anything the bundle does not serve. A host component never sees these — it
  // is not in this scope — which is what makes a bundle's services its own.
  //
  // A served name cannot answer `Pass`: the guest ABI has no way to decline,
  // so it answers `Ok` or `Failed` and the walk ends here whichever it is.
  // Declining is a host-side handler's privilege.
  let served : Map[String, Array[@component.IntentFn]] = Map([])
  for def in manifest.components {
    for name in def.serves {
      served[name] = [
        IntentFn((call, answer) => {
          answer(
            match guest.serve_intent(name, call.args) {
              Ok(v) => Ok(v)
              Err(e) => Failed(e)
            },
          )
        }),
      ]
    }
  }
  if !served.is_empty() {
    child.register_intent_handlers(served)
  }
  // Macros BEFORE the components compile, because a view expands one at parse
  // time: `register_macros` is deliberately separate from `register_components`
  // for exactly this order, and `comp.compile()` below is where a `<x:badge>`
  // would otherwise be an unknown element that renders as itself.
  //
  // Into the bundle's own child scope, like everything else it declares — a
  // bundle's macros are its own, and a host component two levels up has no
  // business seeing them.
  if !manifest.macros.is_empty() {
    let macros : Map[String, @anode.Macro] = Map([])
    for m in manifest.macros {
      macros[m.name] = { defaults: m.defaults, raw_view: m.html }
    }
    child.register_macros(macros)
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
  // their schema from `comps`, so it takes the completed one. The compiled
  // views are also the first point where what a view CALLS can be compared
  // against what the manifest declared — see `screen_method_names`.
  for comp in synthesized {
    match comps.get(comp.name) {
      Some((id, _, def)) => {
        comps[comp.name] = (id, comp.schema, def)
        screen_method_names(diagnostics, comp, def)
        screen_constraints(diagnostics, def)
      }
      None => ()
    }
  }
  {
    guest,
    manifest,
    comps,
    diagnostics,
    next_pid: { val: 1 },
    scope: child,
    config,
    key: bundle_key(manifest, config),
  }
}

///|
/// One finding as a printable line, in the `CODE (level) where: message` shape
/// `gen-views` uses. Shared by every screening pass so a bundle's diagnostics
/// read as one list rather than as one list per rule that produced it.
fn diagnostic_line(
  into : Array[String],
  where_ : String,
  f : @lint.Finding,
) -> Unit {
  let level = match f.level {
    Error => "error"
    Warn => "warning"
    Hint => "hint"
  }
  into.push(
    "\{@lint.lint_code_name(f.code)} (\{level}) \{where_}: \{@lint.finding_message(f)}",
  )
}

///|
/// A declared bound the field's TYPE cannot carry.
///
/// The manifest's constraint record spells "unstated" two ways — `null` (or an
/// absent key) for the four bounds, `""` for the strings beside them — and four
/// of the six keys are safe to write blank. So the habit of writing the record
/// out in full, which every sample guest's manifest teaches, quietly states four
/// zeros. Each one fails differently and none of them fail loudly:
///
///   - `minLen` / `maxLen: 0` on text or a collection is a REAL bound that
///     forbids every value. Nothing here can tell that apart from one somebody
///     meant, so it is not what this screens for — it is why the screen exists.
///   - `min` / `max` on anything but a number is dropped when validating
///     (`v is Num` guards it) and dropped from the generated schema, so it does
///     nothing at all except mislead whoever reads the manifest.
///   - `minLen` / `maxLen` on a number or a bool, likewise.
///
/// The second and third are what this names, because they are the ones that are
/// unambiguously a mistake: a bound that cannot apply was not a decision. A hint
/// rather than a warning — nothing is broken — and the value of saying it is
/// that an author learns the spelling before writing the one that IS broken.
fn screen_constraints(into : Array[String], def : DynComponentDef) -> Unit {
  for f in def.field_infos() {
    guard def.fields.filter(d => d.name == f.name) is [decl, ..] else {
      continue
    }
    guard decl.constraint is Some(c) else { continue }
    if !numeric_bound_applies(f.ty) {
      if c.min is Some(_) {
        constraint_hint(into, def, f.name, "min", f.ty)
      }
      if c.max is Some(_) {
        constraint_hint(into, def, f.name, "max", f.ty)
      }
    }
    if !length_bound_applies(f.ty) {
      if c.min_len is Some(_) {
        constraint_hint(into, def, f.name, "minLen", f.ty)
      }
      if c.max_len is Some(_) {
        constraint_hint(into, def, f.name, "maxLen", f.ty)
      }
    }
  }
}

///|
/// Mirrors `@jsonschema`'s emission gate: the two have to agree, because one
/// decides what is dropped and the other is what says so.
fn numeric_bound_applies(ty : @tutuca.TyInfo) -> Bool {
  match ty {
    TyInt | TyFloat | TyAny => true
    TyOption(inner) => numeric_bound_applies(inner)
    _ => false
  }
}

///|
fn length_bound_applies(ty : @tutuca.TyInfo) -> Bool {
  match ty {
    TyBool | TyInt | TyFloat | TyComp(_) | TyTable => false
    TyOption(inner) => length_bound_applies(inner)
    _ => true
  }
}

///|
fn constraint_hint(
  into : Array[String],
  def : DynComponentDef,
  field : String,
  key : String,
  ty : @tutuca.TyInfo,
) -> Unit {
  diagnostic_line(into, "\{def.name}.\{field}", {
    code: InertConstraint,
    level: Hint,
    info: [("name", field), ("key", key), ("kind", ty.show_source())],
    location: None,
    suggestion: None,
  })
}

///|
/// What a component's views CALL with `$name`, against what its manifest says
/// it answers.
///
/// `$name` resolves through `DynObj::obj_field`, which mints a callable for a
/// name the manifest listed in `methods` — or for one of the mutators the
/// declared fields imply — and for nothing else. Any other name falls through
/// to `get-field`, comes back `Null`, and `Null` in an attribute means "omit
/// the attribute". So a name missing from `methods` fails NOWHERE: the element
/// renders without its class, `call-method` is never reached, and the guest has
/// no way to learn it was asked. The silence is the bug; this is what breaks it.
///
/// Advisory, like the other passes — the view is legal and the bundle renders.
/// What it cannot do is the thing it was written to do.
///
/// Runs on COMPILED views, which is what makes it see through a macro call and
/// see `@on` handlers at all (those live on the parse context, not in the tree).
fn screen_method_names(
  into : Array[String],
  comp : @component.Component,
  def : DynComponentDef,
) -> Unit {
  let answered : Set[String] = Set::from_array(def.methods)
  // The generated mutators (`setCount`, `pushInItems`, …) are answered by the
  // host off the declared fields, so a view calling one is right to expect it
  // even though the manifest never lists it (see `DynObj::obj_field`).
  for name, _ in @component.schema_mutators(comp.schema) {
    answered.add(name)
  }
  let candidates = answered.to_array()
  candidates.sort()
  for vname, view in comp.views {
    let called : Set[String] = Set([])
    view.collect_method_names(called)
    let missing = called.to_array().filter(name => !answered.contains(name))
    // A set's order is not one to print: these lines are read by people and
    // asserted by tests, and both need the same list twice.
    missing.sort()
    for name in missing {
      let info : Array[(String, String)] = [("name", name)]
      let suggestion : @lint.Suggestion? = match
        @lint.closest_name(name, candidates) {
        Some(closest) => {
          info.push(("closest", closest))
          Some(ReplaceName(from="$\{name}", to="$\{closest}"))
        }
        None => None
      }
      diagnostic_line(into, "\{def.name}/\{vname}", {
        code: UndeclaredMethod,
        level: Warn,
        info,
        location: None,
        suggestion,
      })
    }
  }
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
  config_vars : Map[String, String],
) -> Unit raise ManifestError {
  let line = (f : @lint.Finding) => diagnostic_line(into, where_, f)
  for f in @lint.lint_html(html) {
    line(f)
  }
  let collector = @lint.LintCollector::new()
  // The SAME table `View::new` got, and passing it is the whole point of this
  // parameter. This is a second, throwaway parse of the same source; if it
  // resolved `$$name` differently from the tree that will actually render, the
  // check would be about a document nobody displays. Screening the unresolved
  // tree refuses every config-origin sink; screening a resolved one while
  // rendering an unresolved one checks nothing.
  let px = @anode.ParseContext::new(handler=collector, config_vars~)
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
          owned=self.fill_placeholders(schema, args),
        ),
      )
    }
    None => None
  }
}

///|
/// Build what this component's declared PLACEHOLDERS hold (see `DynObj.owned`).
///
/// FOREIGN ones only. A `ty-comp` field naming one of this bundle's OWN
/// components is a nested child the guest makes and owns (`control.make-instance`
/// is same-bundle by contract), and filling it here would shadow the guest's
/// value with a host-built one — which is what `Pair { left: Counter }` is, and
/// what would silently break if this did not check.
///
/// So the discriminator is the boundary itself: same-bundle means the guest's,
/// foreign means a hole only the host can fill.
///
/// A caller that passed one in `args` wins — that is how a restore puts back
/// what was in the hole. A name nothing answers to leaves the field empty
/// rather than refusing the instance: a guest whose placeholder cannot be
/// filled is still a guest that works, minus the hole.
fn Bundle::fill_placeholders(
  self : Bundle,
  schema : @tutuca.SchemaInfo,
  args : Map[String, @tutuca.Value],
) -> Map[String, @tutuca.Value] {
  let owned : Map[String, @tutuca.Value] = Map([])
  for pair in placeholder_fields(schema) {
    let (field, comp) = pair
    if self.comps.contains(comp) {
      continue
    }
    owned[field] = match args.get(field) {
      Some(given) if given is Obj(_) => given
      _ =>
        match self.scope.lookup_component(comp) {
          Some(c) => c.make(Map([]))
          None => Null
        }
    }
  }
  owned
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
///
/// Deliberately fills NO placeholders (see `DynObj.owned`). This runs on every
/// read of a field holding a nested child, so filling here would build a fresh
/// placeholder per read and throw away whatever was put in the last one — the
/// guest's own state survives because it lives behind the handle, and
/// host-owned state would not. A nested same-bundle child therefore has no
/// placeholders; the top-level instances a person places do, which is the case
/// this exists for. Giving nested children real ones needs a host-side table
/// keyed by guest token, which is a bigger change than it looks.
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
