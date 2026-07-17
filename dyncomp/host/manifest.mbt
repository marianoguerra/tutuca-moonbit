///| The guest manifest (the WIT `guest.manifest` record), as the host sees it
/// after the bridge serializes it to JSON. Views are tutuca template strings
/// compiled host-side; the handler/method name lists tell DynObj which
/// dispatches to forward to the guest.

///|
pub(all) struct DynViewDef {
  name : String
  html : String
} derive(Debug, Eq)

///|
pub(all) struct DynComponentDef {
  name : String
  views : Array[DynViewDef]
  input_handlers : Array[String]
  receive_handlers : Array[String]
  response_handlers : Array[String]
  method_names : Array[String]
  style : String
} derive(Debug, Eq)

///|
pub(all) struct DynManifest {
  api_version : Int
  module_name : String
  components : Array[DynComponentDef]
} derive(Debug, Eq)

///|
/// The manifest api-version this host implements.
pub let supported_api_version : Int = 1

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
/// Parse the JSON projection of a guest manifest. The JS bridge produces it
/// with JSON.stringify over the jco-lifted record (camelCase keys).
pub fn DynManifest::from_json_string(s : String) -> DynManifest raise {
  guard @json.parse(s) is Object(root) else {
    raise ManifestError("manifest: not a JSON object")
  }
  let api_version = match root.get("apiVersion") {
    Some(Number(n, ..)) => n.to_int()
    _ => raise ManifestError("manifest: missing apiVersion")
  }
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
    components.push({
      name: str_field(c, "name"),
      views,
      input_handlers: str_array(c, "inputHandlers"),
      receive_handlers: str_array(c, "receiveHandlers"),
      response_handlers: str_array(c, "responseHandlers"),
      method_names: str_array(c, "methodNames"),
      style: str_field(c, "style"),
    })
  }
  { api_version, module_name, components }
}
