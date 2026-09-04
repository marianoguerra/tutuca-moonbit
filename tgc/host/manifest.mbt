///| The module's static `manifest.json`, after the bridge hydrates its view
/// files and serializes it to the host. Views are tutuca template strings
/// compiled host-side; the declared schema — fields over a flat type table,
/// plus the message buckets — becomes the `SchemaInfo` every generic-access
/// seam reads (see `register_module`).

///|
pub(all) struct DynViewDef {
  name : String
  html : String
} derive(Debug, Eq)

///|
pub(all) struct DynFieldDef {
  name : String
  ty : @tutuca.Ty
  /// What the field is FOR. The one fact neither the type table nor the views
  /// can supply, and what a search index ranks on.
  doc : String
  required : Bool
  /// The bounds on this field, conjoined. Empty is unconstrained.
  domains : Array[@tutuca.Domain]
  /// What a form pre-fills and a schema advertises — not a bound, and not the
  /// type's zero.
  default : @tutuca.Value?
} derive(Debug, Eq)

///|
pub(all) struct DynPropertyDef {
  name : String
  ty : @tutuca.Ty
  public_ : Bool
  writable : Bool
  doc : String
} derive(Debug, Eq)

///|
pub(all) struct DynProtocolDef {
  id : String
  handle_messages : Array[String]
  handle_intents : Array[String]
  express_messages : Array[String]
  express_intents : Array[String]
  properties : Array[DynPropertyDef]
  views : Array[String]
  provides : Array[String]
  lookups : Array[String]
} derive(Debug, Eq)

///|
pub(all) struct DynProtocolBinding {
  protocol_id : String
  member_name : String
  source : String
} derive(Debug, Eq)

///|
/// One variable this module reads, as the module DECLARES it: a name, what
/// kind of thing it is, what it is worth when nobody says otherwise, and what
/// it is for.
///
/// The declaration is half of a contract, and the host's binding is the other
/// half — both state the type, and `resolve_config` refuses a module where
/// they disagree. See `@policy.with_config` for why the redundancy is the
/// point rather than an oversight.
///
/// The default reaches the GUEST, which is what lets a module be sensible on a
/// host that bound nothing. It does not reach a view: an `origin` default that
/// opened a URL sink would be a module granting itself an origin.
pub(all) struct DynConfigDef {
  name : String
  ty : @policy.ConfigTy
  default_ : String
  doc : String
} derive(Debug, Eq)

///|
/// A named initial state the guest declares, with its constructor args already
/// decoded from the manifest's JSON.
pub(all) struct DynInitDef {
  name : String
  args : Map[String, @tutuca.Value]
  doc : String
  /// Which view to render this state under; "" for the default resolution.
  view : String
  /// What a picker filters on.
  tags : Array[String]
  /// Whether this is the state to show when nothing names one.
  default_ : Bool
  /// Steps to run after the value is seeded, and the intent answers they need
  /// — carried as JSON rather than parsed.
  ///
  /// A manifest is a WIRE format, and passing a thing it does not interpret
  /// through untouched is what one is for. Parsing them here would mean this
  /// package knowing the scene vocabulary, which belongs to whoever runs a
  /// fixture rather than to whoever describes one. "" for a fixture with none.
  drive_json : String
  intents_json : String
} derive(Debug, Eq)

