// Port of src/components/data/json-schema.js — a high-level JSON-Schema
// viewer. The schema arrives as a `@tutuca.Value` (the parsed JSON document);
// embedded literal values (const / enum members / default / examples) and the
// raw-schema toggle render through the DataInspector (JS used JsonViewer).

// ---------------------------------------------------------------------------
// Shared building blocks
// ---------------------------------------------------------------------------

///|
/// JS schemaNodeFields: the composite state plus a type label, constraint
/// badges and title/description/deprecated metadata. Shared by every
/// collapsible schema-construct component.
priv struct SchemaNodeState {
  items : Array[@tutuca.Value]
  isExpanded : Bool
  itemsPerPage : Int
  currentPage : Int
  typeLabel : String
  badges : Array[String]
  title : String
  description : String
  deprecated : Bool
} derive(ToJson, FromJson)

///|
impl Composite for SchemaNodeState with fn items(self) {
  self.items
}

///|
impl Composite for SchemaNodeState with fn is_expanded(self) {
  self.isExpanded
}

///|
impl Composite for SchemaNodeState with fn per_page(self) {
  self.itemsPerPage
}

///|
impl Composite for SchemaNodeState with fn current_page(self) {
  self.currentPage
}

///|
impl Composite for SchemaNodeState with fn with_current_page(self, p) {
  { ..self, currentPage: p }
}

///|
fn schema_node_init() -> SchemaNodeState {
  {
    items: [],
    isExpanded: false,
    itemsPerPage: 10,
    currentPage: 0,
    typeLabel: "",
    badges: [],
    title: "",
    description: "",
    deprecated: false,
  }
}

///|
fn schema_node_compute(
  count_text : (SchemaNodeState) -> String,
) -> Map[String, (SchemaNodeState, Array[@tutuca.Value]) -> @tutuca.Value] {
  composite_compute(s => s.typeLabel, count_text)
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
priv struct SchemaPropertyState {
  key : String
  child : @tutuca.Value
  required : Bool
} derive(ToJson, FromJson)

///|
/// One object property row: key, optional required marker, then the child
/// schema. `contents` so the cells land directly in the parent's grid.
fn schema_property_comp() -> @component.Component {
  @component.component(
    views={
      "main": @anode.View::new(
        "main",
        raw_view=(
          #|<div class="contents">
          #|  <span class="font-mono text-sm flex items-center gap-1 leading-tight">
          #|    <span class="text-base-content/60 schema-key" @text=".key"></span>
          #|    <span @show=".required" class="text-error font-bold" title="required">*</span>
          #|    <span class="text-base-content/30">:</span>
          #|  </span>
          #|  <x render=".child"></x>
          #|</div>
        ),
      ),
    },
    name="SchemaProperty",
    init=SchemaPropertyState::{ key: "", child: Null, required: false },
  )
}

///|
priv struct SchemaBranchState {
  label : String
  child : @tutuca.Value
  labelClass : String
} derive(ToJson, FromJson)

///|
/// A labeled wrapper around a nested schema (object extras, applicators,
/// $defs entries and embedded values).
fn schema_branch_comp() -> @component.Component {
  @component.component(
    views={
      "main": @anode.View::new(
        "main",
        raw_view=(
          #|<div class="contents">
          #|  <span class="flex items-center gap-1 leading-tight">
          #|    <span :class="$labelCssClass" @text=".label"></span>
          #|    <span class="text-base-content/30">:</span>
          #|  </span>
          #|  <x render=".child"></x>
          #|</div>
        ),
      ),
      "_margauiClasses": @anode.View::new(
        "_margauiClasses",
        raw_view=(
          #|<p class="text-accent text-secondary text-info text-error"></p>
        ),
      ),
    },
    name="SchemaBranch",
    init=SchemaBranchState::{
      label: "",
      child: Null,
      labelClass: "text-accent",
    },
    compute={
      "labelCssClass": (s : SchemaBranchState, _args) => {
        Str("font-mono text-sm schema-branch-label \{s.labelClass}")
      },
    },
  )
}
