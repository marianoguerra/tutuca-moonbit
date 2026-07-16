// Todo list — a list of editable child Item components you can add and remove.

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
    fields={
      "completed": @component.FieldSpec::of_default(Bool(false)),
      "text": @component.FieldSpec::of_default(Str("do the thing")),
    },
  )
}

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
    fields={ "items": @component.FieldSpec::of_default(List([])) },
    input={
      "onAddItem": (inst, _args, _ctx) => {
        let items = match inst.get("items") {
          List(a) => a.copy()
          _ => []
        }
        items.push(item.make(Map([])).to_value())
        Some(inst.set("items", List(items)))
      },
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

fn build() -> @component.ModuleDef {
  todo_module()
}

fn main {
  // mount the list (the module's first example is a single Item); starts empty,
  // click "Add Task" to append editable rows
  @host.mount(build(), "app", root="Items")
}
