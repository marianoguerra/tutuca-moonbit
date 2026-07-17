// Port of src/components/data/json-schema.js — a high-level JSON-Schema
// viewer. The schema arrives as a `@tutuca.Value` (the parsed JSON document);
// embedded literal values (const / enum members / default / examples) and the
// raw-schema toggle render through the DataInspector (JS used JsonViewer).

// ---------------------------------------------------------------------------
// Shared building blocks
// ---------------------------------------------------------------------------

///|
/// JS schemaNodeFields: the composite state plus a type label, constraint
/// badges and title/description/deprecated metadata.
fn schema_node_fields() -> Map[String, @component.FieldSpec] {
  let f = composite_fields()
  f["typeLabel"] = @component.FieldSpec::of_default(Str(""))
  f["badges"] = @component.FieldSpec::of_default(List([]))
  f["title"] = @component.FieldSpec::of_default(Str(""))
  f["description"] = @component.FieldSpec::of_default(Str(""))
  f["deprecated"] = @component.FieldSpec::of_default(Bool(false))
  f
}

///|
fn schema_node_methods(
  count_text : (@component.Instance) -> String,
) -> Map[String, @component.MethodFn] {
  composite_methods(inst => str_field(inst, "typeLabel"), count_text)
}

///|
/// Body of a collapsible node. `grid` (key/value rows) aligns every row's
/// value into one column via a 2-column CSS grid whose rows are
/// `display: contents`; `list` stacks single-element items one per line.
const GRID_BODY : String =
  #|<div @show=".isExpanded" class="ml-1 grid gap-x-2 gap-y-0.5 items-baseline border-l border-base-content/10 pl-2 mt-0.5" style="grid-template-columns: auto 1fr">
  #|  <x render-each=".items" @loop-with="getPageRange"></x>
  #|</div>

///|
const LIST_BODY : String =
  #|<div @show=".isExpanded" class="ml-1 flex flex-col gap-0.5 border-l border-base-content/10 pl-2 mt-0.5">
  #|  <x render-each=".items" @loop-with="getPageRange"></x>
  #|</div>

///|
/// JS makeSchemaView(accent, body): the shared collapsible chrome — chevron +
/// type label + count + badges + title/description + a body (grid or list).
/// `accent` is interpolated as a literal so the margaui scanner sees it.
fn make_schema_view(accent : String, body? : String = GRID_BODY) -> String {
  let tpl =
    #|<span class="font-mono text-sm leading-tight inline-block">
    #|  <span class="inline-flex items-center gap-2 flex-wrap">
    #|    <button
    #|      type="button"
    #|      class="cursor-pointer text-base-content/70 hover:text-base-content inline-flex items-center gap-1"
    #|      :disabled="$isItemsEmpty"
    #|      @on.click="$toggleIsExpanded">
    #|      <span @hide="$isItemsEmpty" @text="$arrowText"></span>
    #|      <span class="__ACCENT__ font-semibold" @text="$typeText"></span>
    #|      <span class="text-base-content/50" @text="$countText"></span>
    #|    </button>
    #|    <span @each=".badges" class="badge badge-xs badge-ghost font-mono font-normal"><x text="@value"></x></span>
    #|    <span @show=".deprecated" class="badge badge-xs badge-warning">deprecated</span>
    #|    <div @show="$showPagination" class="join">
    #|      <button type="button" class="join-item btn btn-xs pg-prev" :disabled="$cannotPrevPage" @on.click="$prevPage">«</button>
    #|      <span class="join-item badge font-mono text-xs pg-label" @text="$pageIndicatorText"></span>
    #|      <button type="button" class="join-item btn btn-xs pg-next" :disabled="$cannotNextPage" @on.click="$nextPage">»</button>
    #|    </div>
    #|  </span>
    #|  <span @show="truthy? .title" class="block text-base-content/80 italic" @text=".title"></span>
    #|  <span @show="truthy? .description" class="block text-base-content/50" @text=".description"></span>
    #|  __BODY__
    #|</span>

  tpl.replace(old="__ACCENT__", new=accent).replace(old="__BODY__", new=body)
}

