// Ports of:
//   docs/examples/dynamic-bindings.js — provide / lookup, `*name` as a value
//   docs/examples/dynamic-path.js     — `*name` as a RENDER TARGET (teleport)
//
// A producer publishes a value under a name; any descendant reads it as `*name`
// without the value being threaded through the components in between. A
// `provide` must be ADDRESSABLE (a field or a `.seq[.key]` access), because it
// doubles as the teleport path — a method or a constant is a lint error.

///|
fn selector_entry_comp() -> @component.Component {
  @component.component(
    name="SelectorEntry",
    view=(
      #|<div class="flex gap-3">
      #|  <input class="input val" :value=".value" @on.input="$setValue value" />
      #|  <input class="input lbl" :value=".label" @on.input="$setLabel value" />
      #|</div>
    ),
    fields={
      "value": @component.FieldSpec::of_default(Str("entry-value")),
      "label": @component.FieldSpec::of_default(Str("Entry Label")),
    },
  )
}

///|
/// The CONSUMER: it has no items of its own, it reads the producer's list as
/// `*entries`. The `default` is used only when no producer is in the render
/// stack.
fn selector_comp() -> @component.Component {
  @component.component(
    name="Selector",
    view=(
      #|<select class="select" :value=".selectedValue" @on.input="$setSelectedValue value">
      #|  <option @each="*entries" :value="@value.value" @text="@value.label"></option>
      #|</select>
    ),
    fields={
      "items": @component.FieldSpec::of_default(List([])),
      "selectedValue": @component.FieldSpec::of_default(Null),
    },
    lookup={
      "entries": {
        source: "EntryEditorAndSelector.entries",
        default: Some(".items"),
      },
    },
  )
}

///|
/// The PRODUCER: every `provide` is evaluated and pushed onto the stack when the
/// component is entered during render — there is no hook to opt in.
fn entry_editor_comp(entry : @component.Component) -> @component.Component {
  @component.component(
    name="EntryEditorAndSelector",
    view=(
      #|<div class="flex flex-col gap-3">
      #|  <div class="flex gap-3 justify-center">
      #|    <x render=".selector"></x>
      #|  </div>
      #|  <button class="btn btn-soft btn-success add" @on.click="onAddItem">Add Entry</button>
      #|  <div class="flex flex-col gap-3 w-full">
      #|    <div @each=".items" class="flex gap-3 justify-center items-center w-full row">
      #|      <x render-it></x>
      #|      <button class="btn btn-soft btn-sm btn-error btn-circle font-mono rm" @on.click="$removeInItemsAt @key">x</button>
      #|    </div>
      #|  </div>
      #|</div>
    ),
    fields={
      "items": @component.FieldSpec::of_default(List([])),
      "selector": @component.FieldSpec::comp("Selector"),
    },
    provide={ "entries": ".items" },
    input={
      "onAddItem": (inst, _args, _ctx) => {
        let items = match inst.get("items") {
          List(a) => a.copy()
          _ => []
        }
        let num = items.length() + 1
        items.push(
          entry
          .make({ "value": Str("entry-\{num}"), "label": Str("Entry #\{num}") })
          .to_value(),
        )
        Some(inst.set("items", List(items)))
      },
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
        args: {},
        view: None,
      },
      {
        component: "EntryEditorAndSelector",
        title: "With Entries",
        args: {
          "items": List([
            entry.make({ "value": Str("a"), "label": Str("Alpha") }).to_value(),
            entry.make({ "value": Str("b"), "label": Str("Beta") }).to_value(),
          ]),
        },
        view: None,
      },
    ],
  )
}

///|
/// A dynamic var resolves to a VALUE, so it works anywhere a value is read —
/// including as a component-render target: `<x render="*active">`.
fn sheet_comp() -> @component.Component {
  @component.component(
    name="Sheet",
    view=(
      #|<div class="card bg-base-200 p-3 gap-2 sheet">
      #|  <span class="text-xs opacity-60 tag">Sheet (rendered via *active)</span>
      #|  <input class="input input-bordered title" :value=".title" @on.input="$setTitle value" />
      #|</div>
    ),
    fields={ "title": @component.FieldSpec::of_default(Str("untitled")) },
  )
}

///|
/// The consumer, far from the producer: it renders a component it does not own.
fn toolbar_comp() -> @component.Component {
  @component.component(
    name="Toolbar",
    view=(
      #|<div class="border border-dashed border-warning rounded p-3 gap-2 toolbar">
      #|  <span class="text-xs opacity-60 tag">Toolbar (consumer)</span>
      #|  <x render="*active"></x>
      #|</div>
    ),
    lookup={
      "active": { source: "Workspace.active", default: Some(".missing") },
    },
  )
}

///|
fn panel_comp() -> @component.Component {
  @component.component(
    name="Panel",
    view=(
      #|<div class="border border-dashed border-info rounded p-3 gap-2 panel">
      #|  <span class="text-xs opacity-60 tag">Panel (intermediate)</span>
      #|  <x render=".toolbar"></x>
      #|</div>
    ),
    fields={ "toolbar": @component.FieldSpec::comp("Toolbar") },
  )
}

///|
/// The producer. The Sheet rendered inside Toolbar physically lives HERE, at
/// `Workspace.sheet` — so editing its title TELEPORTS: the event path is
/// expanded through Workspace → Panel → Toolbar for reconstruction, but the
/// transaction lands on `Workspace.sheet`. The echoed title at the top is the
/// proof; it updates in lock-step.
fn workspace_comp() -> @component.Component {
  @component.component(
    name="Workspace",
    view=(
      #|<div class="flex flex-col gap-3 p-3">
      #|  <div class="alert">
      #|    <span>Workspace.sheet.title = <b class="echo" @text="$sheetTitle"></b></span>
      #|  </div>
      #|  <x render=".panel"></x>
      #|</div>
    ),
    fields={
      "sheet": @component.FieldSpec::comp("Sheet"),
      "panel": @component.FieldSpec::comp("Panel"),
    },
    provide={ "active": ".sheet" },
    methods={
      "sheetTitle": (inst, _args) => {
        match inst.get("sheet") {
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
      { component: "Workspace", title: "Default", args: {}, view: None },
    ],
  )
}
