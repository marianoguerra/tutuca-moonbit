// The inspector registry + ModuleDef (port of src/components/index.js and the
// getExamples entries of the co-located *.dev.js files).
//
// JS exposed the components as module-level singletons with `fromData`
// statics; the port groups them behind an `Inspector` value: `Inspector::new`
// builds every component once (so instances built by the from-data helpers
// belong to the same descriptors the module registers) and the JS statics
// become Inspector methods:
//
//   DataInspector.Class.fromData(v)      -> insp.inspect_value(v)
//   SchemaViewer.Class.fromData(s)       -> insp.schema_view(s)
//   ComponentInspector.Class.fromData(c) -> insp.inspect_component(c)
//   InstanceInspector.Class.fromData(i)  -> insp.inspect_instance(i)
//   InstanceExplorer.Class.fromData(...) -> insp.explore_instance(...)
//   LintReport.Class.fromData(...)       -> insp.lint_report(findings)
//   recordToEntry(record, ...)           -> insp.record_to_entry(record, ...)
//
// NOT PORTED: test-inspector.js (TestReport & co). Its data source was the
// JS in-app test runner (`tutuca test --json`); `moon test` is the runner in
// the port, so there is no in-app test-report data to render.

///|
/// name -> Component, shared by every from-data builder (the same lookup-table
/// pattern examples/json.mbt uses for mutual recursion).
pub struct Inspector {
  comps : Map[String, @component.Component]
}

///|
fn Inspector::make_(
  self : Inspector,
  name : String,
  args? : Map[String, @tutuca.Value] = Map([]),
) -> @tutuca.Value {
  match self.comps.get(name) {
    Some(c) => c.make(args)
    None => Null
  }
}

///|
/// Build every inspector component once. Instances made through the returned
/// Inspector reference these exact descriptors, so snapshots embedded in
/// example args render through the same registered components.
pub fn Inspector::new() -> Inspector {
  let insp = Inspector::{ comps: Map([]) }
  for
    c in [
      // data / json layer
      data_inspector_comp(),
      json_property_comp(),
      json_null_comp(),
      json_boolean_comp(),
      json_number_comp(),
      json_string_comp(),
      json_array_comp(),
      json_object_comp(),
      value_fn_comp(),
      value_obj_comp(),
      // json-schema layer
      schema_viewer_comp(),
      schema_scalar_comp(),
      schema_object_comp(),
      schema_array_comp(),
      schema_enum_comp(),
      schema_const_comp(),
      schema_combinator_comp(),
      schema_conditional_comp(),
      schema_not_comp(),
      schema_property_comp(),
      schema_branch_comp(),
      schema_boolean_comp(),
      schema_ref_comp(),
      // tutuca layer
      activity_log_comp(),
      activity_entry_comp(),
      component_inspector_comp(),
      comp_section_comp(),
      comp_field_comp(),
      comp_name_comp(),
      comp_view_comp(),
      instance_explorer_comp(),
      instance_inspector_comp(),
      instance_fields_comp(),
      lint_report_comp(),
      lint_component_comp(),
      lint_finding_comp(),
    ] {
    insp.comps[c.name] = c
  }
  insp
}

///|
/// Every inspector component, in registration order (JS getComponents()).
pub fn Inspector::components(self : Inspector) -> Array[@component.Component] {
  self.comps.values().collect()
}

// ---------------------------------------------------------------------------
// build-views.js — per-value inspector builder
// ---------------------------------------------------------------------------

///|
/// The views `build_inspector_views` returns (JS buildInspectorViews result).
/// Absent views are Null; the has_* flags say which tabs a host should show.
pub struct InspectorViews {
  instance_view : @tutuca.Value
  component_view : @tutuca.Value
  lint_view : @tutuca.Value
  has_component : Bool
  has_lint : Bool
}

