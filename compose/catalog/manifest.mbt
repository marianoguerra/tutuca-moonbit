///|
/// A module's manifest, projected into palette rows.
///
/// READ DEFENSIVELY, on purpose. A manifest that arrived from a compiler this
/// build does not know should cost the components it cannot read and not the
/// ones it can — a page where one bad component empties the whole palette is a
/// page nobody can recover.
pub fn entries_of_manifest(
  manifest : Json,
  module_? : String = "",
  annotations? : Map[String, Annotation] = Map([]),
) -> Array[Entry] {
  let out : Array[Entry] = []
  guard manifest is Object(root) else { return out }
  let module_doc = str_at(manifest, "doc")
  // The module name comes off the MANIFEST first and the caller's only as a
  // fallback. The compiler derives it from the card, and a caller that named
  // it something else would produce a catalog that can find a component and a
  // host that cannot build it.
  let fallback = if str_at(manifest, "moduleName") != "" {
    str_at(manifest, "moduleName")
  } else {
    module_
  }
  guard root.get("components") is Some(Array(comps)) else { return out }
  for c in comps {
    let name = str_at(c, "name")
    if name == "" {
      continue
    }
    // The component's OWN answer, then the module's. A component says where it
    // came from because that is the only thing that survives being held by
    // somebody else.
    let owner = if str_at(c, "module") != "" {
      str_at(c, "module")
    } else {
      fallback
    }
    let note = annotations.get(name).unwrap_or(Annotation::none())
    out.push({
      ref_: { module_: owner, name, },
      doc: str_at(c, "doc"),
      keywords: note.keywords,
      category: note.category,
      fields: fields_of(c),
      implements: strs_at(c, "implements"),
      messages: [
        ..strs_at(c, "receives"),
        ..strs_at(c, "intents"),
        ..strs_at(c, "methods"),
        ..strs_at(c, "serves"),
      ],
      expresses: [
        ..strs_at(c, "expressMessages"),
        ..strs_at(c, "expressIntents"),
      ],
      properties: properties_of(c),
      presets: note.presets,
      hidden: note.hidden,
      module_doc,
    })
  }
  out
}

///|
fn str_at(j : Json, key : String) -> String {
  match j {
    Object(o) =>
      match o.get(key) {
        Some(String(s)) => s
        _ => ""
      }
    _ => ""
  }
}

///|
fn strs_at(j : Json, key : String) -> Array[String] {
  let out : Array[String] = []
  guard j is Object(o) else { return out }
  guard o.get(key) is Some(Array(items)) else { return out }
  for item in items {
    if item is String(s) {
      out.push(s)
    }
  }
  out
}

///|
/// A field's type, as the manifest spells it.
///
/// The `ty` is a TREE — `{"k":"list","of":{"k":"text"}}` — so the head is what
/// a palette row can show and the rest is what a builder checks against. Only
/// the head is kept here; a form that needed more would ask the schema.
fn ty_head(j : Json) -> String {
  match j {
    Object(o) =>
      match o.get("k") {
        Some(String(k)) => k
        _ => "any"
      }
    _ => "any"
  }
}

///|
fn fields_of(c : Json) -> Array[FieldInfo] {
  let out : Array[FieldInfo] = []
  guard c is Object(o) else { return out }
  guard o.get("fields") is Some(Array(items)) else { return out }
  for f in items {
    let name = str_at(f, "name")
    if name == "" {
      continue
    }
    let required = match f {
      Object(fo) => fo.get("required") is Some(True)
      _ => false
    }
    let ty = match f {
      Object(fo) =>
        match fo.get("ty") {
          Some(t) => ty_head(t)
          None => "any"
        }
      _ => "any"
    }
    out.push({ name, ty, doc: str_at(f, "doc"), required, })
  }
  out
}

///|
/// PUBLIC properties only. A property a component did not mark public is not
/// something anything outside it may read, so listing it would be advertising
/// a door that is shut.
fn properties_of(c : Json) -> Array[String] {
  let out : Array[String] = []
  guard c is Object(o) else { return out }
  guard o.get("properties") is Some(Array(items)) else { return out }
  for p in items {
    let name = str_at(p, "name")
    let public_ = match p {
      Object(po) => po.get("public") is Some(True)
      _ => false
    }
    if name != "" && public_ {
      out.push(name)
    }
  }
  out
}
