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
// - the handler channels are the typed buckets: `mutate`/`compute` list
//   their names ("Methods"), the render-time buckets list under "Alter", and
//   `update` is one opaque pattern match — shown as a presence flag.
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
/// The pure snapshot the component inspector renders (JS introspectComponent):
/// name, id, fields (name/type/default), the typed-bucket name lists, the
/// update flag, and each view's raw template source.
pub fn component_summary(comp : @component.Component) -> @tutuca.Value {
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
  let names = (keys : Array[String]) => {
    let out : Array[@tutuca.Value] = []
    for k in keys {
      out.push(Str(k))
    }
    @tutuca.Value::List(out)
  }
  let views : Array[@tutuca.Value] = []
  for _name, view in comp.views {
    views.push(Map({ "name": Str(view.name), "rawView": Str(view.raw_view) }))
  }
  Map({
    "name": Str(comp.name),
    "id": Num(comp.id.to_double()),
    "fields": List(fields),
    "methods": names(comp.mutate_names + comp.compute_names),
    "update": names(if comp.has_update { ["update"] } else { [] }),
    "swap": names(comp.swap_names),
    "alter": names(comp.alter_names),
    "views": List(views),
  })
}

// ---------------------------------------------------------------------------
// Components
// ---------------------------------------------------------------------------

///|
priv struct NameState {
  name : String
} derive(ToJson, FromJson)

///|
/// A single name entry — used for methods and the handler channels, all of
/// which are just lists of names.
fn comp_name_comp() -> @component.Component {
  @component.component(
    name="CompName",
    init=NameState::{ name: "" },
    view=(
      #|<span class="font-mono text-sm leading-tight badge badge-sm badge-ghost comp-name" @text=".name"></span>
    ),
  )
}

///|
priv struct CompFieldState {
  name : String
  typeName : String
  child : @tutuca.Value
} derive(ToJson, FromJson)

///|
/// A single field row: `name : type = <default value>`. The default value is
/// rendered with the data inspector so it can recurse/expand.
fn comp_field_comp() -> @component.Component {
  @component.component(
    name="CompField",
    init=CompFieldState::{ name: "", typeName: "", child: Null },
    view=(
      #|<div class="flex items-center gap-2 leading-tight comp-field">
      #|  <span class="text-base-content/70 font-mono text-sm" @text=".name"></span>
      #|  <span class="text-base-content/30">:</span>
      #|  <span class="text-base-content/50 font-mono text-xs" @text=".typeName"></span>
      #|  <span class="text-base-content/30">=</span>
      #|  <x render=".child"></x>
      #|</div>
    ),
  )
}

///|
priv struct CompViewState {
  name : String
  rawView : String
  isExpanded : Bool
} derive(ToJson, FromJson)

///|
/// A single view: its name plus the raw template source in a code block. The
/// source collapses/expands independently. Plain click toggles it;
/// ctrl/cmd-click bubbles `toggleAllViews` so the top-level inspector can
/// toggle every one at once.
fn comp_view_comp() -> @component.Component {
  @component.component(
    name="CompView",
    init=CompViewState::{ name: "", rawView: "", isExpanded: false },
    compute={
      "arrowText": (s : CompViewState, _args) => {
        Str(if s.isExpanded { "▼" } else { "▶" })
      },
    },
    update=(s : CompViewState, msg, ctx) => {
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
    view=(
      #|<div class="flex flex-col gap-0.5 leading-tight comp-view">
      #|  <button
      #|    type="button"
      #|    class="cursor-pointer text-base-content/70 hover:text-base-content inline-flex items-center gap-1 self-start"
      #|    @on.click="toggle isCtrl">
      #|    <span @text="$arrowText"></span>
      #|    <span class="font-mono text-sm comp-view-name" @text=".name"></span>
      #|  </button>
      #|  <pre @show=".isExpanded" class="text-xs bg-base-200 rounded p-2 overflow-x-auto whitespace-pre-wrap"><code @text=".rawView"></code></pre>
      #|</div>
    ),
  )
}

///|
/// A labelled, collapsible, paginated group of entries. Reuses the same
/// composite machinery the JSON inspector uses; neutral chrome — hierarchy
/// via weight, colour reserved for status/severity.
priv struct CompSectionState {
  items : Array[@tutuca.Value]
  isExpanded : Bool
  itemsPerPage : Int
  currentPage : Int
  label : String
} derive(ToJson, FromJson)

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
  @component.component(
    name="CompSection",
    init=CompSectionState::{
      items: [],
      isExpanded: false,
      itemsPerPage: 10,
      currentPage: 0,
      label: "",
    },
    compute=composite_compute((s : CompSectionState) => s.label, s => {
      let n = s.items.length()
      "(\{n})"
    }),
    mutate=composite_mutate(),
    loop_with=composite_loop_with(),
    update=(s : CompSectionState, msg, ctx) => {
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
        _ => None
      }
    },
    view=make_composite_view(
      type_class="font-semibold comp-section",
      border_class="border-base-content/15",
      toggle_handler="toggle isCtrl",
    ),
  )
}

///|
priv struct ComponentInspectorState {
  compName : String
  compId : Int
  sections : Array[@tutuca.Value]
} derive(ToJson, FromJson)

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
  @component.component(
    name="ComponentInspector",
    init=ComponentInspectorState::{ compName: "", compId: 0, sections: [] },
    compute={
      "idText": (s : ComponentInspectorState, _args) => Str("#\{s.compId}"),
    },
    update=(s : ComponentInspectorState, msg, _ctx) => {
      match msg {
        Bubble("toggleAllSections", args) =>
          Some(set_all_sections(s, args.get(0) is Some(Bool(true))))
        Bubble("toggleAllViews", args) =>
          Some(set_all_views(s, args.get(0) is Some(Bool(true))))
        _ => None
      }
    },
    view=(
      #|<div class="font-mono text-sm leading-tight flex flex-col gap-1 component-inspector">
      #|  <div class="inline-flex items-center gap-2">
      #|    <span class="font-semibold comp-title" @text=".compName"></span>
      #|    <span class="text-base-content/40 text-xs" @text="$idText"></span>
      #|  </div>
      #|  <x render-each=".sections"></x>
      #|</div>
    ),
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
pub fn Inspector::component_view(
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
      ("Swap", "swap"),
      ("Alter", "alter"),
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
