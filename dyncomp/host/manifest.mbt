///| The bundle's static `manifest.json`, after the bridge hydrates its view
/// files and serializes it to the host. Views are tutuca template strings
/// compiled host-side; the declared schema — fields over a flat type table,
/// plus the message buckets — becomes the `SchemaInfo` every generic-access
/// seam reads (see `register_bundle`).

///|
pub(all) struct DynViewDef {
  name : String
  html : String
} derive(Debug, Eq)

///|
/// One entry of a component's flat type table. WIT has no recursive types, so
/// a compound points at its parts by index; `to_ty_info` rebuilds the nesting.
pub(all) struct DynTyDef {
  kind : String
  elem : Int?
  items : Array[Int]
  name : String
  members : Array[String]
} derive(Debug, Eq)

///|
pub(all) struct DynFieldDef {
  name : String
  ty : Int
  /// What the field is FOR. The one fact neither the type table nor the views
  /// can supply, and what a search index ranks on.
  doc : String
  required : Bool
  constraint : @jsonschema.Constraint?
} derive(Debug, Eq)

///|
/// One variable this bundle reads, as the bundle DECLARES it: a name, what
/// kind of thing it is, what it is worth when nobody says otherwise, and what
/// it is for.
///
/// The declaration is half of a contract, and the host's binding is the other
/// half — both state the type, and `resolve_config` refuses a bundle where
/// they disagree. See `@policy.with_config` for why the redundancy is the
/// point rather than an oversight.
///
/// The default reaches the GUEST, which is what lets a bundle be sensible on a
/// host that bound nothing. It does not reach a view: an `origin` default that
/// opened a URL sink would be a bundle granting itself an origin.
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
  /// Sentences for the names in views / `receives` / `bubbles` /
  /// `responses` / `methods` / `requests`, merged by name — one table rather
  /// than a doc field on six parallel lists.
  message_docs : Map[String, String]
  views : Array[DynViewDef]
  types : Array[DynTyDef]
  fields : Array[DynFieldDef]
  receives : Array[String]
  bubbles : Array[String]
  responses : Array[String]
  methods : Array[String]
  /// Callables a view's `@when` names (the render-time namespace).
  whens : Array[String]
  /// Requests this BUNDLE serves; registered into its own scope, so its
  /// components find them before the host's.
  requests : Array[String]
  /// Named initial states (the guest's `tutuca/init` fixtures).
  inits : Array[DynInitDef]
  style : String
} derive(Debug, Eq)

///|
pub(all) struct DynManifest {
  api_version : Int
  module_name : String
  /// Catalog metadata. All four are ADVISORY: the host shows them, nothing
  /// resolves against them, and a bundle's identity is the hash of the archive
  /// it arrived in rather than anything it says about itself.
  doc : String
  version : String
  homepage : String
  authors : Array[String]
  capabilities : Array[@policy.CapabilityReq]
  /// The variables this bundle reads, declared with defaults. Empty for every
  /// bundle that is the same everywhere it runs, which is most of them.
  config : Array[DynConfigDef]
  components : Array[DynComponentDef]
} derive(Debug, Eq)

///|
/// The manifest api-version this host implements. A bundle declaring anything
/// else is refused rather than adapted: the contract is small enough that a
/// shim would cost more than a rebuild of the guest.
pub let supported_api_version : Int = 7

///|
suberror ManifestError {
  ManifestError(String)
} derive(Debug)