///|
/// Build the inspector views for a single value (port of buildInspectorViews,
/// adapted to the snapshot approach — and without the JS async test runner,
/// see the header comment).
///   value         — the instance/value to inspect (e.g. a drive value)
///   comps         — a component registry used to resolve the value's
///                   descriptor (JS `scope.getCompFor(value)`)
///   lint_findings — prebuilt `finding_value` Maps; omit to skip the Lint view
pub fn Inspector::build_inspector_views(
  self : Inspector,
  value : @tutuca.Value,
  comps? : @component.Components,
  lint_findings? : Array[@tutuca.Value],
) -> InspectorViews {
  let comp = match comps {
    Some(cs) => cs.get_comp_for(value)
    None => None
  }
  let instance_view = self.inspect_value_as_instance(value, comp)
  let component_view = match comp {
    Some(c) => self.inspect_component(c)
    None => Null
  }
  let lint_view = match lint_findings {
    Some(fs) => self.lint_report(fs)
    None => Null
  }
  {
    instance_view,
    component_view,
    lint_view,
    has_component: comp is Some(_),
    has_lint: lint_findings is Some(_),
  }
}

// ---------------------------------------------------------------------------
// Examples (the *.dev.js getExamples entries, a representative subset)
// ---------------------------------------------------------------------------

///|
/// Extract a built instance's fields back into an ExampleDef args map (an
/// ExampleDef mounts a component by name + args, not a prebuilt instance).
fn instance_args(
  v : @tutuca.Value,
  names : Array[String],
) -> Map[String, @tutuca.Value] {
  let args : Map[String, @tutuca.Value] = Map([])
  for name in names {
    match obj_get(v, name) {
      Some(field_val) => args[name] = field_val
      None => ()
    }
  }
  args
}

///|
priv struct SampleState {
  title : String
  count : Int
  tags : Array[@tutuca.Value]
  open : Bool
} derive(ToJson, FromJson)

///|
/// A sample descriptor exercising every summary channel (RichSample in
/// component-inspector.dev.js). Only introspected, never registered/rendered.
fn rich_sample_comp() -> @component.Component {
  @component.component(
    name="RichSample",
    init=SampleState::{ title: "", count: 0, tags: [], open: false },
    compute={
      "label": (s : SampleState, _args) => Str(s.title),
      "double": (s : SampleState, _args) => Num((s.count * 2).to_double()),
    },
    mutate={
      "inc": (s : SampleState, _args) => { ..s, count: s.count + 1 },
      "reset": (s : SampleState, _args) => { ..s, count: 0 },
    },
    update=(s : SampleState, msg, _ctx) => {
      match msg {
        Receive("ping", _) | Bubble("onChild", _) | Response("onData", _) =>
          Some(s)
        _ => None
      }
    },
    loop_with={
      "rows": (s : SampleState, _seq, _ctx) => {
        @component.LoopWith::new(start=0, end=s.count)
      },
    },
    view=(
      #|<div @text=".title"></div>
    ),
    views={
      "compact": (
        #|<span @text=".title"></span>
      ),
    },
  )
}

///|
/// A small descriptor exercising a few field types (SampleCard in
/// instance-inspector.dev.js).
fn sample_card_comp() -> @component.Component {
  @component.component(
    name="SampleCard",
    init=SampleState::{ title: "", count: 0, tags: [], open: false },
    compute={ "label": (s : SampleState, _args) => Str(s.title) },
    mutate={ "bump": (s : SampleState, _args) => { ..s, count: s.count + 1 } },
    view=(
      #|<div class="card" @text=".title"></div>
    ),
  )
}

