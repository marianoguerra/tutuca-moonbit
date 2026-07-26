// Port of src/components/tutuca/component-inspector.js — inspect a Component
// *descriptor* (the value returned by `@component.component(...)`), not a
// made instance.
//
// A `@component.Component` is not a `@tutuca.Value`, so the inspector takes a
// SNAPSHOT: `component_summary(comp)` returns a plain Value Map (the port of
// JS `introspectComponent`) and the components render that. Typed-state
// deviations:
// - fields come from `Component::specs` (derived from the init state +
//   explicit slot specs).
// - the handler channels are the typed buckets: `compute` lists its names
//   ("Methods"), the render-time buckets list under "Alter", and `update` is
//   one opaque pattern match — shown as a presence flag.
// - generated field mutators never appear (they live in their own table).

///|
fn field_kind_name(k : @component.FieldKind) -> String {
  match k {
    FBool => "bool"
    FText => "text"
    FInt => "int"
    FFloat => "float"
    FList => "list"
    FMap => "map"
    FAny => "any"
    FComp(comp~, ..) => "comp(\{comp})"
    FSet => "set"
    FOMap => "omap"
  }
}

///|
/// The pure snapshot the component inspector renders (JS introspectComponent).
///
/// Two sources. A component with a `tutuca/state` schema is DESCRIBED by its
/// generator — field types with their element types, the names `update`
/// answers, the declared message buckets, the element ids, the named
/// fixtures. One without is RECOVERED from the runtime descriptor, which is
/// all a JS port ever had and all that is knowable without a schema.
pub fn component_summary(comp : @component.Component) -> @tutuca.Value {
  match comp.schema {
    Some(si) => summary_from_schema(comp, si)
    None => summary_from_specs(comp)
  }
}

///|
fn name_list(keys : Array[String]) -> @tutuca.Value {
  let out : Array[@tutuca.Value] = []
  for k in keys {
    out.push(Str(k))
  }
  List(out)
}

///|
fn view_rows(comp : @component.Component) -> @tutuca.Value {
  let views : Array[@tutuca.Value] = []
  for _name, view in comp.views {
    views.push(Map({ "name": Str(view.name), "rawView": Str(view.raw_view) }))
  }
  List(views)
}

///|
/// The declared description. `update` is the interesting row: at runtime it
/// is one opaque pattern match, so reflection can only say THAT it exists —
/// the schema knows every name it answers.
fn summary_from_schema(
  comp : @component.Component,
  si : @component.SchemaInfo,
) -> @tutuca.Value {
  let fields : Array[@tutuca.Value] = []
  for f in si.fields {
    let row : Map[String, @tutuca.Value] = {
      "name": Str(f.name),
      // The WIT spelling the author wrote, not a label reconstructed from
      // the runtime kind: `list<card>`, not `list`.
      "type": Str(f.ty),
      "default": match comp.specs.get(f.name) {
        Some(sp) => sp.default
        None => Null
      },
    }
    match f.elem {
      Some(e) => row["elem"] = Str(e)
      None => ()
    }
    match f.slot {
      Some(c) => row["slot"] = Str(c)
      None => ()
    }
    if !f.members.is_empty() {
      row["members"] = name_list(f.members)
    }
    fields.push(Map(row))
  }
  Map({
    "name": Str(comp.name),
    "id": Num(comp.id.to_double()),
    "fingerprint": Str(si.fingerprint),
    "fields": List(fields),
    "methods": name_list(si.methods),
    "update": name_list(si.inputs),
    "receive": name_list(si.receives),
    "bubble": name_list(si.bubbles),
    "response": name_list(si.responses),
    "swap": name_list(comp.swap_names),
    "alter": name_list(comp.alter_names),
    "ids": name_list(si.ids),
    "fixtures": name_list(si.init_names),
    "views": view_rows(comp),
  })
}

