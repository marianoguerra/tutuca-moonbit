# Switch between views

**Problem:** render the *same* component in a different view (e.g. a read-only
"main" vs an "edit" form).

```moonbit
priv struct NoteState {
  title : String
} derive(ToJson, FromJson)

@component.component(
  views={
    "main": @anode.View::new("main", raw_view="<p @text=\".title\"></p>"),
    "edit": @anode.View::new("edit", raw_view="<input :value=\".title\" @on.input=\"$setTitle value\" />"),
  },
  name="Note",
  init=NoteState::{ title: "" },
)
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