///|
fn sample_lint_findings() -> Array[@tutuca.Value] {
  [
    finding_value(
      "METHOD_VAL_NOT_IMPLEMENTED", "error", "Broken/view", "Method '$missingMethod' is not implemented in @on.click",
    ),
    finding_value(
      "FIELD_VAL_NOT_DEFINED", "error", "Broken/view", "Field '.nope' is not defined (in @text, on <span>)",
    ),
    finding_value(
      "REDUNDANT_TEMPLATE_STRING",
      "warn",
      "Broken/view",
      "Redundant string template — '{.title}' should be just '.title'",
      suggestion="$'{.title}' → .title",
    ),
    finding_value(
      "PLACEHOLDERLESS_TEMPLATE_STRING",
      "hint",
      "Broken/view",
      "String template has no dynamic parts — use the literal 'btn' instead",
      suggestion="$'btn' → 'btn'",
    ),
    finding_value(
      "CONSTANT_CONDITION", "warn", "Other/view", "Constant condition 'open' — reference a field ('.name') or method ('$name')",
    ),
  ]
}

///|
fn api_response_shape() -> @tutuca.Value {
  Map({
    "id": Str("user_42"),
    "active": Bool(true),
    "score": Num(99.5),
    "tags": List([Str("admin"), Str("early-access"), Null]),
    "profile": Map({
      "name": Str("Alice"),
      "email": Str("alice@example.com"),
      "meta": Map({ "joined": Str("2026-01-15"), "verified": Bool(true) }),
    }),
  })
}

///|
fn kitchen_sink_schema() -> @tutuca.Value {
  Map({
    "title": Str("User"),
    "description": Str("A registered user account."),
    "type": Str("object"),
    "additionalProperties": Bool(false),
    "minProperties": Num(2),
    "properties": Map({
      "id": Map({
        "type": Str("integer"),
        "minimum": Num(1),
        "readOnly": Bool(true),
      }),
      "email": Map({
        "type": Str("string"),
        "format": Str("email"),
        "maxLength": Num(254),
      }),
      "role": Map({ "enum": List([Str("admin"), Str("editor"), Str("viewer")]) }),
      "status": Map({ "const": Str("active") }),
      "age": Map({
        "type": Str("integer"),
        "minimum": Num(0),
        "maximum": Num(150),
        "default": Num(18),
      }),
      "tags": Map({
        "type": Str("array"),
        "items": Map({ "type": Str("string") }),
        "uniqueItems": Bool(true),
        "maxItems": Num(10),
      }),
      "contact": Map({
        "anyOf": List([
          Map({ "type": Str("string"), "format": Str("email") }),
          Map({ "type": Str("string"), "format": Str("uri") }),
        ]),
      }),
    }),
    "required": List([Str("id"), Str("email")]),
  })
}

///|
fn conditional_schema() -> @tutuca.Value {
  Map({
    "if": Map({ "properties": Map({ "kind": Map({ "const": Str("card") }) }) }),
    "then": Map({
      "type": Str("object"),
      "properties": Map({ "cardNumber": Map({ "type": Str("string") }) }),
      "required": List([Str("cardNumber")]),
    }),
    "else": Map({
      "type": Str("object"),
      "properties": Map({ "account": Map({ "type": Str("string") }) }),
      "required": List([Str("account")]),
    }),
  })
}

///|
fn long_list(n : Int) -> @tutuca.Value {
  let items : Array[@tutuca.Value] = []
  for i in 1..<=n {
    items.push(Num(i.to_double()))
  }
  List(items)
}

///|
/// The whole library as one mountable ModuleDef (fresh registry).
pub fn inspector_module() -> @component.ModuleDef {
  Inspector::new().module_()
}