///|
/// The reflected description, for a component with no schema: field kinds
/// inferred from the encoded init value, and `update` as a presence flag
/// because its handled names are unknowable.
fn summary_from_specs(comp : @component.Component) -> @tutuca.Value {
  let fields : Array[@tutuca.Value] = []
  for name, spec in comp.specs {
    fields.push(
      Map({
        "name": Str(name),
        "type": Str(field_kind_name(spec.kind)),
        "default": spec.default,
      }),
    )
  }
  Map({
    "name": Str(comp.name),
    "id": Num(comp.id.to_double()),
    "fields": List(fields),
    "methods": name_list(comp.compute_names),
    "update": name_list(if comp.has_update { ["update"] } else { [] }),
    "swap": name_list(comp.swap_names),
    "alter": name_list(comp.alter_names),
    "views": view_rows(comp),
  })
}

// ---------------------------------------------------------------------------
// Components
// ---------------------------------------------------------------------------

///|
/// A single name entry — used for methods and the handler channels, all of
/// which are just lists of names.
fn comp_name_comp() -> @component.Component {
  comp_name_component()
}

///|
/// A single field row: `name : type = <default value>`. The default value is
/// rendered with the data inspector so it can recurse/expand.
fn comp_field_comp() -> @component.Component {
  comp_field_component()
}

///|
/// A single view: its name plus the raw template source in a code block. The
/// source collapses/expands independently. Plain click toggles it;
/// ctrl/cmd-click bubbles `toggleAllViews` so the top-level inspector can
/// toggle every one at once.
fn comp_view_comp() -> @component.Component {
  comp_view_component(
    compute=m => {
      match m {
        ArrowText =>
          Some((s, _args) => Str(if s.isExpanded { "▼" } else { "▶" }))
      }
    },
    update=(s, msg, ctx) => {
      match msg {
        Input("toggle", args) =>
          if args.get(0) is Some(Bool(true)) {
            ctx.bubble("toggleAllViews", [Bool(!s.isExpanded)])
            None
          } else {
            Some({ ..s, isExpanded: !s.isExpanded })
          }
        _ => None
      }
    },
  )
}

///|
/// A labelled, collapsible, paginated group of entries. Reuses the same
/// composite machinery the JSON inspector uses; neutral chrome — hierarchy
/// via weight, colour reserved for status/severity.

///|
impl Composite for CompSectionState with fn items(self) {
  self.items
}

///|
impl Composite for CompSectionState with fn is_expanded(self) {
  self.isExpanded
}

///|
impl Composite for CompSectionState with fn per_page(self) {
  self.itemsPerPage
}

///|
impl Composite for CompSectionState with fn current_page(self) {
  self.currentPage
}

///|
impl Composite for CompSectionState with fn with_current_page(self, p) {
  { ..self, currentPage: p }
}

///|
fn comp_section_comp() -> @component.Component {
  comp_section_component(
    init={ ..CompSectionState::zero(), itemsPerPage: 10 },
    compute=m => {
      match m {
        ArrowText => Some(composite_arrow_text)
        IsItemsEmpty => Some(composite_is_items_empty)
        ShowPagination => Some(composite_show_pagination)
        CannotPrevPage => Some(composite_cannot_prev_page)
        CannotNextPage => Some(composite_cannot_next_page)
        PageIndicatorText => Some(composite_page_indicator_text)
        TypeText => Some((s, _args) => Str(s.label))
        CountText => Some((s, _args) => Str("(\{s.items.length()})"))
      }
    },
    loop_with=l => {
      match l {
        GetPageRange => Some(composite_page_range)
      }
    },
    update=(s, msg, ctx) => {
      match msg {
        // Plain click toggles this section; ctrl/cmd-click bubbles up so the
        // inspector can toggle every section at once.
        Input("toggle", args) =>
          if args.get(0) is Some(Bool(true)) {
            ctx.bubble("toggleAllSections", [Bool(!s.isExpanded)])
            None
          } else {
            Some({ ..s, isExpanded: !s.isExpanded })
          }
        // The shared prev/next page arms.
        _ => composite_update(s, msg)
      }
    },
  )
}

///|
fn set_all_sections(
  s : ComponentInspectorState,
  state : Bool,
) -> ComponentInspectorState {
  {
    ..s,
    sections: s.sections.map(sec => obj_set(sec, "isExpanded", Bool(state))),
  }
}