///|
pub(all) struct DynComponentDef {
  name : String
  /// What this component IS. A catalog with nothing but names is a catalog
  /// nobody — person or model — can choose from.
  doc : String
  /// Search terms beyond the name and the doc.
  keywords : Array[String]
  /// A grouping for a palette; "" = ungrouped.
  category : String
  /// Sentences for the names in views / `receives` / `intents` / `methods` /
  /// `serves`, merged by name — one table rather than a doc field on five
  /// parallel lists.
  message_docs : Map[String, String]
  views : Array[DynViewDef]
  fields : Array[DynFieldDef]
  /// Public abstract state, separately declared from internal storage fields.
  properties : Array[DynPropertyDef]
  /// The FIELD DOMAINS the guest declared — its spec block's `where` clauses,
  /// in the runtime vocabulary.
  ///
  /// Here rather than on `DynFieldDef` beside `constraint`, because the two are
  /// different shapes of claim: a constraint is about ONE field's value, and a
  /// domain is a relation that may name another field (`currentIndex is index
  /// of .items`). A per-field list could not hold the second, and splitting one
  /// vocabulary across two homes by whether it happens to mention a neighbour
  /// would be a distinction no reader could keep.
  domains : Array[@tutuca.FieldDomain]
  receives : Array[String]
  /// Every INTENT this component answers — a routed dispatch, offered to each
  /// hop of a route until something replies. The answer to one comes back as
  /// an ordinary message, so it is declared in `receives` rather than here.
  intents : Array[String]
  express_messages : Array[String]
  express_intents : Array[String]
  implements : Array[String]
  protocols : Array[DynProtocolDef]
  property_bindings : Array[DynProtocolBinding]
  view_bindings : Array[DynProtocolBinding]
  provide_bindings : Array[DynProtocolBinding]
  lookup_bindings : Array[DynProtocolBinding]
  methods : Array[String]
  /// Callables a view's `@when` names (the render-time namespace).
  whens : Array[String]
  /// Callables a view's `@enrich-with` names — the in-loop form, called about
  /// one row and answering the bindings that row is rendered with.
  ///
  /// Same namespace as `whens` and a different call shape, which is why it is a
  /// separate list rather than more names in that one: an enricher is handed
  /// the bindings it is extending and answers a map, where a `@when` is handed
  /// the row and answers a yes or a no.
  enriches : Array[String]
  /// The scope form: called about no row at all, and answering the bindings a
  /// whole subtree is rendered with.
  bind_withs : Array[String]
  /// Intents this BUNDLE serves; registered into its own scope on the `lex`
  /// leg, so its components find them before the host's.
  serves : Array[String]
  /// What this component PUBLISHES to its subtree: a name, and the source text
  /// that produces it.
  ///
  /// A lowercase name publishes a VALUE and takes an addressable path
  /// (`.field`, `.seq[.key]`), because a provide doubles as the path a
  /// `<x render="*name">` resumes through. An uppercase name publishes the
  /// component itself as a TYPE, and `"self"` is the only thing it can be.
  ///
  /// The host evaluates these against the guest instance while rendering, the
  /// same way it evaluates one a host component declared — a provide reads a
  /// field, and reading a guest's field is what `get-field` is for. So a
  /// module gets dynamic bindings with nothing added to the guest ABI.
  provide : Array[(String, String)]
  /// What it asks its ancestors for: a name, and the fallback expression to
  /// use when nothing above provides it (`""` for none). A lookup names what
  /// it WANTS, not who supplies it.
  lookup : Array[(String, String)]
  /// Named initial states (the guest's `tutuca/init` fixtures).
  inits : Array[DynInitDef]
  style : String
} derive(Debug, Eq)

///|
pub(all) struct DynManifest {
  api_version : Int
  module_name : String
  /// Catalog metadata. All four are ADVISORY: the host shows them, nothing
  /// resolves against them, and a module's identity is the hash of the archive
  /// it arrived in rather than anything it says about itself.
  doc : String
  version : String
  homepage : String
  authors : Array[String]
  /// The variables this module reads, declared with defaults. Empty for every
  /// module that is the same everywhere it runs, which is most of them.
  config : Array[DynConfigDef]
  components : Array[DynComponentDef]
  /// The `<template id="macro:name">` declarations this module carries.
  ///
  /// Module-level rather than per component, because that is what a macro IS: a
  /// piece of markup a view expands, registered in the scope every component of
  /// the module is registered in. It has no behaviour, no state and no schema —
  /// which is the reason a module can have macros while a guest cannot have
  /// children.
  macros : Array[DynMacroDef]
} derive(Debug, Eq)

///|
/// One macro: its name, its `data-` defaults, and the markup it expands to.
///
/// The same two fields `@anode.Macro` holds, because that is what this becomes
/// — `register_module` hands them straight to `register_macros`. Nothing here
/// is compiled ahead of time: a module's views arrive as markup and so does
/// this.
pub(all) struct DynMacroDef {
  name : String
  defaults : Map[String, String]
  html : String
} derive(Debug, Eq)

///|
/// The manifest api-version this host implements. A module declaring anything
/// else is refused rather than adapted: the contract is small enough that a
/// shim would cost more than a rebuild of the guest.
pub let supported_api_version : Int = 10

///|
/// The archive JSON shape paired with `supported_api_version`.
pub let supported_manifest_version : Int = 3

///|
suberror ManifestError {
  ManifestError(String)
} derive(Debug)

///|
/// Why the module was refused, as a sentence for whoever is looking at the
/// page. The error stays abstract outside this package — a caller has nothing
/// to do with its shape — but the reason is the entire point of raising it,
/// so that much is public.
pub fn ManifestError::message(self : ManifestError) -> String {
  let ManifestError(msg) = self
  msg
}