///|
/// The ModuleDef over THIS registry — use it when instances built through
/// this Inspector (e.g. `record_to_entry` rows sent to a mounted ActivityLog)
/// must resolve against the same registered components.
pub fn Inspector::module_(self : Inspector) -> @component.ModuleDef {
  let insp = self
  let expand_top = (v : @tutuca.Value) => obj_set(v, "isExpanded", Bool(true))
  let sample_card = sample_card_comp()
  let card = sample_card.make({
    "title": Str("Hello"),
    "count": Num(3),
    "tags": List([Str("a"), Str("b")]),
    "open": Bool(true),
  })
  let deep_zoo : @tutuca.Value = Map({
    "json": Map({ "ok": Bool(true), "n": Num(1) }),
    "items": List([Num(1), Num(2), Map({ "x": Num(99) })]),
    "fn": Fn(_args => Null),
    "nothing": Null,
  })
  @component.ModuleDef::new(name="inspector", components=insp.components(), examples=[
    {
      component: "DataInspector",
      title: "Null",
      args: { "value": insp.classify(Null) },
      view: None,
    },
    {
      component: "DataInspector",
      title: "Small Array (expanded)",
      args: {
        "value": expand_top(
          insp.classify(List([Num(1), Str("two"), Bool(true), Null])),
        ),
      },
      view: None,
    },
    {
      component: "DataInspector",
      title: "Paginated Array (25 items, expanded)",
      args: { "value": expand_top(insp.classify(long_list(25))) },
      view: None,
    },
    {
      component: "DataInspector",
      title: "API Response Shape (expanded)",
      args: { "value": expand_top(insp.classify(api_response_shape())) },
      view: None,
    },
    {
      component: "DataInspector",
      title: "Deeply Mixed (expanded)",
      args: { "value": deep_expand(insp.classify(deep_zoo)) },
      view: None,
    },
    {
      component: "SchemaViewer",
      title: "Schema: Kitchen Sink (expanded)",
      args: instance_args(
        deep_expand(insp.schema_view(kitchen_sink_schema())),
        ["value", "raw", "rawSchema", "showRaw"],
      ),
      view: None,
    },
    {
      component: "SchemaViewer",
      title: "Schema: Conditional",
      args: instance_args(insp.schema_view(conditional_schema()), [
        "value", "raw", "rawSchema", "showRaw",
      ]),
      view: None,
    },
    {
      component: "SchemaViewer",
      title: "Schema: Boolean False",
      args: instance_args(insp.schema_view(Bool(false)), [
        "value", "raw", "rawSchema", "showRaw",
      ]),
      view: None,
    },
    {
      component: "ComponentInspector",
      title: "Component: Rich Sample",
      args: instance_args(insp.inspect_component(rich_sample_comp()), [
        "compName", "compId", "sections",
      ]),
      view: None,
    },
    {
      component: "ComponentInspector",
      title: "Component: Rich Sample (expanded)",
      args: instance_args(
        deep_expand(insp.inspect_component(rich_sample_comp())),
        ["compName", "compId", "sections"],
      ),
      view: None,
    },
    {
      component: "InstanceInspector",
      title: "Instance Inspector (expanded)",
      args: instance_args(insp.inspect_instance(card, sample_card), ["value"]),
      view: None,
    },
    {
      component: "InstanceExplorer",
      title: "Instance Explorer",
      args: instance_args(
        insp.explore_instance(
          card,
          sample_card,
          lint_findings=sample_lint_findings(),
        ),
        [
          "activeTab", "instanceView", "componentView", "lintView", "hasComponent",
          "hasLint",
        ],
      ),
      view: None,
    },
    {
      component: "LintReport",
      title: "Lint Report With Findings",
      args: instance_args(
        insp.lint_report(sample_lint_findings(), title="broken module"),
        ["title", "path", "errors", "warnings", "hints", "clean", "components"],
      ),
      view: None,
    },
    {
      component: "LintReport",
      title: "Lint Report Clean",
      args: instance_args(insp.lint_report([], title="good module"), [
        "title", "path", "errors", "warnings", "hints", "clean", "components",
      ]),
      view: None,
    },
    {
      component: "ActivityLog",
      title: "Activity Log",
      args: Map([]),
      view: None,
    },
    {
      component: "ActivityEntry",
      title: "Activity Entry",
      args: {
        "kind": Str("input"),
        "name": Str("click"),
        "matched": Str("exact"),
        "pathLabel": Str("value.rows[1]"),
        "time": Str("#1"),
        "before": insp.inspect_value(Num(1)),
        "after": insp.inspect_value(Num(2)),
        "hasAfter": Bool(true),
      },
      view: None,
    },
  ])
}
