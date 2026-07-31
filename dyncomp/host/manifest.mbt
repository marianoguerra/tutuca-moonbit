///| The guest manifest (the WIT `guest.manifest` record), as the host sees it
/// after the bridge serializes it to JSON. Views are tutuca template strings
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
} derive(Debug, Eq)

///|
/// A named initial state the guest declares, with its constructor args already
/// decoded from the manifest's JSON.
pub(all) struct DynInitDef {
  name : String
  args : Map[String, @tutuca.Value]
} derive(Debug, Eq)

///|
pub(all) struct DynComponentDef {
  name : String
  views : Array[DynViewDef]
  types : Array[DynTyDef]
  fields : Array[DynFieldDef]
  /// `@on` names the guest answers itself; anything else a view raises is a
  /// generated mutator the host applies (see DynObj::obj_handler).
  handlers : Array[String]
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
  components : Array[DynComponentDef]
} derive(Debug, Eq)

///|
/// The manifest api-version this host implements. A bundle declaring anything
/// else is refused rather than adapted: the contract is small enough that a
/// shim would cost more than a rebuild of the guest.
pub let supported_api_version : Int = 2

///|
suberror ManifestError {
  ManifestError(String)
} derive(Debug)

///|
fn str_field(m : Map[String, Json], name : String) -> String raise {
  match m.get(name) {
    Some(String(s)) => s
    _ => raise ManifestError("manifest: missing string field \{name}")
  }
}

///|
fn str_array(m : Map[String, Json], name : String) -> Array[String] raise {
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
fn int_field(m : Map[String, Json], name : String) -> Int raise {
  match m.get(name) {
    Some(Number(n, ..)) => n.to_int()
    _ => raise ManifestError("manifest: missing number field \{name}")
  }
}

///|
fn parse_types(c : Map[String, Json]) -> Array[DynTyDef] raise {
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
fn parse_inits(c : Map[String, Json]) -> Array[DynInitDef] raise {
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
    out.push({ name, args })
  }
  out
}

///|
/// Parse the JSON projection of a guest manifest. The JS bridge produces it
/// with JSON.stringify over the jco-lifted record (camelCase keys).
pub fn DynManifest::from_json_string(s : String) -> DynManifest raise {
  guard @json.parse(s) is Object(root) else {
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
          fields.push({ name: str_field(f, "name"), ty: int_field(f, "ty") })
        }
      _ => ()
    }
    components.push({
      name: str_field(c, "name"),
      views,
      types: parse_types(c),
      fields,
      handlers: str_array(c, "handlers"),
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
  { api_version, module_name, components }
}
