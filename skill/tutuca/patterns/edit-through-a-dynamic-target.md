# Edit through a dynamic target

**Problem:** render a value owned by a distant ancestor *and* let edits made in
the child land back on the owner — without forwarding events up by hand.

`workspace.html` — one view file, so one generated module for all three:

```html
<script type="tutuca/spec">
  state Workspace { sheet: Sheet, bar: Toolbar }
    state Sheet { text: String }
    state Toolbar {  }
</script>

<template id="Workspace">
  <div>
    <x render=".bar"></x>
  </div>
</template>

<template id="Sheet">
  <p @text=".text"></p>
</template>
<template id="Sheet:edit">
  <input class="input" :value=".text" @on.input="setText e.value" />
</template>

<template id="Toolbar">
  <x render="*active" as="edit"></x>
</template>
```

`workspace.mbt`:

```moonbit
///|
/// The producer exposes one of its fields as a dynamic. `provide` values must be
/// addressable, so a seq-access works too: `".items[.selectedKey]"`.
fn workspace_comp() -> @component.Component {
  workspace_component(provide={ "sheet": ".sheet" })
}

///|
/// A distant consumer names what it wants; the producer is found by scope.
fn toolbar_comp() -> @component.Component {
  toolbar_component(lookup=[@component.lookup_name("sheet")])
}
```

Both calls are wiring — where a value comes from, not what a component does —
so they are `component()` arguments and no script block states them.

Because `*active` resolves to a real **path** (not a copied value), the event
fired by the `setText` input inside the rendered child is *teleported*: the
mutation skips the intermediate components and lands on `Workspace.sheet`, so the
owner and any other view of the same value update in lock-step. A `provide` can
point at a seq-access (`.items[.selectedKey]`) to expose "the selected item".

Every component needs a `main` view even when you only ever render it `as="edit"`
— `gen-views` refuses a component without one. This is the **edit** counterpart
of [Share state across the tree](share-state-across-the-tree.md); the full
`provide`/`lookup` reference is in [advanced.md](../advanced.md#dynamic-bindings).