///|
fn str_field(
  m : Map[String, Json],
  name : String,
) -> String raise ManifestError {
  match m.get(name) {
    Some(String(s)) => s
    _ => raise ManifestError("manifest: missing string field \{name}")
  }
}

///|
fn str_array(
  m : Map[String, Json],
  name : String,
) -> Array[String] raise ManifestError {
  match m.get(name) {
    Some(Array(items)) => {
      let out = []
      for item in items {
        match item {
          String(s) => out.push(s)
          _ => raise ManifestError("manifest: \{name} must be strings")
        }
      }
      out
    }
    None => []
    _ => raise ManifestError("manifest: \{name} must be an array")
  }
}

///|
fn int_field(m : Map[String, Json], name : String) -> Int raise ManifestError {
  match m.get(name) {
    Some(Number(n, ..)) => n.to_int()
    _ => raise ManifestError("manifest: missing number field \{name}")
  }
}

///|
/// A string the manifest MAY carry. Every doc/metadata field added in v3 is
/// optional in this sense: a guest that says nothing gets "", not a rejection.
/// A hand-written manifest in a test should not have to spell out six blanks,
/// and a module that has nothing to say about itself is not a broken module.
fn opt_str(m : Map[String, Json], name : String) -> String {
  match m.get(name) {
    Some(String(s)) => s
    _ => ""
  }
}

///|
/// A WIT `option<f64>` / `option<u32>`: absent or null both read as None.
fn opt_num(m : Map[String, Json], name : String) -> Double? {
  match m.get(name) {
    Some(Number(n, ..)) => Some(n)
    _ => None
  }
}

///|
fn opt_int(m : Map[String, Json], name : String) -> Int? {
  match opt_num(m, name) {
    Some(n) => Some(n.to_int())
    None => None
  }
}

///|
fn bool_field(m : Map[String, Json], name : String) -> Bool {
  m.get(name) is Some(True)
}

///|
/// A JSON-text member of `constraint`, decoded into the value world. "" is the
/// contract's spelling for "not stated", and unparseable text is treated the
/// same way — a constraint the host cannot read is a constraint it must not
/// enforce.
fn opt_json_value(m : Map[String, Json], name : String) -> @tutuca.Value? {
  let text = opt_str(m, name)
  if text == "" {
    return None
  }
  let parsed = @json.parse(text) catch { _ => return None }
  Some(@tutuca.Value::from_json(parsed))
}

///|
/// A field's bounds, in either wire form.
///
/// `"domains"` is the form: an array of `@tutuca.Domain`, the same vocabulary
/// the runtime checks a write against and a `where` clause parses into.
///
/// `"constraint"` is the OLD one, kept for one release: a record of eight
/// optional members that said seven of the same things in a second vocabulary,
/// with a `default` that was never a bound at all. It is read into domains
/// here so nothing downstream has to know there were ever two.
fn parse_field_domains(m : Map[String, Json]) -> Array[@tutuca.Domain] {
  if m.get("domains") is Some(d) {
    return @tutuca.domains_of_json(d).map(fd => fd.domain)
  }
  guard m.get("constraint") is Some(Object(c)) else { return [] }
  let out : Array[@tutuca.Domain] = []
  if opt_num(c, "min") is Some(n) {
    out.push(DCompare(op=DGe, rhs=DLit(n)))
  }
  if opt_num(c, "max") is Some(n) {
    out.push(DCompare(op=DLe, rhs=DLit(n)))
  }
  if opt_int(c, "minLen") is Some(n) {
    out.push(DLen(DCompare(op=DGe, rhs=DLit(n.to_double()))))
  }
  if opt_int(c, "maxLen") is Some(n) {
    out.push(DLen(DCompare(op=DLe, rhs=DLit(n.to_double()))))
  }
  let pattern = opt_str(c, "pattern")
  if pattern != "" {
    out.push(DPattern(pattern))
  }
  let format = opt_str(c, "format")
  if format != "" {
    out.push(DFormat(format))
  }
  if opt_json_value(c, "enumJson") is Some(List(items)) {
    out.push(DOneOf(items))
  }
  out
}

///|
/// What a form pre-fills, in either wire form: a field-level `"default"`, or
/// the old `constraint.defaultJson` for one release.
fn parse_field_default(m : Map[String, Json]) -> @tutuca.Value? {
  if opt_json_value(m, "default") is Some(v) {
    return Some(v)
  }
  guard m.get("constraint") is Some(Object(c)) else { return None }
  opt_json_value(c, "defaultJson")
}

