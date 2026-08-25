// Inspect a Component
// *descriptor* (the value returned by `@component.component(...)`), not a
// made instance.
//
// A `@component.Component` is not a `@tutuca.Value`, so the inspector takes a
// SNAPSHOT: `component_summary(comp)` returns a plain Value Map
// and the components render that. Typed-state
// deviations:
// - fields come from `Component::specs` (derived from the init state +
//   explicit slot specs).
// - the handler channels are the typed buckets: `compute` lists its names
//   ("Methods"), the render-time buckets list under "Alter", and `update` is
//   one opaque pattern match — shown as a presence flag.
// - generated field mutators never appear (they live in their own table).

///|
/// The pure snapshot the component inspector renders.
///
/// One source: what the component DECLARES. Field types show the author's WIT
/// spelling rather than a label reconstructed from a runtime kind, and
/// `update` lists the names it answers instead of the bare fact that it
/// exists.
pub fn component_summary(comp : @component.Component) -> @tutuca.Value {
  summary_from_schema(comp, comp.schema)
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
      "type": Str(f.ty.show_source()),
      // Its type's zero, off the SCHEMA.
      "default": f.default(),
    }
    // What it CONTAINS, which is now a different question from "may a view
    // `@each` over it?" — that one has to answer yes for `any` and for a child
    // slot, and answering both with one method put a meaningless `elem: any`
    // on this row for every dynamic field in the corpus.
    match f.ty.elem() {
      Some(e) => row["elem"] = Str(e.show_source())
      None => ()
    }
    match f.ty.slot() {
      Some(c) => row["slot"] = Str(c)
      None => ()
    }
    let members = f.ty.members()
    if !members.is_empty() {
      row["members"] = name_list(members)
    }
    fields.push(Map(row))
  }
  Map({
    "name": Str(comp.name),
    "id": Num(comp.id.to_double()),
    "fingerprint": Str(si.fingerprint),
    "fields": List(fields),
    "methods": name_list(si.methods),
    "viewHandlers": name_list(si.view_handlers),
    "receive": name_list(si.receives),
    "intent": name_list(si.intents),
    "swap": name_list(comp.swap_names),
    "alter": name_list(comp.alter_names),
    "ids": name_list(si.ids),
    "fixtures": name_list(si.init_names),
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
          Some((s, _args, _stack) => {
            Str(if s.isExpanded { "▼" } else { "▶" })
          })
      }
    },
    update=(s, msg, ctx) => {
      match msg {
        Receive("toggle", args) =>
          if args.get(0) is Some(Bool(true)) {
            ctx.intent(
              "toggleAllViews",
              [Bool(!s.isExpanded)],
              @tutuca.IntentOpts::new(route=[Dyn]),
            )
            Unhandled
          } else {
            Next({ ..s, isExpanded: !s.isExpanded })
          }
        _ => Unhandled
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
        TypeText => Some((s, _args, _stack) => Str(s.label))
        CountText => Some((s, _args, _stack) => Str("(\{s.items.length()})"))
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
        Receive("toggle", args) =>
          if args.get(0) is Some(Bool(true)) {
            ctx.intent(
              "toggleAllSections",
              [Bool(!s.isExpanded)],
              @tutuca.IntentOpts::new(route=[Dyn]),
            )
            Unhandled
          } else {
            Next({ ..s, isExpanded: !s.isExpanded })
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
    sections: s.sections.map(sec => sec.with_field("isExpanded", Bool(state))),
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
      if sec.field_opt("label") is Some(Str("Views")) {
        match sec.field_opt("items") {
          Some(List(views)) =>
            sec.with_field(
              "items",
              List(views.map(v => v.with_field("isExpanded", Bool(state)))),
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
        IdText => Some((s, _args, _stack) => Str("#\{s.compId}"))
      }
    },
    update=(s, msg, _ctx) => {
      match ComponentInspectorIntent::from_dispatch(msg) {
        Some(ToggleAllSections(on)) => Next(set_all_sections(s, on))
        Some(ToggleAllViews(on)) => Next(set_all_views(s, on))
        Some(Unknown(_, _)) | None => Unhandled
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
/// Build a ComponentInspector instance from a `component_summary` snapshot.
/// Empty groups are omitted.
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
      ("View handlers", "viewHandlers"),
      ("Receive", "receive"),
      ("Intent", "intent"),
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
/// Snapshot + render in one step.
pub fn Inspector::inspect_component(
  self : Inspector,
  comp : @component.Component,
) -> @tutuca.Value {
  self.component_view(component_summary(comp))
}
