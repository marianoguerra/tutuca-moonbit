///| SchemaInfo -> JSON Schema (draft 2020-12).
///
/// The projection is total: every `TyInfo` has an answer, including the ones
/// the schema cannot open. `TyRecord` / `TyEnum` / `TyVariant` carry a name and
/// nothing else — core's comment says so outright, "enough to label it, not
/// enough to open it" — so they become a `$ref` to a titled but unconstrained
/// `$defs` entry. That is the honest projection: it names the type and admits
/// it cannot describe it, which is what lets a form draw "opaque, edit as JSON"
/// under the right label instead of guessing.

///|
/// The `$defs` key a component-slot field points at. A `TyComp` field is not
/// filled by JSON at all — the host builds the child (`make-instance`) — so
/// what a caller can supply is a REFERENCE to a component, which is exactly
/// what the surface patch algebra's `BindInstance` takes.
pub let component_ref_def : String = "componentRef"

///|
fn obj(entries : Array[(String, Json)]) -> Json {
  let m : Map[String, Json] = Map([])
  for e in entries {
    m[e.0] = e.1
  }
  Json::object(m)
}

///|
/// Add a key to a schema that is known to be an object. A `true` schema (what
/// `TyAny` projects to) has nowhere to put one, so it is returned untouched
/// rather than being silently promoted into an object — `true` already permits
/// what the key would have permitted.
fn with_key(schema : Json, key : String, v : Json) -> Json {
  match schema {
    Object(m) => {
      let out : Map[String, Json] = Map([])
      for k, existing in m {
        out[k] = existing
      }
      out[key] = v
      Json::object(out)
    }
    _ => schema
  }
}

///|
/// The `$defs` a projection accumulated. Named types are collected as they are
/// met rather than walked for up front, because the same record can appear in
/// three fields and must produce one entry.
priv struct Defs {
  entries : Map[String, Json]
}

///|
fn Defs::named(self : Defs, name : String) -> Json {
  let key = if name == "" { "unnamed" } else { name }
  if !self.entries.contains(key) {
    // Unconstrained on purpose: the declared schema knows the NAME of a record
    // and not its fields. Claiming `type: object` here would be inventing a
    // fact — a declared `enum` is a string, not an object — so the entry says
    // only what it is called.
    self.entries[key] = obj([("title", Json::string(key))])
  }
  obj([("$ref", Json::string("#/$defs/\{key}"))])
}

///|
fn Defs::component_ref(self : Defs, comp : String?) -> Json {
  if !self.entries.contains(component_ref_def) {
    self.entries[component_ref_def] = obj([
      ("title", Json::string("Component reference")),
      (
        "description",
        Json::string(
          "A component to instantiate, not an inline value: the host builds it and holds the instance.",
        ),
      ),
      ("type", Json::string("object")),
      (
        "properties",
        obj([
          ("module", obj([("type", Json::string("string"))])),
          ("name", obj([("type", Json::string("string"))])),
          (
            "init",
            obj([
              ("type", Json::string("string")),
              (
                "description",
                Json::string(
                  "A named init fixture, or \"\" for the bare constructor.",
                ),
              ),
            ]),
          ),
        ]),
      ),
      ("required", Json::array([Json::string("module"), Json::string("name")])),
    ])
  }
  let base = obj([("$ref", Json::string("#/$defs/\{component_ref_def}"))])
  // The slot's declared component, when it named one. It is a description
  // rather than a constraint: nothing here can check that a reference resolves
  // to that component, and a schema that pretended to would be lying.
  match comp {
    Some(c) if c != "" =>
      with_key(base, "description", Json::string("Must be a \{c}."))
    _ => base
  }
}

///|
/// One declared type as a schema. `TyOption` is NOT handled here — an optional
/// field is expressed by leaving the name out of `required`, which is how JSON
/// Schema says it, so unwrapping happens at the field level.
fn ty_schema(ty : @tutuca.TyInfo, defs : Defs) -> Json {
  match ty {
    TyBool => obj([("type", Json::string("boolean"))])
    TyInt => obj([("type", Json::string("integer"))])
    TyFloat => obj([("type", Json::string("number"))])
    TyText => obj([("type", Json::string("string"))])
    TyList(e) =>
      obj([("type", Json::string("array")), ("items", ty_schema(e, defs))])
    TyTuple(ts) =>
      // A tuple is a fixed-length array: prefixItems pins the members and
      // `items: false` is what forbids a tenth one.
      obj([
        ("type", Json::string("array")),
        ("prefixItems", Json::array(ts.map(t => ty_schema(t, defs)))),
        ("items", Json::boolean(false)),
        ("minItems", Json::number(ts.length().to_double())),
      ])
    TyOption(e) => ty_schema(e, defs)
    TyOMap(v) =>
      obj([
        ("type", Json::string("object")),
        ("additionalProperties", ty_schema(v, defs)),
      ])
    TyFlags(_, members) =>
      // A closed set: the members are the one thing about it only the schema
      // knows, since the encoded value is just a Map.
      obj([
        ("type", Json::string("array")),
        ("uniqueItems", Json::boolean(true)),
        (
          "items",
          obj([("enum", Json::array(members.map(m => Json::string(m))))]),
        ),
      ])
    TySet =>
      obj([
        ("type", Json::string("array")),
        ("uniqueItems", Json::boolean(true)),
        ("items", obj([("type", Json::string("string"))])),
      ])
    TyRecord(n) | TyEnum(n) | TyVariant(n) => defs.named(n)
    TyComp(c) => defs.component_ref(c)
    // The one named shape this projection describes rather than merely labels
    // — see table_defs.mbt for why that asymmetry is the point.
    TyTable => defs.table()
    // JSON Schema's `true` is "anything", which is exactly what `any` declares.
    TyAny => Json::boolean(true)
  }
}

