// Port of docs/examples/todo.js — a list of child components.
//
// The JS view passes the component itself as a handler argument
// (`@on.click="onAddItem Item"`), because JS can put a component in the value
// world. MoonBit's Value has no component-reference variant, so the handler
// CAPTURES the `Item` component in its closure instead and the view just calls
// `@on.click="onAddItem"`. Same result, one less thing in the value language.

///|
priv struct TodoItemState {
  completed : Bool
  text : String
} derive(ToJson, FromJson)

///|
fn todo_item_comp() -> @component.Component {
  @component.component(
    name="Item",
    view=(
      #|<div class="flex gap-3 items-center">
      #|  <input type="checkbox" class="checkbox" :checked=".completed" @on.input="$setCompleted value" />
      #|  <input class="input" :value=".text" @on.input="$setText value" :disabled=".completed" />
      #|</div>
    ),
    init=TodoItemState::{ completed: false, text: "do the thing" },
  )
}

///|
priv struct TodoItemsState {
  items : Array[@tutuca.Value]
} derive(ToJson, FromJson)

///|
/// `<x render-it>` inside an `@each` renders whatever component instance the
/// loop is currently on. `$removeInItemsAt @key` is a generated list mutator,
/// passed the loop's key.
fn todo_items_comp(item : @component.Component) -> @component.Component {
  @component.component(
    name="Items",
    view=(
      #|<div class="flex flex-col gap-3">
      #|  <button class="btn btn-soft btn-success add" @on.click="onAddItem">Add Task</button>
      #|  <div class="flex flex-col gap-3 w-full">
      #|    <div @each=".items" class="flex gap-3 justify-center items-center w-full row">
      #|      <x render-it></x>
      #|      <button class="btn btn-soft btn-sm btn-error btn-circle font-mono rm" @on.click="$removeInItemsAt @key">x</button>
      #|    </div>
      #|  </div>
      #|</div>
    ),
    init=TodoItemsState::{ items: [] },
    update=(s : TodoItemsState, msg, _ctx) => {
      match msg {
        Input("onAddItem", _) => Some({ items: s.items + [item.make(Map([]))] })
        _ => None
      }
    },
  )
}

///|
pub fn todo_module() -> @component.ModuleDef {
  let item = todo_item_comp()
  @component.ModuleDef::new(
    name="todo",
    components=[todo_items_comp(item), item],
    examples=[
      { component: "Item", title: "Default Item", args: Map([]), view: None },
      {
        component: "Item",
        title: "Completed Item",
        args: { "completed": Bool(true) },
        view: None,
      },
      { component: "Items", title: "Default Items", args: Map([]), view: None },
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
