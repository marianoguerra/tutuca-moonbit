// The to-do app rebuilt with macros for
// its repeated markup: checkbox, input, and button fragments, plus hbox/vbox
// layout wrappers, factored into reusable templates.
//
// The interesting bit is `^handler ^arg` INDIRECTION: a macro takes the handler
// name AND its argument as parameters, so `<x:btn-rm :handler="onRemoveItem"
// :arg="@key">` expands to `@on.click="removeInItemsAt @key"`. Macro params are
// substituted as SOURCE TEXT, so a handler name or a loop binding threads
// straight through.

///|
fn tm_checkbox_macro() -> @anode.Macro {
  {
    defaults: { "value": ".value", "handler": "onValue" },
    raw_view: "<input type=\"checkbox\" class=\"checkbox\" :checked=\"^value\" @on.input=\"^handler e.value\" />",
  }
}

///|
fn tm_input_macro() -> @anode.Macro {
  {
    defaults: { "value": ".value", "handler": "onValue", "disabled": "false" },
    raw_view: "<input class=\"input\" :value=\"^value\" @on.input=\"^handler e.value\" :disabled=\"^disabled\" />",
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
    views={
      "main": @anode.View::new(
        "main",
        raw_view=(
          #|<x:hbox>
          #|  <x:checkbox :value=".completed" :handler="onCompleted"></x:checkbox>
          #|  <x:input :value=".text" :handler="onText" :disabled=".completed"></x:input>
          #|</x:hbox>
        ),
      ),
    },
    name="Item",
    initial=TmItemState::{ completed: false, text: "do the thing", },
    // Declared arms, where the view used to pass `$setCompleted` / `$setText`
    // — generated mutators reached through the dispatch path. A `$name` and a
    // bare name are the same dispatch, so that was the fallback wearing a
    // sigil. A macro substitutes ONE TOKEN, so it cannot carry a property
    // action's target; what it carries is a handler name, and the component
    // declares what the macro asks for.
    update=(s : TmItemState, msg, _ctx) => {
      match msg {
        Receive("onCompleted", [v, ..]) =>
          Next({ ..s, completed: v.is_truthy(), })
        Receive("onText", [v, ..]) =>
          Next({ ..s, text: v.to_display_string(), })
        _ => Unhandled
      }
    },
  )
}

///|
/// `:handler="onAddItem"` passes the handler NAME through the macro; the handler
/// itself captures the `Item` component in its closure (the value language has
/// no component-reference, so a `:arg="Item"` would degrade to a harmless
/// ignored argument).
fn tm_items_comp(item : @component.Component) -> @component.Component {
  @component.component(
    views={
      "main": @anode.View::new(
        "main",
        raw_view=(
          #|<x:vbox>
          #|  <x:btn-action label="Add Task" :handler="onAddItem"></x:btn-action>
          #|  <x:vbox class="w-full">
          #|    <div @each=".items" class="flex gap-3 justify-center items-center w-full entry">
          #|      <x render-it></x>
          #|      <x:btn-rm :handler="onRemoveItem" :arg="@key"></x:btn-rm>
          #|    </div>
          #|  </x:vbox>
          #|</x:vbox>
        ),
      ),
    },
    name="Items",
    initial=TmItemsState::{ items: [], },
    update=(s : TmItemsState, msg, _ctx) => {
      match msg {
        // A DECLARED arm, where the view used to pass `$removeInItemsAt` — a
        // generated mutator reached through the dispatch path. A `$name` and a
        // bare name are the same dispatch, so that was the fallback wearing a
        // sigil; a macro cannot carry a property action, so the component
        // declares what the macro asks for.
        Receive("onRemoveItem", [Num(at), ..]) => {
          let drop = at.to_int()
          let kept : Array[@tutuca.Value] = []
          for i, v in s.items {
            if i != drop {
              kept.push(v)
            }
          }
          Next({ items: kept, })
        }
        Receive("onAddItem", _) =>
          Next({
            items: s.items +
            [
              item.make({
                "completed": Bool(false),
                "text": Str("do the thing"),
              }),
            ],
          })
        _ => Unhandled
      }
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
      { component: "Item", title: "Default Item", args: Map([]), view: None, },
      {
        component: "Item",
        title: "Completed Item",
        args: { "completed": Bool(true) },
        view: None,
      },
      { component: "Items", title: "Empty List", args: Map([]), view: None, },
      {
        component: "Items",
        title: "Some Items",
        args: {
          "items": List([
            item.make(Map([])),
            item.make({ "completed": Bool(true) }),
            item.make({ "completed": Bool(true), "text": Str("") }),
          ]),
        },
        view: None,
      },
    ],
  )
}
