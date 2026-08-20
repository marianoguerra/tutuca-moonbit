# Render a child component

**Problem:** a component holds another component in a field and wants to render
it (reaching into nested data is not allowed — `@text=".child.name"` fails).

Declare the field with the child's interface name — that makes it a **slot**:

```html
<script type="tutuca/state">
  state Card { mode: String, greeting: Greeting }
    state Greeting { name: String }
</script>

<template id="Card">
  <x render=".greeting"></x>            <!-- default ("main") view -->
  <x render=".greeting" as="edit"></x>  <!-- a named view -->
  <x render=".greeting" as=".mode"></x> <!-- view chosen by a field at runtime -->
</template>

<template id="Greeting">
  <p @text=".name"></p>
</template>
<template id="Greeting:edit">
  <input class="input" :value=".name" @on.input="setName e.value" />
</template>
```

The slot is filled through the **registration scope** at `make()` time — a
forward reference by name, so no import cycle. The one thing the schema cannot
state is what the child is built *with*, which is `slot_args~`:

```moonbit
///|
fn card_comp() -> @component.Component {
  card_component(slot_args={ "greeting": { "name": Str("world") } })
}
```

That call is wiring, not behaviour — the schema already declared the slot;
`slot_args~` only says what the child is built with, which is the one thing no
type states.

The child draws its own view from its own fields, so inside `Greeting`'s view
`@text=".name"` reads the child's `name`. This is the idiomatic way to display
nested structure: make the nested thing a component and render it, rather than
trying to path into it. Every component needs a `main` view, even one you only
render `as="edit"`.

For a list of children use `render-each` ([Iterate a
list](iterate-a-list.md)); to flip which view renders, see [Switch between
views](switch-between-views.md). Slot spellings — a sibling interface, bare
`component`, or a `resource` from another module — are in
[schema.md](../schema.md#slots).