///|
fn schema_str(m : Map[String, @tutuca.Value], k : String) -> String {
  match m.get(k) {
    Some(Str(s)) => s
    _ => ""
  }
}

///|
/// JS metaOf: title/description/deprecated, written into a component-args map.
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
/// A `key != null` presence probe (JS `schema.x != null`).
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
/// JS collectExtras: cross-cutting keywords that can coexist with any primary
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
  @component.component(
    name="SchemaProperty",
    fields={
      "key": @component.FieldSpec::of_default(Str("")),
      "child": @component.FieldSpec::of_default(Null),
      "required": @component.FieldSpec::of_default(Bool(false)),
    },
    view=(
      #|<div class="contents">
      #|  <span class="font-mono text-sm flex items-center gap-1 leading-tight">
      #|    <span class="text-base-content/60 schema-key" @text=".key"></span>
      #|    <span @show=".required" class="text-error font-bold" title="required">*</span>
      #|    <span class="text-base-content/30">:</span>
      #|  </span>
      #|  <x render=".child"></x>
      #|</div>
    ),
  )
}

///|
/// A labeled wrapper around a nested schema (object extras, applicators,
/// $defs entries and embedded values).
fn schema_branch_comp() -> @component.Component {
  @component.component(
    name="SchemaBranch",
    fields={
      "label": @component.FieldSpec::of_default(Str("")),
      "child": @component.FieldSpec::of_default(Null),
      "labelClass": @component.FieldSpec::of_default(Str("text-accent")),
    },
    methods={
      "labelCssClass": (inst, _args) => {
        let label_class = str_field(inst, "labelClass")
        Str("font-mono text-sm schema-branch-label \{label_class}")
      },
    },
    view=(
      #|<div class="contents">
      #|  <span class="flex items-center gap-1 leading-tight">
      #|    <span :class="$labelCssClass" @text=".label"></span>
      #|    <span class="text-base-content/30">:</span>
      #|  </span>
      #|  <x render=".child"></x>
      #|</div>
    ),
    views={
      // Decoy: labelClass colours are chosen at build time, so they never
      // appear as literals for the margaui scanner.
      "_margauiClasses": (
        #|<p class="text-accent text-secondary text-info text-error"></p>
      ),
    },
  )
}

// ---------------------------------------------------------------------------
// Per-construct schema components
// ---------------------------------------------------------------------------

///|
/// Primitive type(s): string / number / integer / boolean / null / multi-type.
fn schema_scalar_comp() -> @component.Component {
  @component.component(
    name="SchemaScalar",
    fields=schema_node_fields(),
    methods=schema_node_methods(_inst => ""),
    alter=composite_alter(),
    view=make_schema_view("text-success schema-scalar"),
  )
}

///|
fn Inspector::schema_scalar_from(
  self : Inspector,
  m : Map[String, @tutuca.Value],
) -> @tutuca.Value {
  let args : Map[String, @tutuca.Value] = {
    "typeLabel": Str(display_type(m, "any")),
    "badges": List(collect_badges(m)),
    "items": List(self.collect_extras(m, "scalar")),
  }
  schema_meta_into(args, m)
  self.make_("SchemaScalar", args~)
}

///|
/// Object schema: property rows (with required markers) plus object-specific
/// branches (additionalProperties / patternProperties / propertyNames).
fn schema_object_comp() -> @component.Component {
  @component.component(
    name="SchemaObject",
    fields=schema_node_fields(),
    methods=schema_node_methods(inst => {
      let n = items_of(inst).length()
      if n > 0 {
        "{\{n}}"
      } else {
        ""
      }
    }),
    alter=composite_alter(),
    view=make_schema_view("text-primary schema-object"),
  )
}

