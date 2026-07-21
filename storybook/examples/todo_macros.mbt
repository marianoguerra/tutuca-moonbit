// Port of docs/examples/todo-macros.js — the to-do app rebuilt with macros for
// its repeated markup: checkbox, input, and button fragments, plus hbox/vbox
// layout wrappers, factored into reusable templates.
//
// The interesting bit is `^handler ^arg` INDIRECTION: a macro takes the handler
// name AND its argument as parameters, so `<x:btn-rm :handler="$removeInItemsAt"
// :arg="@key">` expands to `@on.click="$removeInItemsAt @key"`. Macro params are
// substituted as SOURCE TEXT, so a handler name or a loop binding threads
// straight through.

///|
fn tm_checkbox_macro() -> @anode.Macro {
  {
    defaults: { "value": ".value", "handler": "$setValue" },
    raw_view: "<input type=\"checkbox\" class=\"checkbox\" :checked=\"^value\" @on.input=\"^handler value\" />",
  }
}

///|
fn tm_input_macro() -> @anode.Macro {
  {
    defaults: { "value": ".value", "handler": "$setValue", "disabled": "false" },
    raw_view: "<input class=\"input\" :value=\"^value\" @on.input=\"^handler value\" :disabled=\"^disabled\" />",
  }
}

///|
fn tm_btn_rm_macro() -> @anode.Macro {
  {
    defaults: { "handler": "onRemove", "arg": "event" },
    raw_view: "<button class=\"btn btn-soft btn-sm btn-error btn-circle rm\" @on.click=\"^handler ^arg\">x</button>",
  }
}

///|
fn tm_btn_action_macro() -> @anode.Macro {
  {
    defaults: { "handler": "onAction", "arg": "event", "label": "'Action'" },
    raw_view: "<button class=\"btn btn-soft btn-success add\" @on.click=\"^handler ^arg\" @text=\"^label\"></button>",
  }
}

///|
fn tm_hbox_macro() -> @anode.Macro {
  {
    defaults: { "class": "''" },
    raw_view: "<div :class=\"$'hbox flex gap-3 items-center {^class}'\"><x:slot></x:slot></div>",
  }
}

///|
fn tm_vbox_macro() -> @anode.Macro {
  {
    defaults: { "class": "''" },
    raw_view: "<div :class=\"$'flex flex-col gap-3 {^class}'\"><x:slot name=\"_\"></x:slot></div>",
  }
}

///|
fn tm_item_comp() -> @component.Component {
  @component.component(
    name="Item",
    view=(
      #|<x:hbox>
      #|  <x:checkbox :value=".completed" :handler="$setCompleted"></x:checkbox>
      #|  <x:input :value=".text" :handler="$setText" :disabled=".completed"></x:input>
      #|</x:hbox>
    ),
    fields={
      "completed": @component.FieldSpec::of_default(Bool(false)),
      "text": @component.FieldSpec::of_default(Str("do the thing")),
    },
  )
}

///|
/// `:handler="onAddItem"` passes the handler NAME through the macro; the handler
/// itself captures the `Item` component in its closure (the value language has
/// no component-reference, so the JS `:arg="Item"` degrades to a harmless
/// ignored argument here).
fn tm_items_comp(item : @component.Component) -> @component.Component {
  @component.component(
    name="Items",
    view=(
      #|<x:vbox>
      #|  <x:btn-action label="Add Task" :handler="onAddItem"></x:btn-action>
      #|  <x:vbox class="w-full">
      #|    <div @each=".items" class="flex gap-3 justify-center items-center w-full entry">
      #|      <x render-it></x>
      #|      <x:btn-rm :handler="$removeInItemsAt" :arg="@key"></x:btn-rm>
      #|    </div>
      #|  </x:vbox>
      #|</x:vbox>
    ),
    fields={ "items": @component.FieldSpec::of_default(List([])) },
    input={
      "onAddItem": (inst, _args, _ctx) => {
        let items = match inst.get("items") {
          List(a) => a.copy()
          _ => []
        }
        items.push(
          item
          .make({ "completed": Bool(false), "text": Str("do the thing") })
          .to_value(),
        )
        Some(inst.set("items", List(items)))
      },
    },
  )
}

///|
pub fn todo_macros_module() -> @component.ModuleDef {
  let item = tm_item_comp()
  @component.ModuleDef::new(
    name="todo-macros",
    components=[tm_items_comp(item), item],
    macros={
      "btn-rm": tm_btn_rm_macro(),
      "btn-action": tm_btn_action_macro(),
      "checkbox": tm_checkbox_macro(),
      "input": tm_input_macro(),
      "hbox": tm_hbox_macro(),
      "vbox": tm_vbox_macro(),
    },
    examples=[
      { component: "Item", title: "Default Item", args: Map([]), view: None },
      {
        component: "Item",
        title: "Completed Item",
        args: { "completed": Bool(true) },
        view: None,
      },
      { component: "Items", title: "Empty List", args: Map([]), view: None },
      {
        component: "Items",
        title: "Some Items",
        args: {
          "items": List([
            item.make(Map([])).to_value(),
            item.make({ "completed": Bool(true) }).to_value(),
            item.make({ "completed": Bool(true), "text": Str("") }).to_value(),
          ]),
        },
        view: None,
      },
    ],
  )
}