///|
/// `message-docs` as a lookup, which is how every reader wants it. Entries
/// without a name are dropped rather than keyed on "".
fn parse_message_docs(c : Map[String, Json]) -> Map[String, String] {
  let out : Map[String, String] = Map([])
  guard c.get("messageDocs") is Some(Array(items)) else { return out }
  for item in items {
    guard item is Object(d) else { continue }
    let name = opt_str(d, "name")
    if name != "" {
      out[name] = opt_str(d, "doc")
    }
  }
  out
}

///|
/// One wiring section: `[{"name": …, "source": …}]` for a provide,
/// `[{"name": …, "default": …}]` for a lookup.
///
/// One reader for both, because the two differ only in what the second key is
/// called and a manifest that spelled them two ways would be two formats. An
/// entry with no name is dropped: it names nothing, so there is nothing it
/// could wire.
fn parse_wiring(c : Map[String, Json], key : String) -> Array[(String, String)] {
  let out : Array[(String, String)] = []
  guard c.get(key) is Some(Array(items)) else { return out }
  for item in items {
    guard item is Object(d) else { continue }
    let name = opt_str(d, "name")
    if name == "" {
      continue
    }
    let value = if key == "provide" {
      opt_str(d, "source")
    } else {
      opt_str(d, "default")
    }
    out.push((name, value))
  }
  out
}

///|
/// The variables a module declares. A malformed entry RAISES rather than
/// being kept: a config var with no name or an unreadable type is not a
/// declaration at all — nothing can be bound to it and nothing can refuse it,
/// so letting it through would leave a `host.name` in the views with no way to
/// say what went wrong.
fn parse_config(
  root : Map[String, Json],
) -> Array[DynConfigDef] raise ManifestError {
  let out : Array[DynConfigDef] = []
  guard root.get("config") is Some(Array(items)) else { return out }
  let seen : Array[String] = []
  for item in items {
    guard item is Object(r) else {
      raise ManifestError("manifest: bad config entry")
    }
    let name = opt_str(r, "name")
    guard name != "" else {
      raise ManifestError("manifest: a config entry has no name")
    }
    if seen.contains(name) {
      raise ManifestError("manifest: config declares '\{name}' twice")
    }
    seen.push(name)
    let raw_ty = opt_str(r, "type")
    guard @policy.ConfigTy::parse(raw_ty) is Some(ty) else {
      raise ManifestError(
        "manifest: config '\{name}' has type '\{raw_ty}', which is not one of origin, text, bool, number",
      )
    }
    out.push({
      name,
      ty,
      default_: opt_str(r, "default"),
      doc: opt_str(r, "doc"),
    })
  }
  out
}

///|
/// The module's macros. Absent is the common case and means none.
fn parse_macros(
  root : Map[String, Json],
) -> Array[DynMacroDef] raise ManifestError {
  let out : Array[DynMacroDef] = []
  guard root.get("macros") is Some(Array(items)) else { return out }
  let seen : Array[String] = []
  for item in items {
    guard item is Object(r) else {
      raise ManifestError("manifest: bad macro entry")
    }
    let name = opt_str(r, "name")
    guard name != "" else {
      raise ManifestError("manifest: a macro entry has no name")
    }
    // Two macros of one name is the same failure two templates of one id are,
    // and the loader has no way to choose between them.
    if seen.contains(name) {
      raise ManifestError("manifest: macros declare '\{name}' twice")
    }
    seen.push(name)
    let defaults : Map[String, String] = Map([])
    match r.get("defaults") {
      Some(Object(d)) =>
        for k, v in d {
          defaults[k] = match v {
            String(t) => t
            other => other.stringify()
          }
        }
      _ => ()
    }
    out.push({ name, defaults, html: opt_str(r, "html"), })
  }
  out
}

///|
/// The declared fields of a component, in declaration order.
pub fn DynComponentDef::field_infos(
  self : DynComponentDef,
) -> Array[@tutuca.FieldInfo] {
  self.fields.map(f => @tutuca.FieldInfo::new(f.name, f.ty))
}

///|
/// The declared type of one member: the type itself, as a tree
/// (`@tutuca.Ty::of_json`). Anything else is `TyAny`, the honest "cannot say"
/// for a kind the host does not recognize.
fn parse_member_ty(m : Map[String, Json]) -> @tutuca.Ty {
  match m.get("ty") {
    Some(Object(_) as j) => @tutuca.Ty::of_json(j)
    _ => TyAny
  }
}