///|
fn Inspector::schema_object_from(
  self : Inspector,
  m : Map[String, @tutuca.Value],
) -> @tutuca.Value {
  let required : Array[@tutuca.Value] = match m.get("required") {
    Some(List(r)) => r
    _ => []
  }
  let items : Array[@tutuca.Value] = []
  match m.get("properties") {
    Some(Map(props)) =>
      for k, v in props {
        items.push(
          self.make_("SchemaProperty", args={
            "key": Str(k),
            "required": Bool(required.contains(Str(k))),
            "child": self.classify_schema(v),
          }),
        )
      }
    _ => ()
  }
  match m.get("patternProperties") {
    Some(Map(pats)) =>
      for pat, v in pats {
        items.push(
          self.schema_branch(
            "/\{pat}/",
            self.classify_schema(v),
            label_class="text-secondary",
          ),
        )
      }
    _ => ()
  }
  match m.get("additionalProperties") {
    Some(Map(_) as ap) =>
      items.push(
        self.schema_branch(
          "additional properties",
          self.classify_schema(ap),
          label_class="text-secondary",
        ),
      )
    _ => ()
  }
  match m.get("propertyNames") {
    Some(pn) =>
      items.push(
        self.schema_branch(
          "property names",
          self.classify_schema(pn),
          label_class="text-secondary",
        ),
      )
    None => ()
  }
  items.append(self.collect_extras(m, "object"))
  let args : Map[String, @tutuca.Value] = {
    "typeLabel": Str(display_type(m, "object")),
    "badges": List(collect_badges(m)),
    "items": List(items),
  }
  schema_meta_into(args, m)
  self.make_("SchemaObject", args~)
}

///|
/// Array schema: a single `items` schema, or a positional `prefixItems`
/// tuple, plus `contains` and array constraints (as badges).
fn schema_array_comp() -> @component.Component {
  @component.component(
    name="SchemaArray",
    fields=schema_node_fields(),
    methods=schema_node_methods(inst => {
      let n = items_of(inst).length()
      if n > 0 {
        "[\{n}]"
      } else {
        ""
      }
    }),
    alter=composite_alter(),
    view=make_schema_view("text-primary schema-array"),
  )
}

///|
fn Inspector::schema_array_from(
  self : Inspector,
  m : Map[String, @tutuca.Value],
) -> @tutuca.Value {
  let items : Array[@tutuca.Value] = []
  let prefix_items : Array[@tutuca.Value]? = match m.get("prefixItems") {
    Some(List(p)) => Some(p)
    _ => None
  }
  let is_tuple = prefix_items is Some(_)
  // Inline a bare primitive item type into the label ("array of string")
  // instead of an expandable `items` row.
  let inline_type : String? = if !is_tuple && !(m.get("items") is Some(List(_))) {
    simple_scalar_type(m.get("items"))
  } else {
    None
  }
  match prefix_items {
    Some(ps) =>
      for i, s in ps {
        items.push(self.schema_branch("item \{i}", self.classify_schema(s)))
      }
    None => ()
  }
  match m.get("items") {
    // draft-07 tuple form
    Some(List(ss)) =>
      for i, s in ss {
        items.push(self.schema_branch("item \{i}", self.classify_schema(s)))
      }
    Some(s) =>
      if inline_type is None {
        items.push(self.schema_branch("items", self.classify_schema(s)))
      }
    None => ()
  }
  match m.get("contains") {
    Some(c) =>
      items.push(self.schema_branch("contains", self.classify_schema(c)))
    None => ()
  }
  items.append(self.collect_extras(m, "array"))
  let type_label = if is_tuple {
    "tuple"
  } else {
    match inline_type {
      Some(t) => "array of \{t}"
      None => display_type(m, "array")
    }
  }
  let args : Map[String, @tutuca.Value] = {
    "typeLabel": Str(type_label),
    "badges": List(collect_badges(m)),
    "items": List(items),
  }
  schema_meta_into(args, m)
  self.make_("SchemaArray", args~)
}

///|
/// Enumerated allowed values — each rendered with the value inspector.
fn schema_enum_comp() -> @component.Component {
  @component.component(
    name="SchemaEnum",
    fields=schema_node_fields(),
    methods=schema_node_methods(inst => {
      let n = items_of(inst).length()
      if n > 0 {
        "(\{n})"
      } else {
        ""
      }
    }),
    alter=composite_alter(),
    // list layout: each enum member is a single value one per line.
    view=make_schema_view("text-info schema-enum", body=LIST_BODY),
  )
}

