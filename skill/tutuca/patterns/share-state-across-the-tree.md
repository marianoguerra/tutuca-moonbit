# Share state across the tree

**Problem:** a deep descendant needs a value owned by a distant ancestor, and
you don't want to thread it through every component in between.

> **Reach for this last.** Keep state local to the component and use
> `provide` / `lookup` only when it is genuinely the only solution — a value
> owned far away that a deep descendant needs and nothing in between should
> know about. Dynamic bindings couple a consumer to a producer that may not be
> in scope, so keep components as self-contained as possible: let a child
> render the field it needs from its owner, and lift state only as far up the
> tree as it needs to live.

`entries.html`:

```html
<script type="tutuca/state">
  state Editor { entries: Array[Any], picker: Selector }
    state Selector {  }
</script>

<template id="Editor">
  <div>
    <x render=".picker"></x>
  </div>
</template>

<template id="Selector">
  <select class="select">
    <option @each="*entries" :value="@value.value" @text="@value.label"></option>
  </select>
</template>
```

`entries.mbt`:

```moonbit
///|
/// The producer publishes one of its fields under an exported name.
fn editor_comp() -> @component.Component {
  editor_component(provide={ "entries": ".entries" })
}

///|
/// The consumer resolves it by "Component.name", with a fallback expression for
/// when no producer is in scope.
fn selector_comp() -> @component.Component {
  selector_component(lookup={
    "entries": { source: "Editor.entries", default: Some("[]") },
  })
}
```

`provide` / `lookup` are **wiring, not behaviour**: they say where a value
comes from, which is a fact about how this component was registered rather than
about what it does, so they are `component()` arguments and the script block has
nothing to say about them.

`provide` publishes a field under a name; a descendant's `lookup` resolves
`*name` to the nearest matching producer, falling back to the `default`
expression when none is in scope (`None` → `null`). `*name` works wherever a
`.field` does, iteration and render targets included.

A `provide` expression must be **addressable** (`.field` or `.seq[.key]`), and a
bad one is dropped **silently** — if `*name` reads as its fallback everywhere,
suspect the producer's expression. This is the **read** side; to edit the
producer's value through the dynamic, see
[Edit through a dynamic target](edit-through-a-dynamic-target.md).
