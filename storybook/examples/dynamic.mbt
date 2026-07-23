// Ports of:
//   docs/examples/dynamic-bindings.js — provide / lookup, `*name` as a value
//   docs/examples/dynamic-path.js     — `*name` as a RENDER TARGET (teleport)
//
// A producer publishes a value under a name; any descendant reads it as `*name`
// without the value being threaded through the components in between. A
// `provide` must be ADDRESSABLE (a field or a `.seq[.key]` access), because it
// doubles as the teleport path — a method or a constant is a lint error.

///|
priv struct SelectorEntryState {
  value : String
  label : String
} derive(ToJson, FromJson)

///|
fn selector_entry_comp() -> @component.Component {
  @component.component(views=selector_entry_views(), name="SelectorEntry", init=SelectorEntryState::{
    value: "entry-value",
    label: "Entry Label",
  })
}

///|
priv struct SelectorState {
  items : Array[@tutuca.Value]
  selectedValue : @tutuca.Value
} derive(ToJson, FromJson)

///|
/// The CONSUMER: it has no items of its own, it reads the producer's list as
/// `*entries`. The `default` is used only when no producer is in the render
/// stack.
fn selector_comp() -> @component.Component {
  @component.component(
    views=selector_views(),
    name="Selector",
    init=SelectorState::{ items: [], selectedValue: Null },
    lookup={
      "entries": {
        source: "EntryEditorAndSelector.entries",
        default: Some(".items"),
      },
    },
  )
}

///|
priv struct EntryEditorState {
  items : Array[@tutuca.Value]
} derive(ToJson, FromJson)

///|
/// The PRODUCER: every `provide` is evaluated and pushed onto the stack when the
/// component is entered during render — there is no hook to opt in.
fn entry_editor_comp(entry : @component.Component) -> @component.Component {
  @component.component(
    views=entry_editor_and_selector_views(),
    name="EntryEditorAndSelector",
    init=EntryEditorState::{ items: [] },
    specs={ "selector": @component.FieldSpec::comp("Selector") },
    provide={ "entries": ".items" },
    update=(s : EntryEditorState, msg, _ctx) => {
      match EntryEditorAndSelectorMsg::of_dispatch(msg) {
        Some(OnAddItem) => {
          let num = s.items.length() + 1
          Some({
            items: s.items +
            [
              entry.make({
                "value": Str("entry-\{num}"),
                "label": Str("Entry #\{num}"),
              }),
            ],
          })
        }
        Some(Unknown(_, _)) | None => None
      }
    },
  )
}

///|
pub fn dynamic_bindings_module() -> @component.ModuleDef {
  let entry = selector_entry_comp()
  @component.ModuleDef::new(
    name="dynamic-bindings",
    components=[entry_editor_comp(entry), selector_comp(), entry],
    examples=[
      {
        component: "EntryEditorAndSelector",
        title: "Default",
        args: Map([]),
        view: None,
      },
      {
        component: "EntryEditorAndSelector",
        title: "With Entries",
        args: {
          "items": List([
            entry.make({ "value": Str("a"), "label": Str("Alpha") }),
            entry.make({ "value": Str("b"), "label": Str("Beta") }),
          ]),
        },
        view: None,
      },
    ],
  )
}

///|
priv struct SheetState {
  title : String
} derive(ToJson, FromJson)

///|
/// A dynamic var resolves to a VALUE, so it works anywhere a value is read —
/// including as a component-render target: `<x render="*active">`.
fn sheet_comp() -> @component.Component {
  @component.component(views=sheet_views(), name="Sheet", init=SheetState::{
    title: "untitled",
  })
}

///|
priv struct ToolbarState {} derive(ToJson, FromJson)

///|
/// The consumer, far from the producer: it renders a component it does not own.
fn toolbar_comp() -> @component.Component {
  @component.component(
    views=toolbar_views(),
    name="Toolbar",
    init=ToolbarState::{  },
    lookup={
      "active": { source: "Workspace.active", default: Some(".missing") },
    },
  )
}

///|
priv struct PanelState {} derive(ToJson, FromJson)

///|
fn panel_comp() -> @component.Component {
  @component.component(
    views=panel_views(),
    name="Panel",
    init=PanelState::{  },
    specs={ "toolbar": @component.FieldSpec::comp("Toolbar") },
  )
}

///|
/// `sheet` is declared in the state (the compute below reads it) AND in
/// `specs` as a comp slot — the spec entry keeps the scope-made default.
priv struct WorkspaceState {
  sheet : @tutuca.Value
} derive(ToJson, FromJson)

///|
/// The producer. The Sheet rendered inside Toolbar physically lives HERE, at
/// `Workspace.sheet` — so editing its title TELEPORTS: the event path is
/// expanded through Workspace → Panel → Toolbar for reconstruction, but the
/// transaction lands on `Workspace.sheet`. The echoed title at the top is the
/// proof; it updates in lock-step.
fn workspace_comp() -> @component.Component {
  @component.component(
    views=workspace_views(),
    name="Workspace",
    init=WorkspaceState::{ sheet: Null },
    specs={
      "sheet": @component.FieldSpec::comp("Sheet"),
      "panel": @component.FieldSpec::comp("Panel"),
    },
    provide={ "active": ".sheet" },
    compute={
      "sheetTitle": (s : WorkspaceState, _args) => {
        match s.sheet {
          Obj(o) => o.obj_field("title").unwrap_or(Str(""))
          _ => Str("")
        }
      },
    },
  )
}

///|
pub fn dynamic_path_module() -> @component.ModuleDef {
  @component.ModuleDef::new(
    name="dynamic-path",
    components=[workspace_comp(), panel_comp(), toolbar_comp(), sheet_comp()],
    examples=[
      { component: "Workspace", title: "Default", args: Map([]), view: None },
    ],
  )
}