///|
fn Inspector::schema_enum_from(
  self : Inspector,
  m : Map[String, @tutuca.Value],
) -> @tutuca.Value {
  let members : Array[@tutuca.Value] = match m.get("enum") {
    Some(List(e)) => e
    _ => []
  }
  let items = members.map(v => self.inspect_value(v))
  items.append(self.collect_extras(m, "enum"))
  let args : Map[String, @tutuca.Value] = {
    "typeLabel": Str("enum"),
    "badges": List(collect_badges(m)),
    "items": List(items),
  }
  schema_meta_into(args, m)
  self.make_("SchemaEnum", args~)
}

///|
/// A single constant value — terminal, rendered inline.
fn schema_const_comp() -> @component.Component {
  @component.component(
    name="SchemaConst",
    fields={ "value": @component.FieldSpec::of_default(Null) },
    view=(
      #|<span class="font-mono text-sm leading-tight inline-flex items-center gap-2 schema-const">
      #|  <span class="text-info font-semibold">const</span>
      #|  <span class="text-base-content/30">=</span>
      #|  <x render=".value"></x>
      #|</span>
    ),
  )
}

///|
/// Combinator: allOf / anyOf / oneOf, subschemas listed without keys.
fn schema_combinator_comp() -> @component.Component {
  @component.component(
    name="SchemaCombinator",
    fields=schema_node_fields(),
    methods=schema_node_methods(inst => {
      let n = items_of(inst).length()
      if n > 0 {
        "(\{n})"
      } else {
        ""
      }
    }),
    alter=composite_alter(),
    // list layout: members are full schema nodes one per line, no keys.
    view=make_schema_view("text-accent schema-combinator", body=LIST_BODY),
  )
}

///|
fn Inspector::schema_combinator_from(
  self : Inspector,
  m : Map[String, @tutuca.Value],
) -> @tutuca.Value {
  let items : Array[@tutuca.Value] = []
  let mut kind = ""
  for k in ["allOf", "anyOf", "oneOf"] {
    if m.get(k) is Some(List(subs)) {
      if kind == "" {
        kind = k
      }
      for s in subs {
        items.push(self.classify_schema(s))
      }
    }
  }
  items.append(self.collect_extras(m, "combinator"))
  let args : Map[String, @tutuca.Value] = {
    "typeLabel": Str(combinator_phrasing(kind)),
    "badges": List(collect_badges(m)),
    "items": List(items),
  }
  schema_meta_into(args, m)
  self.make_("SchemaCombinator", args~)
}

///|
/// Conditional applicator: if / then / else as three labeled regions.
fn schema_conditional_comp() -> @component.Component {
  @component.component(
    name="SchemaConditional",
    fields={
      "ifNode": @component.FieldSpec::of_default(Null),
      "thenNode": @component.FieldSpec::of_default(Null),
      "elseNode": @component.FieldSpec::of_default(Null),
      "title": @component.FieldSpec::of_default(Str("")),
      "description": @component.FieldSpec::of_default(Str("")),
      "deprecated": @component.FieldSpec::of_default(Bool(false)),
    },
    view=(
      #|<span class="font-mono text-sm leading-tight inline-block schema-conditional">
      #|  <span class="inline-flex items-center gap-2 flex-wrap">
      #|    <span class="text-accent font-semibold">conditional</span>
      #|    <span @show=".deprecated" class="badge badge-xs badge-warning">deprecated</span>
      #|  </span>
      #|  <span @show="truthy? .title" class="block text-base-content/80 italic" @text=".title"></span>
      #|  <span @show="truthy? .description" class="block text-base-content/50" @text=".description"></span>
      #|  <div class="ml-1 grid gap-x-2 gap-y-0.5 items-baseline border-l border-base-content/10 pl-2 mt-0.5" style="grid-template-columns: auto 1fr">
      #|    <div @show="truthy? .ifNode" class="contents">
      #|      <span class="font-mono text-sm flex items-center gap-1 leading-tight">
      #|        <span class="text-info">if</span>
      #|        <span class="text-base-content/30">:</span>
      #|      </span>
      #|      <x render=".ifNode"></x>
      #|    </div>
      #|    <div @show="truthy? .thenNode" class="contents">
      #|      <span class="font-mono text-sm flex items-center gap-1 leading-tight">
      #|        <span class="text-success">then</span>
      #|        <span class="text-base-content/30">:</span>
      #|      </span>
      #|      <x render=".thenNode"></x>
      #|    </div>
      #|    <div @show="truthy? .elseNode" class="contents">
      #|      <span class="font-mono text-sm flex items-center gap-1 leading-tight">
      #|        <span class="text-warning">else</span>
      #|        <span class="text-base-content/30">:</span>
      #|      </span>
      #|      <x render=".elseNode"></x>
      #|    </div>
      #|  </div>
      #|</span>
    ),
  )
}

