// A high-level JSON-Schema
// viewer. The schema arrives as a `@tutuca.Value` (the parsed JSON document);
// embedded literal values (const / enum members / default / examples) and the
// raw-schema toggle render through the DataInspector.

// ---------------------------------------------------------------------------
// Shared building blocks
// ---------------------------------------------------------------------------

///|
/// The five collapsible schema-construct components share one shape — the
/// composite fields plus a type label, badges and title/description/deprecated
/// — declared once per component in schema_components.html and implemented
/// against the generated states in schema_components.mbt.

///|
fn schema_str(m : Map[String, @tutuca.Value], k : String) -> String {
  match m.get(k) {
    Some(Str(s)) => s
    _ => ""
  }
}

///|
/// Title/description/deprecated metadata, written into a component-args map.
fn schema_meta_into(
  args : Map[String, @tutuca.Value],
  m : Map[String, @tutuca.Value],
) -> Unit {
  args["title"] = Str(schema_str(m, "title"))
  args["description"] = Str(schema_str(m, "description"))
  args["deprecated"] = Bool(m.get("deprecated") is Some(Bool(true)))
}

///|
fn display_type(m : Map[String, @tutuca.Value], fallback : String) -> String {
  match m.get("type") {
    Some(Str(t)) => t
    Some(List(items)) => items.map(i => i.to_display_string()).join(" | ")
    _ => fallback
  }
}

///|
/// A schema whose only keyword is a primitive `type` (e.g. {type:"string"}) —
/// the kind that can be inlined into a parent's label ("array of string").
fn simple_scalar_type(v : @tutuca.Value?) -> String? {
  guard v is Some(Map(m)) else { return None }
  let type_ok = match m.get("type") {
    Some(Str(_)) => true
    Some(List(items)) => items.iter().all(i => i is Str(_))
    _ => false
  }
  if !type_ok {
    return None
  }
  for k, _v in m {
    if k != "type" {
      return None
    }
  }
  Some(display_type(m, "any"))
}

///|
fn combinator_phrasing(kind : String) -> String {
  match kind {
    "allOf" => "all of"
    "anyOf" => "any of"
    "oneOf" => "one of"
    _ => "combination"
  }
}

///|
/// A `key != null` presence probe.
fn present_nn(m : Map[String, @tutuca.Value], k : String) -> @tutuca.Value? {
  match m.get(k) {
    Some(Null) | None => None
    Some(v) => Some(v)
  }
}

///|
/// Constraint keywords as human-readable badge text.
fn collect_badges(m : Map[String, @tutuca.Value]) -> Array[@tutuca.Value] {
  let b : Array[@tutuca.Value] = []
  let disp = (v : @tutuca.Value) => v.to_display_string()
  // string
  match present_nn(m, "format") {
    Some(v) => b.push(Str("format: \{disp(v)}"))
    None => ()
  }
  match present_nn(m, "minLength") {
    Some(v) => b.push(Str("min length: \{disp(v)}"))
    None => ()
  }
  match present_nn(m, "maxLength") {
    Some(v) => b.push(Str("max length: \{disp(v)}"))
    None => ()
  }
  match present_nn(m, "pattern") {
    Some(v) => b.push(Str("pattern: /\{disp(v)}/"))
    None => ()
  }
  // numeric
  match present_nn(m, "minimum") {
    Some(v) => b.push(Str("≥ \{disp(v)}"))
    None => ()
  }
  match present_nn(m, "maximum") {
    Some(v) => b.push(Str("≤ \{disp(v)}"))
    None => ()
  }
  match present_nn(m, "exclusiveMinimum") {
    Some(v) => b.push(Str("> \{disp(v)}"))
    None => ()
  }
  match present_nn(m, "exclusiveMaximum") {
    Some(v) => b.push(Str("< \{disp(v)}"))
    None => ()
  }
  match present_nn(m, "multipleOf") {
    Some(v) => b.push(Str("multiple of \{disp(v)}"))
    None => ()
  }
  // array
  match present_nn(m, "minItems") {
    Some(v) => b.push(Str("min items: \{disp(v)}"))
    None => ()
  }
  match present_nn(m, "maxItems") {
    Some(v) => b.push(Str("max items: \{disp(v)}"))
    None => ()
  }
  if m.get("uniqueItems") is Some(v) && v.is_truthy() {
    b.push(Str("unique items"))
  }
  // object
  match present_nn(m, "minProperties") {
    Some(v) => b.push(Str("min properties: \{disp(v)}"))
    None => ()
  }
  match present_nn(m, "maxProperties") {
    Some(v) => b.push(Str("max properties: \{disp(v)}"))
    None => ()
  }
  if m.get("additionalProperties") is Some(Bool(false)) {
    b.push(Str("no additional properties"))
  }
  // metadata flags
  if m.get("readOnly") is Some(v) && v.is_truthy() {
    b.push(Str("read-only"))
  }
  if m.get("writeOnly") is Some(v) && v.is_truthy() {
    b.push(Str("write-only"))
  }
  b
}

