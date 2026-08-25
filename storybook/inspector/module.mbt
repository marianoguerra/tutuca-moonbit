// The inspector registry + ModuleDef.
//
// The components are grouped behind an `Inspector` value: `Inspector::new`
// builds every component once (so instances built by the from-data helpers
// belong to the same descriptors the module registers) and exposes them as
// Inspector methods:
//
//   insp.inspect_value(v)
//   insp.schema_view(s)
//   insp.inspect_component(c)
//   insp.inspect_instance(i)
//   insp.explore_instance(...)
//   insp.record_to_entry(record, ...)
//
// NOT INCLUDED: the in-app test report. `moon test` is the runner, so there is
// no in-app test-report data to render.

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
      state_editor_comp(insp),
      state_editor_row_comp(),
    ] {
    insp.comps[c.name] = c
  }
  insp
}

///|
/// Every inspector component, in registration order.
///
/// Public because a host that renders an inspector view it built itself (the
/// storybook gallery's Instance tab) has to register these: a rendered
/// instance resolves its component through the registry, so an unregistered
/// one draws nothing.
pub fn Inspector::components(self : Inspector) -> Array[@component.Component] {
  self.comps.values().collect()
}

// ---------------------------------------------------------------------------
// per-value inspector builder
// ---------------------------------------------------------------------------

///|
/// The views `build_inspector_views` returns.
/// Absent views are Null; the has_* flags say which tabs a host should show.
pub struct InspectorViews {
  instance_view : @tutuca.Value
  component_view : @tutuca.Value
  has_component : Bool
}

///|
/// Build the inspector views for a single value.
///   value         — the instance/value to inspect (e.g. a drive value)
///   comps         — a component registry used to resolve the value's
///                   descriptor
pub fn Inspector::build_inspector_views(
  self : Inspector,
  value : @tutuca.Value,
  comps? : @component.Components,
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
  { instance_view, component_view, has_component: comp is Some(_) }
}

// ---------------------------------------------------------------------------
// Examples (a representative subset)
// ---------------------------------------------------------------------------

///|
/// Extract a built instance's fields back into an ExampleDef args map (an
/// ExampleDef mounts a component by name + args, not a prebuilt instance).
///
/// The names come from the instance. Each of the eight call sites below used
/// to spell them out — `["value", "raw", "rawSchema", "showRaw"]` and friends
/// — and had to be edited whenever the component grew a field, because an
/// instance could not say what it held.
fn instance_args(v : @tutuca.Value) -> Map[String, @tutuca.Value] {
  v.snapshot()
}

///|
/// A sample descriptor exercising every summary channel. Only introspected,
/// never registered/rendered.
fn rich_sample_comp() -> @component.Component {
  rich_sample_component(
    update=(s, msg, _ctx) => {
      match msg {
        Receive("inc", _) => Next({ ..s, count: s.count + 1 })
        Receive("reset", _) => Next({ ..s, count: 0 })
        Receive("ping", _) | Intent("onChild", _) | Receive("onData", _) =>
          Next(s)
        _ => Unhandled
      }
    },
    loop_with=l => {
      match l {
        Rows =>
          Some((s, _seq, _ctx) => @component.LoopWith::new(start=0, end=s.count))
      }
    },
  )
}

///|
/// A small descriptor exercising a few field types.
fn sample_card_comp() -> @component.Component {
  sample_card_component(
    compute=m => {
      match m {
        Label => Some((s, _args, _stack) => Str(s.title))
      }
    },
    update=(s, msg, _ctx) => {
      match msg {
        Receive("bump", _) => Next({ ..s, count: s.count + 1 })
        _ => Unhandled
      }
    },
  )
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
  let expand_top = (v : @tutuca.Value) => v.with_field("isExpanded", Bool(true))
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
      args: instance_args(deep_expand(insp.schema_view(kitchen_sink_schema()))),
      view: None,
    },
    {
      component: "SchemaViewer",
      title: "Schema: Conditional",
      args: instance_args(insp.schema_view(conditional_schema())),
      view: None,
    },
    {
      component: "SchemaViewer",
      title: "Schema: Boolean False",
      args: instance_args(insp.schema_view(Bool(false))),
      view: None,
    },
    {
      component: "ComponentInspector",
      title: "Component: Rich Sample",
      args: instance_args(insp.inspect_component(rich_sample_comp())),
      view: None,
    },
    {
      component: "ComponentInspector",
      title: "Component: Rich Sample (expanded)",
      args: instance_args(
        deep_expand(insp.inspect_component(rich_sample_comp())),
      ),
      view: None,
    },
    {
      component: "InstanceInspector",
      title: "Instance Inspector (expanded)",
      args: instance_args(insp.inspect_instance(card, sample_card)),
      view: None,
    },
    {
      component: "InstanceExplorer",
      title: "Instance Explorer",
      args: instance_args(insp.explore_instance(card, sample_card)),
      view: None,
    },
    {
      // A form nobody wrote: every row, control and label comes from what the
      // component DECLARES, so this example works for any component at all.
      component: "StateEditor",
      title: "State Editor (schema-driven)",
      args: instance_args(insp.edit_instance(card)),
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