///|
fn Inspector::schema_conditional_from(
  self : Inspector,
  m : Map[String, @tutuca.Value],
) -> @tutuca.Value {
  let node = (k : String) => {
    match m.get(k) {
      Some(s) => self.classify_schema(s)
      None => Null
    }
  }
  let args : Map[String, @tutuca.Value] = {
    "ifNode": node("if"),
    "thenNode": node("then"),
    "elseNode": node("else"),
  }
  schema_meta_into(args, m)
  self.make_("SchemaConditional", args~)
}

///|
/// Negation: the value must NOT match the wrapped schema.
fn schema_not_comp() -> @component.Component {
  @component.component(
    name="SchemaNot",
    fields={ "child": @component.FieldSpec::of_default(Null) },
    view=(
      #|<span class="font-mono text-sm leading-tight inline-flex items-center gap-2 schema-not">
      #|  <span class="text-error font-semibold">not</span>
      #|  <span class="text-base-content/30">:</span>
      #|  <x render=".child"></x>
      #|</span>
    ),
  )
}

///|
/// Boolean schemas: `true` accepts any value, `false` accepts none.
fn schema_boolean_comp() -> @component.Component {
  @component.component(
    name="SchemaBoolean",
    fields={ "value": @component.FieldSpec::of_default(Bool(true)) },
    methods={
      "text": (inst, _args) => {
        Str(
          if bool_field(inst, "value") {
            "any value (true)"
          } else {
            "no value allowed (false)"
          },
        )
      },
      "cssClass": (inst, _args) => {
        let color = if bool_field(inst, "value") {
          "text-success"
        } else {
          "text-error"
        }
        Str("font-mono text-sm leading-tight italic schema-boolean \{color}")
      },
    },
    view=(
      #|<span :class="$cssClass" @text="$text"></span>
    ),
    views={
      // Decoy: cssClass() builds these at runtime.
      "_margauiClasses": (
        #|<p class="text-success text-error"></p>
      ),
    },
  )
}

///|
/// A `$ref`. Rendered as a label only — never resolved/followed, so recursive
/// schemas (`{ "$ref": "#" }`) cannot loop.
fn schema_ref_comp() -> @component.Component {
  @component.component(
    name="SchemaRef",
    fields={ "target": @component.FieldSpec::of_default(Str("")) },
    view=(
      #|<span class="font-mono text-sm leading-tight text-secondary schema-ref">→ <span @text=".target"></span></span>
    ),
  )
}

// ---------------------------------------------------------------------------
// Top-level viewer + dispatch
// ---------------------------------------------------------------------------

///|
/// Holds the classified high-level tree in `value` and a DataInspector of the
/// original schema in `raw`; `showRaw` toggles between them. `rawSchema`
/// keeps the plain schema for inspection.
fn schema_viewer_comp() -> @component.Component {
  @component.component(
    name="SchemaViewer",
    fields={
      "value": @component.FieldSpec::of_default(Null),
      "raw": @component.FieldSpec::of_default(Null),
      "rawSchema": @component.FieldSpec::of_default(Null),
      "showRaw": @component.FieldSpec::of_default(Bool(false)),
    },
    methods={
      "toggleIsExpanded": wrapper_toggle,
      "toggleLabel": (inst, _args) => {
        Str(
          if bool_field(inst, "showRaw") {
            "high-level view"
          } else {
            "raw schema"
          },
        )
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
