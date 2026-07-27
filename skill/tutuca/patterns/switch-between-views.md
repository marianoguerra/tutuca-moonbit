# Switch between views

**Problem:** render the *same* component in a different view (e.g. a read-only
"main" vs an "edit" form).

A named view is a `<template id="Comp:name">` in the view file; `main` is the
one with no suffix.

```html
<script type="tutuca/state">
  interface note { record state { title: string } }
</script>

<template id="Note"><p @text=".title"></p></template>
<template id="Note:edit">
  <input :value=".title" @on.input="setTitle value">
</template>
```

```moonbit nocheck
note_component() // the generated wrapper passes both views
```

```html
<!-- as= picks the view for one <x render> element only -->
<x render=".value"></x>
<x render=".value" as="edit"></x>
<x render=".value" as=".mode"></x>   <!-- view chosen by a field at runtime -->

<!-- @push-view forces a view on every component rendered under the host -->
<div @push-view=".view"><x render-each=".items"></x></div>
```

`as` applies to the direct component only and falls back to `main` if the view
is absent. It takes the same value forms as `@push-view` — a literal name
(`as="edit"`) or a dynamic value (`as=".mode"`, `*dyn`, `@bind`, `$handler`,
`$'…'`), evaluated against the host component at render time (for `render-each`,
once for all items). `@push-view` instead pushes a view name onto the render
stack so every descendant picks the first matching view (else `main`) — use it
to flip a whole subtree (e.g. a list) into edit mode at once. To toggle
*sibling panels* by a field instead, see the tabbed-interface recipe.
