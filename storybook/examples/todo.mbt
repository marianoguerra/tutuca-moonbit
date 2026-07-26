// Port of docs/examples/todo.js — a list of child components.
//
// The JS view passes the component itself as a handler argument
// (`@on.click="onAddItem Item"`), because JS can put a component in the value
// world. MoonBit's Value has no component-reference variant, so the handler
// CAPTURES the `Item` component in its closure instead and the view just calls
// `@on.click="onAddItem"`. Same result, one less thing in the value language.

///|
fn todo_item_comp() -> @component.Component {
  @component.component(
    views=item_views(),
    name="Item",
    init=ItemState::{ completed: false, text: "do the thing" },
    // The schema-generated direct codec, in place of the JSON bridge.
    encode=item_encode,
    decode=item_decode,
  )
}

///|
/// `<x render-it>` inside an `@each` renders whatever component instance the
/// loop is currently on. `$removeInItemsAt @key` is a generated list mutator,
/// passed the loop's key.
fn todo_items_comp(item : @component.Component) -> @component.Component {
  @component.component(
    views=items_views(),
    name="Items",
    init=ItemsState::{ items: [] },
    update=(s : ItemsState, msg, _ctx) => {
      match ItemsMsg::from_dispatch(msg) {
        Some(OnAddItem) => Some({ items: s.items + [item.make(Map([]))] })
        Some(Unknown(_, _)) | None => None
      }
    },
    // The schema-generated direct codec, in place of the JSON bridge.
    encode=items_encode,
    decode=items_decode,
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
