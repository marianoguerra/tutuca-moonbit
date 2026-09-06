# Switch between views

**Problem:** render the *same* component in a different view (e.g. a read-only
"main" vs an "edit" form).

A named view is a `Comp.name:` in `view:` in the view file; `main` is the
one with no suffix.

```tutu
spec:
  Note:
    field title :: String
    field view :: String
    field items :: List.of(Any)

logic:
  Note:
    /// Flip the pushed view name. One string field is the whole switch.
    receive toggle_view:
      it.view := if (it.view == "main") | "edit" | "main"

view:
  Note:
    @div{@p{@(it.title)} @button(~on_click: toggle_view){flip} @comment{ ~as: picks the view for one @render only } @each(value, key in it.items){@render(value)} @each(value, key in it.items){@render(value, ~as: "edit")} @each(value, key in it.items){@render(value, ~as: it.view)} @comment{ view chosen by a field at runtime } @comment{@" ~push_view forces a view on every component rendered under the host "} @div(~push_view: it.view){@each(value, key in it.items){@render(value)}}}

  Note.edit:
    @input(~value: it.title, ~on_input: it.title := e.value)
```

Nothing else is needed: the generated wrapper passes both views, and `if` in a
value position (both arms required — an expression has to have a value) is
enough to write the flip.

`as` applies to the direct component only and falls back to `main` if the view
is absent. It takes the same value forms as `~push_view` — a literal name
(`~as: "edit"`) or a dynamic value (`~as: it.view`, `dyn.<name>`, `~bind`, `handler()`,
`@str{…}`), evaluated against the host component at render time (for `@each(…){@render(value)}`,
once for all items). `~push_view` instead pushes a view name onto the render
stack so every descendant picks the first matching view (else `main`) — use it
to flip a whole subtree (e.g. a list) into edit mode at once. To toggle
*sibling panels* by a field instead, see the tabbed-interface recipe.