///|
fn parse_properties(
  c : Map[String, Json],
) -> Array[DynPropertyDef] raise ManifestError {
  guard c.get("properties") is Some(Array(items)) else {
    raise ManifestError("manifest: missing properties array")
  }
  let out : Array[DynPropertyDef] = []
  for item in items {
    guard item is Object(p) else {
      raise ManifestError("manifest: bad property-def")
    }
    out.push({
      name: str_field(p, "name"),
      ty: parse_member_ty(p),
      public_: bool_field(p, "public"),
      writable: bool_field(p, "writable"),
      doc: opt_str(p, "doc"),
    })
  }
  out
}

///|
/// A PROTOCOL's property list, which is the same shape as a component's with
/// one spelling more: a bare string, meaning a member named and not typed.
///
/// The extra spelling is not a convenience. A protocol is an INTERFACE, and a
/// manifest written by hand — or by a compiler that had only the member list —
/// can name what it requires without claiming a type for it; such a member
/// reads back as `TyAny`, which is what "cannot say" is spelled everywhere
/// else here.
/// Refusing it would take a whole module down over a member list that named
/// its members correctly.
///
/// Absent or malformed entries are SKIPPED rather than raised, which is the
/// stance `parse_protocols` already takes one level up: a protocol nobody can
/// read is a protocol the host does not offer, and the components around it
/// still register.
fn parse_protocol_properties(c : Map[String, Json]) -> Array[DynPropertyDef] {
  let out : Array[DynPropertyDef] = []
  guard c.get("properties") is Some(Array(items)) else { return out }
  for item in items {
    match item {
      String(name) =>
        out.push({ name, ty: TyAny, public_: true, writable: false, doc: "", })
      Object(p) =>
        out.push({
          name: opt_str(p, "name"),
          ty: parse_member_ty(p),
          // A protocol member is public by definition — it is what the
          // protocol PROMISES — so a projection that omits the flag is not
          // saying "private".
          public_: match p.get("public") {
            Some(v) => v is True
            None => true
          },
          writable: bool_field(p, "writable"),
          doc: opt_str(p, "doc"),
        })
      _ => ()
    }
  }
  out
}

///|
pub fn DynComponentDef::property_infos(
  self : DynComponentDef,
) -> Array[@tutuca.PropertyInfo] {
  self.properties.map(p => {
    name: p.name,
    ty: p.ty,
    public_: p.public_,
    writable: p.writable,
  })
}

///|
/// The named initial states of one component. An entry whose `argsJson` is not
/// a JSON object is dropped: a fixture the host cannot read is a fixture it
/// must not offer.
fn parse_inits(c : Map[String, Json]) -> Array[DynInitDef] raise ManifestError {
  let out : Array[DynInitDef] = []
  guard c.get("inits") is Some(Array(items)) else { return out }
  for item in items {
    guard item is Object(i) else {
      raise ManifestError("manifest: bad init-def")
    }
    let name = str_field(i, "name")
    let args : Map[String, @tutuca.Value] = Map([])
    let parsed = @json.parse(str_field(i, "argsJson")) catch {
      _ => Json::null()
    }
    guard parsed is Object(fields) else { continue }
    for k, v in fields {
      args[k] = @tutuca.Value::from_json(v)
    }
    let tags : Array[String] = []
    if i.get("tags") is Some(Array(items)) {
      for t in items {
        if t is String(t) {
          tags.push(t)
        }
      }
    }
    out.push({
      name,
      args,
      doc: opt_str(i, "doc"),
      view: opt_str(i, "view"),
      tags,
      default_: i.get("default") is Some(True),
      drive_json: opt_str(i, "driveJson"),
      intents_json: opt_str(i, "intentsJson"),
    })
  }
  out
}

///|
/// Parse the JSON projection of a module's manifest — what `tgc.describe`
/// answers, in camelCase keys.
fn parse_protocols(
  c : Map[String, Json],
) -> Array[DynProtocolDef] raise ManifestError {
  let out : Array[DynProtocolDef] = []
  guard c.get("protocols") is Some(Array(items)) else { return out }
  for item in items {
    guard item is Object(p) else { continue }
    out.push({
      id: str_field(p, "id"),
      handle_messages: str_array(p, "handleMessages"),
      handle_intents: str_array(p, "handleIntents"),
      express_messages: str_array(p, "expressMessages"),
      express_intents: str_array(p, "expressIntents"),
      properties: parse_protocol_properties(p),
      views: str_array(p, "views"),
      provides: str_array(p, "provides"),
      lookups: str_array(p, "lookups"),
    })
  }
  out
}