///|
fn set_all_views(
  s : ComponentInspectorState,
  state : Bool,
) -> ComponentInspectorState {
  {
    ..s,
    sections: s.sections.map(sec => {
      if obj_get(sec, "label") is Some(Str("Views")) {
        match obj_get(sec, "items") {
          Some(List(views)) =>
            obj_set(
              sec,
              "items",
              List(views.map(v => obj_set(v, "isExpanded", Bool(state)))),
            )
          _ => sec
        }
      } else {
        sec
      }
    }),
  }
}

///|
/// Top-level wrapper: one CompSection per non-empty group of the summary.
fn component_inspector_comp() -> @component.Component {
  component_inspector_component(
    compute=m => {
      match m {
        IdText => Some((s, _args) => Str("#\{s.compId}"))
      }
    },
    update=(s, msg, _ctx) => {
      match ComponentInspectorBubble::from_dispatch(msg) {
        Some(ToggleAllSections(on)) => Some(set_all_sections(s, on))
        Some(ToggleAllViews(on)) => Some(set_all_views(s, on))
        Some(Unknown(_, _)) | None => None
      }
    },
  )
}

// ---------------------------------------------------------------------------
// Builders
// ---------------------------------------------------------------------------

///|
fn Inspector::comp_names_section(
  self : Inspector,
  label : String,
  names : @tutuca.Value,
) -> @tutuca.Value? {
  guard names is List(items) && items.length() > 0 else { return None }
  let rows = items.map(n => self.make_("CompName", args={ "name": n }))
  Some(
    self.make_("CompSection", args={ "label": Str(label), "items": List(rows) }),
  )
}

///|
/// Build a ComponentInspector instance from a `component_summary` snapshot
/// (JS ComponentInspector.Class.fromData). Empty groups are omitted.
fn Inspector::component_view(
  self : Inspector,
  summary : @tutuca.Value,
) -> @tutuca.Value {
  guard summary is Map(d) else { return self.inspect_value(summary) }
  let sections : Array[@tutuca.Value] = []
  // Fields start expanded — the most useful section when inspecting.
  match d.get("fields") {
    Some(List(fields)) if fields.length() > 0 => {
      let rows = fields.map(f => {
        let name = match f {
          Map(fm) => fm.get("name").unwrap_or(Null)
          _ => Null
        }
        let type_name = match f {
          Map(fm) => fm.get("type").unwrap_or(Str(""))
          _ => Str("")
        }
        let dflt = match f {
          Map(fm) => fm.get("default").unwrap_or(Null)
          _ => Null
        }
        self.make_("CompField", args={
          "name": name,
          "typeName": type_name,
          "child": self.inspect_value(dflt),
        })
      })
      sections.push(
        self.make_("CompSection", args={
          "label": Str("Fields"),
          "items": List(rows),
          "isExpanded": Bool(true),
        }),
      )
    }
    _ => ()
  }
  for
    group in [
      ("Methods", "methods"),
      ("Update", "update"),
      ("Receive", "receive"),
      ("Bubble", "bubble"),
      ("Response", "response"),
      ("Swap", "swap"),
      ("Alter", "alter"),
      ("Ids", "ids"),
      ("Fixtures", "fixtures"),
    ] {
    let (label, key) = group
    match self.comp_names_section(label, d.get(key).unwrap_or(Null)) {
      Some(s) => sections.push(s)
      None => ()
    }
  }
  match d.get("views") {
    Some(List(views)) if views.length() > 0 => {
      let rows = views.map(v => {
        match v {
          Map(vm) =>
            self.make_("CompView", args={
              "name": vm.get("name").unwrap_or(Str("")),
              "rawView": vm.get("rawView").unwrap_or(Str("")),
            })
          _ => Null
        }
      })
      sections.push(
        self.make_("CompSection", args={
          "label": Str("Views"),
          "items": List(rows),
        }),
      )
    }
    _ => ()
  }
  self.make_("ComponentInspector", args={
    "compName": d.get("name").unwrap_or(Str("")),
    "compId": d.get("id").unwrap_or(Num(0)),
    "sections": List(sections),
  })
}

///|
/// Snapshot + render in one step (JS ComponentInspector.Class.fromData(comp)).
pub fn Inspector::inspect_component(
  self : Inspector,
  comp : @component.Component,
) -> @tutuca.Value {
  self.component_view(component_summary(comp))
}
