# Switch between views

**Problem:** render the *same* component in a different view (e.g. a read-only
"main" vs an "edit" form).

A named view is a `<template id="Comp:name">` in the view file; `main` is the
one with no suffix.

```html
<script type="tutuca/spec">
  state Note { title: String, view: String, items: Array[Any] }
</script>

<script type="tutuca/script" for="Note">
  /// Flip the pushed view name. One string field is the whole switch.
  receive toggleView { .view = if .view is 'main' { 'edit' } else { 'main' } }
</script>

<template id="Note">
  <div>
    <p @text=".title"></p>
    <button @on.click="toggleView">flip</button>

    <!-- as= picks the view for one <x render> element only -->
    <x render-each=".items"></x>
    <x render-each=".items" as="edit"></x>
    <x render-each=".items" as=".view"></x>   <!-- view chosen by a field at runtime -->

    <!-- @push-view forces a view on every component rendered under the host -->
    <div @push-view=".view"><x render-each=".items"></x></div>
  </div>
</template>

<template id="Note:edit">
  <input :value=".title" @on.input="setTitle e.value">
</template>
```

Nothing else is needed: the generated wrapper passes both views, and `if` in a
value position (both arms required — an expression has to have a value) is
enough to write the flip.

`as` applies to the direct component only and falls back to `main` if the view
is absent. It takes the same value forms as `@push-view` — a literal name
(`as="edit"`) or a dynamic value (`as=".view"`, `*dyn`, `@bind`, `$handler`,
`$'…'`), evaluated against the host component at render time (for `render-each`,
once for all items). `@push-view` instead pushes a view name onto the render
stack so every descendant picks the first matching view (else `main`) — use it
to flip a whole subtree (e.g. a list) into edit mode at once. To toggle
*sibling panels* by a field instead, see the tabbed-interface recipe.
