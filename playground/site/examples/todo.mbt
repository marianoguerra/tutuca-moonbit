// Todo list — a list of editable child Item components you can add and remove.

///|
struct TodoItemState {
  completed : Bool
  text : String
} derive(ToJson, FromJson)

///|
fn todo_item_comp() -> @component.Component {
  @component.component(
  compiled_views={
    "main": @anode.View::new("main", raw_view=(
      #|<div class="flex gap-3 items-center">
      #|  <input type="checkbox" class="checkbox" :checked=".completed" @on.input="$setCompleted value" />
      #|  <input class="input" :value=".text" @on.input="$setText value" :disabled=".completed" />
      #|</div>
    )),
  },
  name="Item",
  init=TodoItemState::{ completed: false, text: "do the thing" },
)
}

///|
/// `<x render-it>` inside an `@each` renders whatever component instance the
/// loop is currently on. `$removeInItemsAt @key` is a generated list mutator,
/// passed the loop's key.
struct TodoItemsState {
  items : Array[@tutuca.Value]
} derive(ToJson, FromJson)

///|
fn todo_items_comp(item : @component.Component) -> @component.Component {
  @component.component(
  compiled_views={
    "main": @anode.View::new("main", raw_view=(
      #|<div class="flex flex-col gap-3">
      #|  <button class="btn btn-soft btn-success add" @on.click="onAddItem">Add Task</button>
      #|  <div class="flex flex-col gap-3 w-full">
      #|    <div @each=".items" class="flex gap-3 justify-center items-center w-full row">
      #|      <x render-it></x>
      #|      <button class="btn btn-soft btn-sm btn-error btn-circle font-mono rm" @on.click="$removeInItemsAt @key">x</button>
      #|    </div>
      #|  </div>
      #|</div>
    )),
  },
  name="Items",
  init=TodoItemsState::{ items: [] },
  update=(s : TodoItemsState, msg, _ctx) => match msg {
      Input("onAddItem", _) => Some({ items: s.items + [item.make(Map([]))] })
      _ => None
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

fn build() -> @component.ModuleDef {
  // The playground mounts the module's FIRST example, so lead with the Items
  // list (starts empty — click "Add Task" to append editable rows). The full
  // gallery (single Item, completed Item, …) still lives in todo_module().
  let m = todo_module()
  @component.ModuleDef::new(
    name=m.name,
    components=m.components,
    examples=[
      { component: "Items", title: "List", args: Map([]), view: None },
      ..m.examples,
    ],
  )
}