///|
/// Why the bundle was refused, as a sentence for whoever is looking at the
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
/// The contract requires them to be present, but jco drops an empty option and
/// a hand-written manifest in a test should not have to spell out six blanks.
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
fn parse_constraint(m : Map[String, Json]) -> @jsonschema.Constraint? {
  guard m.get("constraint") is Some(Object(c)) else { return None }
  let enum_values = match opt_json_value(c, "enumJson") {
    Some(List(items)) => Some(items)
    _ => None
  }
  Some({
    min: opt_num(c, "min"),
    max: opt_num(c, "max"),
    min_len: opt_int(c, "minLen"),
    max_len: opt_int(c, "maxLen"),
    pattern: opt_str(c, "pattern"),
    format: opt_str(c, "format"),
    enum_values,
    default: opt_json_value(c, "defaultJson"),
  })
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
/// The capabilities a bundle asks for. An unknown name is KEPT as
/// `CapUnknown` rather than dropped: the host refuses a bundle it cannot
/// fully understand, and a dropped name would look like a bundle that asked
/// for nothing.
fn parse_capabilities(root : Map[String, Json]) -> Array[@policy.CapabilityReq] {
  let out : Array[@policy.CapabilityReq] = []
  guard root.get("capabilities") is Some(Array(items)) else { return out }
  for item in items {
    guard item is Object(r) else { continue }
    // An unknown name is KEPT (`CapUnknown`) rather than dropped: the host
    // refuses a bundle it cannot fully understand, and a dropped name would
    // look like a bundle that asked for nothing.
    let cap = @policy.Capability::parse(opt_str(r, "cap"))
    out.push({ cap, reason: opt_str(r, "reason") })
  }
  out
}

///|
/// The variables a bundle declares. Unlike `parse_capabilities`, a malformed
/// entry RAISES rather than being kept as an unknown: a capability's name is
/// the only thing a host has to judge it by, so an unrecognized one is still
/// information, while a config var with no name or an unreadable type is not a
/// declaration at all — nothing can be bound to it and nothing can refuse it,
/// so letting it through would leave a `$$name` in the views with no way to
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
fn parse_types(c : Map[String, Json]) -> Array[DynTyDef] raise ManifestError {
  let out : Array[DynTyDef] = []
  guard c.get("types") is Some(Array(items)) else { return out }
  for item in items {
    guard item is Object(t) else { raise ManifestError("manifest: bad ty-def") }
    let elem = match t.get("elem") {
      Some(Number(n, ..)) => Some(n.to_int())
      _ => None
    }
    let indices : Array[Int] = []
    match t.get("items") {
      Some(Array(is_)) =>
        for i in is_ {
          match i {
            Number(n, ..) => indices.push(n.to_int())
            _ => raise ManifestError("manifest: ty-def items must be numbers")
          }
        }
      _ => ()
    }
    out.push({
      kind: str_field(t, "kind"),
      elem,
      items: indices,
      name: match t.get("name") {
        Some(String(s)) => s
        _ => ""
      },
      members: str_array(t, "members"),
    })
  }
  out
}

///|
/// The declared type at `index`, rebuilt from the flat table.
///
/// `depth` is the cycle guard, and it is why this cannot loop: a table entry
/// may point at any index, including its own, and the manifest crossed a
/// boundary — a host that trusted it to be acyclic would hang on a guest bug.
/// An entry past the guard reads as `TyAny`, the honest "cannot say".
fn ty_info_at(
  types : Array[DynTyDef],
  index : Int,
  depth? : Int = 0,
) -> @tutuca.TyInfo {
  if depth > 16 || index < 0 || index >= types.length() {
    return TyAny
  }
  let t = types[index]
  let inner = () => {
    match t.elem {
      Some(e) => ty_info_at(types, e, depth=depth + 1)
      None => TyAny
    }
  }
  match t.kind {
    "ty-bool" => TyBool
    "ty-int" => TyInt
    "ty-float" => TyFloat
    "ty-text" => TyText
    "ty-list" => TyList(inner())
    "ty-option" => TyOption(inner())
    "ty-omap" => TyOMap(inner())
    "ty-tuple" =>
      TyTuple(t.items.map(i => ty_info_at(types, i, depth=depth + 1)))
    "ty-record" => TyRecord(t.name)
    "ty-enum" => TyEnum(t.name)
    "ty-variant" => TyVariant(t.name)
    "ty-flags" => TyFlags(t.name, t.members)
    "ty-set" => TySet
    // "" is the bare `component` marker: a slot whose component the guest did
    // not name, which `slots~` names for a host component and nothing names
    // here — so it stays unnamed rather than becoming a wrong name.
    "ty-comp" => TyComp(if t.name == "" { None } else { Some(t.name) })
    // A `tables.table`. Unlike `ty-record`, this one carries no name because
    // there is nothing to name — the shape is the contract's, so the host can
    // describe and check it without asking the guest anything.
    "ty-table" => TyTable
    _ => TyAny
  }
}

///|
/// The declared fields of a component, in declaration order.
pub fn DynComponentDef::field_infos(
  self : DynComponentDef,
) -> Array[@tutuca.FieldInfo] {
  self.fields.map(f => {
    @tutuca.FieldInfo::new(f.name, ty_info_at(self.types, f.ty))
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
    out.push({ name, args, doc: opt_str(i, "doc") })
  }
  out
}

///|
/// Parse the JSON projection of a guest manifest. The JS bridge produces it
/// with JSON.stringify over the jco-lifted record (camelCase keys).
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
      views.push({ name: str_field(v, "name"), html: str_field(v, "html") })
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
            ty: int_field(f, "ty"),
            doc: opt_str(f, "doc"),
            required: bool_field(f, "required"),
            constraint: parse_constraint(f),
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
      types: parse_types(c),
      fields,
      receives: str_array(c, "receives"),
      bubbles: str_array(c, "bubbles"),
      responses: str_array(c, "responses"),
      methods: str_array(c, "methods"),
      whens: str_array(c, "whens"),
      requests: str_array(c, "requests"),
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
    capabilities: parse_capabilities(root),
    config: parse_config(root),
    components,
  }
}