///|
/// Apply the half a type cannot state. Which keyword a bound becomes depends on
/// what it is bounding: `min`/`max` are numeric, `min_len`/`max_len` are a
/// length, and a length means characters on a string and elements on an array.
fn apply_constraint(schema : Json, ty : @tutuca.TyInfo, c : Constraint) -> Json {
  let mut out = schema
  if c.min is Some(n) {
    out = with_key(out, "minimum", Json::number(n))
  }
  if c.max is Some(n) {
    out = with_key(out, "maximum", Json::number(n))
  }
  let (min_kw, max_kw) = match ty {
    TyList(_) | TyTuple(_) | TyFlags(_, _) | TySet => ("minItems", "maxItems")
    TyOMap(_) => ("minProperties", "maxProperties")
    _ => ("minLength", "maxLength")
  }
  if c.min_len is Some(n) {
    out = with_key(out, min_kw, Json::number(n.to_double()))
  }
  if c.max_len is Some(n) {
    out = with_key(out, max_kw, Json::number(n.to_double()))
  }
  if c.pattern != "" {
    out = with_key(out, "pattern", Json::string(c.pattern))
  }
  if c.format != "" {
    out = with_key(out, "format", Json::string(c.format))
  }
  if c.enum_values is Some(vs) {
    out = with_key(out, "enum", Json::array(vs.map(v => v.to_json())))
  }
  if c.default is Some(v) {
    out = with_key(out, "default", v.to_json())
  }
  out
}

///|
/// One field's schema: its type, the constraint over it, and its sentence.
fn field_schema(f : @tutuca.FieldInfo, fd : FieldDoc, defs : Defs) -> Json {
  let mut s = ty_schema(f.ty, defs)
  if fd.constraint is Some(c) {
    s = apply_constraint(s, f.ty, c)
  }
  if fd.doc != "" {
    s = with_key(s, "description", Json::string(fd.doc))
  }
  s
}

///|
/// Whether a field must be supplied. An optional TYPE is never required no
/// matter what the manifest claimed — `option<T>` says the absence is a legal
/// value, and a schema that then demanded the key would contradict it.
fn is_required(f : @tutuca.FieldInfo, fd : FieldDoc) -> Bool {
  if f.ty is TyOption(_) {
    false
  } else {
    fd.required
  }
}

///|
/// The JSON Schema for constructing an instance of `schema`.
///
/// `docs` is what a manifest carries beyond the type — a field missing from it
/// is described by its type alone, which is what a HOST component gets and is
/// why this works for both.
///
/// The result is an object schema over the declared fields. It is deliberately
/// NOT closed (`additionalProperties` is left unsaid): a constructor may accept
/// arguments that are not declared fields, and refusing them here would make
/// the schema narrower than the thing it describes.
pub fn of_schema(
  schema : @tutuca.SchemaInfo,
  docs? : Map[String, FieldDoc] = Map([]),
  title? : String = "",
  description? : String = "",
) -> Json {
  let defs : Defs = { entries: Map([]) }
  let props : Map[String, Json] = Map([])
  let required : Array[Json] = []
  for f in schema.fields {
    let fd = docs.get(f.name).unwrap_or(FieldDoc::none())
    props[f.name] = field_schema(f, fd, defs)
    if is_required(f, fd) {
      required.push(Json::string(f.name))
    }
  }
  let entries : Array[(String, Json)] = [
    ("$schema", Json::string("https://json-schema.org/draft/2020-12/schema")),
    ("title", Json::string(if title != "" { title } else { schema.name })),
    ("type", Json::string("object")),
    ("properties", Json::object(props)),
  ]
  if description != "" {
    entries.push(("description", Json::string(description)))
  }
  if !required.is_empty() {
    entries.push(("required", Json::array(required)))
  }
  if !defs.entries.is_empty() {
    entries.push(("$defs", Json::object(defs.entries)))
  }
  obj(entries)
}
