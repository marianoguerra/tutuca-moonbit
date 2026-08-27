# Build a todo list (complete pairing)

**Problem:** a known-good, complete view + code pairing for a small app:
a list of child components over `Array[Any]`, `@when`
filtering, add / toggle / delete handlers, and controlled inputs.

One view file carries the whole module — the schema for both components
and a named `<template>` per component:

```html
<!-- todo.html -->
<script type="tutuca/spec">
  state Item { completed: Bool, text: String }
    state Items { items: Array[Any], hideCompleted: Bool }
</script>

<template id="Item">
  <div class="flex gap-3 items-center">
    <input type="checkbox" class="checkbox" :checked=".completed"
      @on.input="setCompleted e.value">
    <input class="input" :value=".text" @on.input="setText e.value"
      :disabled=".completed">
  </div>
</template>

<template id="Items">
  <div class="flex flex-col gap-3">
    <div class="flex gap-2">
      <button class="btn btn-soft btn-success add" @on.click="onAddItem">Add Task</button>
      <button class="btn btn-soft btn-sm toggle-done"
        @on.click="toggleHideCompleted">Hide done</button>
    </div>
    <div class="flex flex-col gap-3 w-full">
      <div @each=".items" @when="onlyVisible"
        class="flex gap-3 items-center w-full row">
        <x render-it></x>
        <button class="btn btn-soft btn-sm btn-error btn-circle rm"
          @on.click="removeInItemsAt @key">x</button>
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
  item_component(init=ItemState::{ completed: false, text: "do the thing" })
  // no update: `setCompleted e.value` and `setText e.value` are served by the
  // generated mutators. If you do want an update arm, the typed cases are
  // SetCompleted(Bool) and SetText(String) — `e.value` infers Bool on a
  // checkbox (events.md "Generated `Msg` payload types").
}

fn todo_items_comp(item : @component.Component) -> @component.Component {
  items_component(
    init=ItemsState::{ items: [], hideCompleted: false },
    update=(s, msg, _ctx) => match ItemsMsg::from_dispatch(msg) {
      // the handler CAPTURES the child Component; the view just says
      // @on.click="onAddItem" (no component-reference value exists)
      Some(OnAddItem) => Next({ ..s, items: s.items + [item.make(Map([]))] })
      // `@key` is a binding, so the payload is @tutuca.Value; returning
      // None falls through to the generated list mutator, which answers it
      Some(RemoveInItemsAt(_)) => Unhandled
      // toggleHideCompleted: generated Bool mutator — same fall-through
      Some(ToggleHideCompleted) => Unhandled
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

- **`items: Array[Any]`** — the struct field is
  `items : Array[@tutuca.Value]`, holding `Item` instances built with
  `item.make(...)`. Append immutably: `s.items + [ ... ]`.
- **`@each` + `<x render-it>`** renders each instance as its own `Item`
  component (fresh frame — the item handles its own events); the remove
  button sits **beside** `render-it` in the loop, so `removeInItemsAt
  @key` dispatches to the *list*, which owns the collection.
- **`@when="onlyVisible"`** filters at render time; the `when` bucket is
  a match over a generated enum (a raw `component()` call would take
  `when={ "onlyVisible": ... }` instead). The other way to write it is to put
  the predicate on the CHILD — `pred unfinished { not .completed }` in
  `Item`'s block — and have this `when` call it on each instance with
  `value.call_field("unfinished", [])`.
- **Add / toggle / delete** show the three handler routes: an `update`
  arm (`OnAddItem`), fall-through to a generated mutator
  (`RemoveInItemsAt`, `ToggleHideCompleted`), and the checkbox mutator
  on the child.

Test it end-to-end with the harness ([testing.md](../testing.md)):

```moonbit
test "todo: add, complete, filter" {
  let h = @harness.mount(todo_module(), "Items")
  h.click(".add")
  h.click(".add")
  assert_eq(h.find_all(".row").length(), 2)
  h.check(".checkbox", true)        // complete the first item
  h.click(".toggle-done")           // toggleHideCompleted
  assert_eq(h.find_all(".row").length(), 1)
  h.click(".rm")                    // delete the visible one
  assert_eq(h.find_all(".row").length(), 0)
}
```
