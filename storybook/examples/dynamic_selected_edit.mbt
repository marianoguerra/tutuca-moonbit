// Port of docs/examples/dynamic-selected-edit.js.
//
// Dynamic bindings used as render targets — a single item and a whole
// sequence. `Root` owns a keyed map of entries and a `selectedKey`; it
// PRODUCES two dynamics: `items` = `.items` (the whole sequence) and
// `selected` = `.items[.selectedKey]` (a seq-access to the selected entry).
// The child `Editor` CONSUMES both: it iterates `*items` and renders the
// `*selected` entry with its `edit` view. The edited entry physically lives
// in `Root.items`, so edits in the child TELEPORT back to the owner — both
// lists update in lock-step.

///|
fn dse_entry_comp() -> @component.Component {
  dse_entry_component(name="Entry", init={ name: "" })
}

///|
fn dse_editor_comp() -> @component.Component {
  dse_editor_component(
    name="Editor",
    init={ missing: Null },
    // Consumer: forwards to Root's provides — a sequence and a single item.
    lookup={
      "items": { source: "Root.items", default: Some(".missing") },
      "selected": { source: "Root.selected", default: Some(".missing") },
    },
  )
}

///|
fn dse_root_comp() -> @component.Component {
  dse_root_component(
    name="Root",
    init={ ..DseRootState::zero(), items: Map([]), selectedKey: "" },
    // Producer: the whole sequence, plus a seq-access to the selected entry.
    provide={ "items": ".items", "selected": ".items[.selectedKey]" },
    update=(s, msg, _ctx) => {
      match DseRootMsg::from_dispatch(msg) {
        Some(SelectItem(Str(key))) => Some({ ..s, selectedKey: key })
        Some(SelectItem(_)) | Some(Unknown(_, _)) | None => None
      }
    },
  )
}

///|
fn dse_items(entry : @component.Component) -> @tutuca.Value {
  Map({
    "a": entry.make({ "name": Str("alpha") }),
    "b": entry.make({ "name": Str("beta") }),
    "c": entry.make({ "name": Str("gamma") }),
  })
}

///|
pub fn dynamic_selected_edit_module() -> @component.ModuleDef {
  let entry = dse_entry_comp()
  @component.ModuleDef::new(
    name="dynamic-selected-edit",
    components=[dse_root_comp(), dse_editor_comp(), entry],
    examples=[
      {
        component: "Root",
        title: "First selected",
        args: { "items": dse_items(entry), "selectedKey": Str("a") },
        view: None,
      },
      {
        component: "Root",
        title: "Second selected",
        args: { "items": dse_items(entry), "selectedKey": Str("b") },
        view: None,
      },
    ],
  )
}
