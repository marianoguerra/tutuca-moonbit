# Build a todo list (complete pairing)

**Problem:** a known-good, complete view + code pairing for a small app:
a list of child components over `Array[Item]`, `@when`
filtering, add / toggle / delete handlers, and controlled inputs.

One view file carries the whole module — the schema for both components
and a named `<template>` per component:

```html
<!-- todo.html -->
<script type="tutuca/spec">
  state Item { completed: Bool, text: String }
    state Items { items: Array[Item], hideCompleted: Bool }
</script>

<template id="Item">
  <div class="flex gap-3 items-center">
    <input type="checkbox" class="checkbox" :checked=".completed"
      @on.input=".completed = e.value">
    <input class="input" :value=".text" @on.input=".text = e.value"
      :disabled=".completed">
  </div>
</template>

<template id="Items">
  <div class="flex flex-col gap-3">
    <div class="flex gap-2">
      <button class="btn btn-soft btn-success add" @on.click="onAddItem">Add Task</button>
      <button class="btn btn-soft btn-sm toggle-done"
        @on.click=".hideCompleted = not .hideCompleted">Hide done</button>
    </div>
    <div class="flex flex-col gap-3 w-full">
      <div @each=".items" @when="onlyVisible"
        class="flex gap-3 items-center w-full row">
        <x render-it></x>
        <button class="btn btn-soft btn-sm btn-error btn-circle rm"
          @on.click=".items.removeAt @key">x</button>
      </div>
    </div>
  </div>
</template>
```

Generation derives every name from the template/interface ids:
`ItemState` / `ItemsState`, `item_component` / `items_component`,
`ItemsMsg::from_dispatch`, and the bucket enums.

There is no `<script type="tutuca/script">` block here, and this is the recipe
that shows why one is not always the answer. Each handler below is one of the
two reasons: **building a child component instance** (`item.make`), which that
language deliberately has no way to say, and **reading a path into a row**
(`@value.completed`), which `gen-views` does not compile — the rows are `Item`
INSTANCES, so the filter has to look inside one. Were `items` a list of plain
values, `onlyVisible` would be a `pred` in the spec block and this file would
have no `when` bucket at all (see [filter-a-list.md](filter-a-list.md)). What is left
is the handlers:

```moonbit
///|
fn todo_item_comp() -> @component.Component {
  item_component(initial=ItemState::{ completed: false, text: "do the thing" })
  // no update: the view writes `.completed` and `.text` itself, which is a
  // synchronous member write and raises no message at all. Give the component
  // an arm only when something has to HAPPEN besides the write.
}

fn todo_items_comp(item : @component.Component) -> @component.Component {
  items_component(
    initial=ItemsState::{ items: [], hideCompleted: false },
    update=(s, msg, _ctx) => match ItemsMsg::from_dispatch(msg) {
      // the handler CAPTURES the child Component; the view just says
      // @on.click="onAddItem" (no component-reference value exists)
      Some(OnAddItem) => Next({ ..s, items: s.items + [item.make(Map([]))] })
      // remove and hide are member operations the view performs itself
      // (`.items.removeAt @key`, `.hideCompleted = not .hideCompleted`), so
      // no name reaches here for either
      Some(Unknown(_, _)) | None => Unhandled
    },
    when=w => match w {
      // items are Item INSTANCES (Obj values) — read fields off them
      // with the value coercers
      OnlyVisible =>
        Some((s, _key, value, _iter, _stack) => {
          !s.hideCompleted || !value.field("completed").bool()
        })
    },
  )
}

pub fn todo_module() -> @component.ModuleDef {
  let item = todo_item_comp()
  @component.ModuleDef::new(
    name="todo",
    components=[todo_items_comp(item), item], // EVERY component, children too
    examples=[
      { component: "Items", title: "Empty", args: Map([]), view: None },
      {
        component: "Items",
        title: "Some Items",
        args: {
          "items": List([
            item.make(Map([])), // make() returns the instance as a Value
            item.make({ "completed": Bool(true) }),
          ]),
        },
        view: None,
      },
      { component: "Item", title: "One Item", args: Map([]), view: None },
    ],
  )
}
```

Why each piece is the way it is:

- **`items: Array[Item]`** — a field type may name a SIBLING `state`, and
  naming it is what lets the checker read `@each`'s body against `Item`'s
  own schema. The struct field is `items : Array[@tutuca.Value]` either way,
  holding `Item` instances built with `item.make(...)` — the element type
  costs nothing at runtime and buys the check. Append immutably:
  `s.items + [ ... ]`. Reach for `Array[Any]` only when the elements really
  are of different shapes.
- **`@each` + `<x render-it>`** renders each instance as its own `Item`
  component (fresh frame — the item handles its own events); the remove
  button sits **beside** `render-it` in the loop, so `.items.removeAt @key`
  writes the *list*'s own field, which is where the collection lives.
- **`@when="onlyVisible"`** filters at render time; the `when` bucket is
  a match over a generated enum (a raw `component()` call would take
  `when={ "onlyVisible": ... }` instead). The other way to write it is to put
  the predicate on the CHILD — `pred unfinished { not .completed }` in
  `Item`'s block — and have this `when` call it on each instance with
  `value.call_field("unfinished", [])`.
- **Add / toggle / delete** show the two handler routes: an `update` arm
  (`OnAddItem`), for the one that needs the child `Component` in scope, and a
  property action written in the view for the three that are only writes.

Test it end-to-end with the harness ([testing.md](../testing.md)):

```moonbit
test "todo: add, complete, filter" {
  let h = @harness.mount(todo_module(), "Items")
  h.click(".add")
  h.click(".add")
  assert_eq(h.find_all(".row").length(), 2)
  h.check(".checkbox", true)        // complete the first item
  h.click(".toggle-done")           // .hideCompleted = not .hideCompleted
  assert_eq(h.find_all(".row").length(), 1)
  h.click(".rm")                    // delete the visible one
  assert_eq(h.find_all(".row").length(), 0)
}
```
