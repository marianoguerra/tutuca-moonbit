// The top-level SchemaViewer component and the schema -> component dispatch.
// Split from schema.mbt; same package.

///|
priv struct SchemaViewerState {
  value : @tutuca.Value
  raw : @tutuca.Value
  rawSchema : @tutuca.Value
  showRaw : Bool
} derive(ToJson, FromJson)

///|
/// Holds the classified high-level tree in `value` and a DataInspector of the
/// original schema in `raw`; `showRaw` toggles between them. `rawSchema`
/// keeps the plain schema for inspection.
fn schema_viewer_comp() -> @component.Component {
  @component.component(
    name="SchemaViewer",
    init=SchemaViewerState::{
      value: Null,
      raw: Null,
      rawSchema: Null,
      showRaw: false,
    },
    mutate={
      "toggleIsExpanded": (s : SchemaViewerState, _args) => {
        ..s,
        value: toggle_wrapped(s.value),
      },
    },
    compute={
      "toggleLabel": (s : SchemaViewerState, _args) => {
        Str(if s.showRaw { "high-level view" } else { "raw schema" })
      },
    },
    view=(
      #|<div class="inline-flex flex-col items-start gap-1 schema-viewer">
      #|  <button type="button" class="btn btn-xs btn-ghost self-end raw-toggle" @on.click="$toggleShowRaw" @text="$toggleLabel"></button>
      #|  <x render=".value" @hide=".showRaw"></x>
      #|  <x render=".raw" @show=".showRaw"></x>
      #|</div>
    ),
  )
}

///|
fn has_object_keywords(m : Map[String, @tutuca.Value]) -> Bool {
  match m.get("type") {
    Some(Str("object")) => return true
    Some(List(ts)) => if ts.contains(Str("object")) { return true }
    _ => ()
  }
  m.contains("properties") ||
  m.contains("required") ||
  m.contains("patternProperties") ||
  m.contains("propertyNames") ||
  m.contains("additionalProperties") ||
  present_nn(m, "minProperties") is Some(_) ||
  present_nn(m, "maxProperties") is Some(_)
}

///|
fn has_array_keywords(m : Map[String, @tutuca.Value]) -> Bool {
  match m.get("type") {
    Some(Str("array")) => return true
    Some(List(ts)) => if ts.contains(Str("array")) { return true }
    _ => ()
  }
  m.contains("items") ||
  m.contains("prefixItems") ||
  m.contains("contains") ||
  present_nn(m, "minItems") is Some(_) ||
  present_nn(m, "maxItems") is Some(_) ||
  m.contains("uniqueItems")
}

///|
/// JS classifySchema: dispatch a schema Value to its per-construct component.
pub fn Inspector::classify_schema(
  self : Inspector,
  schema : @tutuca.Value,
) -> @tutuca.Value {
  match schema {
    Bool(b) => self.make_("SchemaBoolean", args={ "value": Bool(b) })
    Map(m) => {
      if m.get("$ref") is Some(Str(target)) {
        return self.make_("SchemaRef", args={ "target": Str(target) })
      }
      if has_object_keywords(m) {
        return self.schema_object_from(m)
      }
      if has_array_keywords(m) {
        return self.schema_array_from(m)
      }
      if m.get("enum") is Some(List(_)) {
        return self.schema_enum_from(m)
      }
      if m.get("const") is Some(cv) {
        return self.make_("SchemaConst", args={
          "value": self.inspect_value(cv),
        })
      }
      if (m.get("allOf") is Some(v) && v.is_truthy()) ||
        (m.get("anyOf") is Some(v) && v.is_truthy()) ||
        (m.get("oneOf") is Some(v) && v.is_truthy()) {
        return self.schema_combinator_from(m)
      }
      if m.get("not") is Some(nv) {
        return self.make_("SchemaNot", args={
          "child": self.classify_schema(nv),
        })
      }
      if m.contains("if") || m.contains("then") || m.contains("else") {
        return self.schema_conditional_from(m)
      }
      self.schema_scalar_from(m)
    }
    // null / non-object schemas render as plain values (JS JsonViewer path)
    _ => self.inspect_value(schema)
  }
}

///|
/// JS SchemaViewer.Class.fromData.
pub fn Inspector::schema_view(
  self : Inspector,
  schema : @tutuca.Value,
) -> @tutuca.Value {
  self.make_("SchemaViewer", args={
    "value": self.classify_schema(schema),
    "raw": self.inspect_value(schema),
    "rawSchema": schema,
  })
}