///|
fn Inspector::schema_branch(
  self : Inspector,
  label : String,
  child : @tutuca.Value,
  label_class? : String = "text-accent",
) -> @tutuca.Value {
  self.make_("SchemaBranch", args={
    "label": Str(label),
    "child": child,
    "labelClass": Str(label_class),
  })
}

///|
/// An embedded literal value (const / enum / default / examples) as a
/// labelled branch, rendered with the value inspector.
fn Inspector::value_branch(
  self : Inspector,
  label : String,
  value : @tutuca.Value,
) -> @tutuca.Value {
  self.schema_branch(label, self.inspect_value(value), label_class="text-info")
}

///|
/// Cross-cutting keywords that can coexist with any primary
/// type. `primary` names the family the host component already renders.
fn Inspector::collect_extras(
  self : Inspector,
  m : Map[String, @tutuca.Value],
  primary : String,
) -> Array[@tutuca.Value] {
  let rows : Array[@tutuca.Value] = []
  if primary != "const" && m.get("const") is Some(cv) {
    rows.push(self.value_branch("const", cv))
  }
  if primary != "enum" && m.get("enum") is Some(List(_) as ev) {
    rows.push(self.value_branch("enum", ev))
  }
  match m.get("default") {
    Some(dv) => rows.push(self.value_branch("default", dv))
    None => ()
  }
  match m.get("examples") {
    Some(xv) => rows.push(self.value_branch("examples", xv))
    None => ()
  }
  if primary != "combinator" {
    for k in ["allOf", "anyOf", "oneOf"] {
      if m.get(k) is Some(List(subs)) {
        for s in subs {
          rows.push(
            self.schema_branch(combinator_phrasing(k), self.classify_schema(s)),
          )
        }
      }
    }
  }
  if primary != "not" && m.get("not") is Some(nv) {
    rows.push(
      self.schema_branch(
        "not",
        self.classify_schema(nv),
        label_class="text-error",
      ),
    )
  }
  if primary != "conditional" {
    for k in ["if", "then", "else"] {
      match m.get(k) {
        Some(sv) => rows.push(self.schema_branch(k, self.classify_schema(sv)))
        None => ()
      }
    }
  }
  let defs = match m.get("$defs") {
    Some(Map(d)) => Some(d)
    _ =>
      match m.get("definitions") {
        Some(Map(d)) => Some(d)
        _ => None
      }
  }
  match defs {
    Some(d) =>
      for name, s in d {
        rows.push(
          self.schema_branch(
            "$defs/\{name}",
            self.classify_schema(s),
            label_class="text-secondary",
          ),
        )
      }
    None => ()
  }
  rows
}

// ---------------------------------------------------------------------------
// Leaf rows (reused by composites)
// ---------------------------------------------------------------------------

///|
/// One object property row: key, optional required marker, then the child
/// schema. `contents` so the cells land directly in the parent's grid.
fn schema_property_comp() -> @component.Component {
  schema_property_component()
}

///|
/// A labeled wrapper around a nested schema (object extras, applicators,
/// $defs entries and embedded values).
fn schema_branch_comp() -> @component.Component {
  schema_branch_component(
    init={ ..SchemaBranchState::zero(), labelClass: "text-accent" },
    compute=m => {
      match m {
        LabelCssClass =>
          Some((s, _args) => {
            Str("font-mono text-sm schema-branch-label \{s.labelClass}")
          })
      }
    },
  )
}
