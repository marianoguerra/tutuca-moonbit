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
  @component.component(
    name="Entry",
    // main view: read-only display, used inside the lists.
    view="<span class=\"font-mono entry\" @text=\".name\"></span>",
    views={
      // edit view: rendered by the child Editor via <x render="*selected" as="edit">
      "edit": (
        #|<input class="input input-bordered w-full edit-name" :value=".name" @on.input="$setName value" placeholder="Entry name" />
      ),
    },
    fields={ "name": @component.FieldSpec::of_default(Str("")) },
  )
}

///|
fn dse_editor_comp() -> @component.Component {
  @component.component(
    name="Editor",
    view=(
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
    fields={ "missing": @component.FieldSpec::of_default(Null) },
    // Consumer: forwards to Root's provides — a sequence and a single item.
    lookup={
      "items": { source: "Root.items", default: Some(".missing") },
      "selected": { source: "Root.selected", default: Some(".missing") },
    },
  )
}

///|
fn dse_root_comp() -> @component.Component {
  @component.component(
    name="Root",
    view=(
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
    fields={
      "items": @component.FieldSpec::of_default(Map({})),
      "selectedKey": @component.FieldSpec::of_default(Str("")),
      "editor": @component.FieldSpec::comp("Editor"),
    },
    // Producer: the whole sequence, plus a seq-access to the selected entry.
    provide={ "items": ".items", "selected": ".items[.selectedKey]" },
    input={
      "selectItem": (inst, args, _ctx) => {
        guard args is [Str(key), ..] else { return None }
        Some(inst.set("selectedKey", Str(key)))
      },
    },
  )
}

///|
fn dse_items(entry : @component.Component) -> @tutuca.Value {
  Map({
    "a": entry.make({ "name": Str("alpha") }).to_value(),
    "b": entry.make({ "name": Str("beta") }).to_value(),
    "c": entry.make({ "name": Str("gamma") }).to_value(),
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