///|
fn parse_protocol_bindings(
  c : Map[String, Json],
  key : String,
) -> Array[DynProtocolBinding] raise ManifestError {
  let out : Array[DynProtocolBinding] = []
  guard c.get(key) is Some(Array(items)) else { return out }
  for item in items {
    guard item is Object(b) else { continue }
    out.push({
      protocol_id: str_field(b, "protocolId"),
      member_name: str_field(b, "member"),
      source: str_field(b, "source"),
    })
  }
  out
}

///|
pub fn DynManifest::from_json_string(
  s : String,
) -> DynManifest raise ManifestError {
  // The bridge's own JSON, so a parse failure here is a bridge bug rather than
  // a guest one — but it is still a refusal a page has to be able to show, so
  // it becomes the same error as everything else this function reports.
  let parsed = @json.parse(s) catch {
    e => raise ManifestError("manifest: not JSON (\{e})")
  }
  guard parsed is Object(root) else {
    raise ManifestError("manifest: not a JSON object")
  }
  let manifest_version = int_field(root, "manifestVersion")
  if manifest_version != supported_manifest_version {
    raise ManifestError(
      "manifest: unsupported manifestVersion \{manifest_version} (host supports \{supported_manifest_version})",
    )
  }
  let api_version = int_field(root, "apiVersion")
  if api_version != supported_api_version {
    raise ManifestError(
      "manifest: unsupported apiVersion \{api_version} (host supports \{supported_api_version})",
    )
  }
  let module_name = str_field(root, "moduleName")
  guard root.get("components") is Some(Array(comps_json)) else {
    raise ManifestError("manifest: missing components")
  }
  let components = []
  for cj in comps_json {
    guard cj is Object(c) else {
      raise ManifestError("manifest: bad component")
    }
    guard c.get("views") is Some(Array(views_json)) else {
      raise ManifestError("manifest: component without views")
    }
    let views = []
    for vj in views_json {
      guard vj is Object(v) else { raise ManifestError("manifest: bad view") }
      views.push({ name: str_field(v, "name"), html: str_field(v, "html"), })
    }
    let fields : Array[DynFieldDef] = []
    match c.get("fields") {
      Some(Array(fs)) =>
        for fj in fs {
          guard fj is Object(f) else {
            raise ManifestError("manifest: bad field-def")
          }
          fields.push({
            name: str_field(f, "name"),
            ty: parse_member_ty(f),
            doc: opt_str(f, "doc"),
            required: bool_field(f, "required"),
            domains: parse_field_domains(f),
            default: parse_field_default(f),
          })
        }
      _ => ()
    }
    components.push({
      name: str_field(c, "name"),
      doc: opt_str(c, "doc"),
      keywords: str_array(c, "keywords"),
      category: opt_str(c, "category"),
      message_docs: parse_message_docs(c),
      views,
      fields,
      properties: parse_properties(c),
      domains: match c.get("domains") {
        Some(d) => @tutuca.domains_of_json(d)
        None => []
      },
      receives: str_array(c, "receives"),
      intents: str_array(c, "intents"),
      express_messages: str_array(c, "expressMessages"),
      express_intents: str_array(c, "expressIntents"),
      implements: str_array(c, "implements"),
      protocols: parse_protocols(c),
      property_bindings: parse_protocol_bindings(c, "propertyBindings"),
      view_bindings: parse_protocol_bindings(c, "viewBindings"),
      provide_bindings: parse_protocol_bindings(c, "provideBindings"),
      lookup_bindings: parse_protocol_bindings(c, "lookupBindings"),
      methods: str_array(c, "methods"),
      whens: str_array(c, "whens"),
      enriches: str_array(c, "enriches"),
      bind_withs: str_array(c, "bindWiths"),
      serves: str_array(c, "serves"),
      provide: parse_wiring(c, "provide"),
      lookup: parse_wiring(c, "lookup"),
      inits: parse_inits(c),
      style: str_field(c, "style"),
    })
  }
  {
    api_version,
    module_name,
    doc: opt_str(root, "doc"),
    version: opt_str(root, "version"),
    homepage: opt_str(root, "homepage"),
    authors: str_array(root, "authors"),
    config: parse_config(root),
    components,
    macros: parse_macros(root),
  }
}
