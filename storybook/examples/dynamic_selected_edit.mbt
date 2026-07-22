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
priv struct DseEntryState {
  name : String
} derive(ToJson, FromJson)

///|
fn dse_entry_comp() -> @component.Component {
  @component.component(
    compiled_views={
      "main": @anode.View::new(
        "main",
        raw_view="<span class=\"font-mono entry\" @text=\".name\"></span>",
      ),
      "edit": @anode.View::new(
        "edit",
        raw_view=(
          #|<input class="input input-bordered w-full edit-name" :value=".name" @on.input="$setName value" placeholder="Entry name" />
        ),
      ),
    },
    name="Entry",
    init=DseEntryState::{ name: "" },
  )
}

///|
priv struct DseEditorState {
  missing : @tutuca.Value
} derive(ToJson, FromJson)

///|
fn dse_editor_comp() -> @component.Component {
  @component.component(
    compiled_views={
      "main": @anode.View::new(
        "main",
        raw_view=(
          #|<div class="card bg-base-200 p-3 gap-3 editor">
          #|  <span class="text-xs opacity-60">Editor (child component)</span>
          #|  <div class="flex flex-col gap-1">
          #|    <span class="text-xs opacity-60">All entries — rendered from the *items lookup:</span>
          #|    <div @each="*items" class="flex gap-3 flex-wrap child-items"><x render-it></x></div>
          #|  </div>
          #|  <div class="flex flex-col gap-1">
          #|    <span class="text-xs opacity-60">Editing the *selected entry:</span>
          #|    <x render="*selected" as="edit"></x>
          #|  </div>
          #|</div>
        ),
      ),
    },
    name="Editor",
    init=DseEditorState::{ missing: Null },
    // Consumer: forwards to Root's provides — a sequence and a single item.
    lookup={
      "items": { source: "Root.items", default: Some(".missing") },
      "selected": { source: "Root.selected", default: Some(".missing") },
    },
  )
}

///|
priv struct DseRootState {
  items : Map[String, @tutuca.Value]
  selectedKey : String
} derive(ToJson, FromJson)

///|
fn dse_root_comp() -> @component.Component {
  @component.component(
    compiled_views={
      "main": @anode.View::new(
        "main",
        raw_view=(
          #|<div class="flex flex-col gap-3 p-3">
          #|  <div class="alert">
          #|    <span>Selected key = <b class="selected-key" @text=".selectedKey"></b></span>
          #|  </div>
          #|  <div class="flex flex-col gap-2">
          #|    <span class="text-xs opacity-60">Entries — rendered from the *items dynamic (owner):</span>
          #|    <div @each="*items" class="flex gap-3 items-center owner-row">
          #|      <x render-it></x>
          #|      <button class="btn btn-xs btn-soft select" @on.click="selectItem @key">select</button>
          #|    </div>
          #|  </div>
          #|  <x render=".editor"></x>
          #|</div>
        ),
      ),
    },
    name="Root",
    init=DseRootState::{ items: Map([]), selectedKey: "" },
    specs={ "editor": @component.FieldSpec::comp("Editor") },
    // Producer: the whole sequence, plus a seq-access to the selected entry.
    provide={ "items": ".items", "selected": ".items[.selectedKey]" },
    update=(s : DseRootState, msg, _ctx) => {
      match msg {
        Input("selectItem", [Str(key), ..]) => Some({ ..s, selectedKey: key })
        _ => None
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
