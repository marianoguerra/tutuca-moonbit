// Todo list — a list of editable child Item components you can add and remove.
// Both components' views live in the View tab (todo.html): one file per module,
// `<template id="Item">` / `<template id="Items">` naming each. They arrive
// here as `item_views()` and `items_views()`.


///|
fn todo_item_comp() -> @component.Component {
  item_component(
    initial=ItemState::{ completed: false, text: "do the thing" },
  )
}


///|
fn todo_items_comp(item : @component.Component) -> @component.Component {
  items_component(
    initial=ItemsState::{ items: [] },
    update=(s, msg, _ctx) => match ItemsMsg::from_dispatch(msg) {
      Some(OnAddItem) => Next({ items: s.items + [item.make(Map([]))] })
      Some(Unknown(_, _)) | None => Unhandled
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
