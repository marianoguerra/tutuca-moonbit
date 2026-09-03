// A list of child components.
//
// MoonBit's Value has no component-reference variant, so the handler
// CAPTURES the `Item` component in its closure and the view just calls
// `@on.click="onAddItem"`. Same result, one less thing in the value language.

///|
fn todo_item_comp() -> @component.Component {
  item_component(init={ completed: false, text: "do the thing", })
}

///|
/// `<x render-it>` inside an `@each` renders whatever component instance the
/// loop is currently on. `$removeInItemsAt @key` is a generated list mutator,
/// passed the loop's key.
fn todo_items_comp(item : @component.Component) -> @component.Component {
  items_component(init={ items: [], }, update=(s, msg, _ctx) => {
    match ItemsMsg::from_dispatch(msg) {
      Some(OnAddItem) => Next({ items: s.items + [item.make(Map([]))], })
      Some(Unknown(_, _)) | None => Unhandled
    }
  })
}

///|
pub fn todo_module() -> @component.ModuleDef {
  let item = todo_item_comp()
  @component.ModuleDef::new(
    name="todo",
    components=[todo_items_comp(item), item],
    examples=[
      { component: "Item", title: "Default Item", args: Map([]), view: None, },
      {
        component: "Item",
        title: "Completed Item",
        args: { "completed": Bool(true) },
        view: None,
      },
      { component: "Items", title: "Default Items", args: Map([]), view: None, },
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
