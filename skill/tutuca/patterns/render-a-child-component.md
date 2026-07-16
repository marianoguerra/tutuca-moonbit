# Render a child component

**Problem:** a component holds another component in a field and wants to render
it (reaching into nested data is not allowed — `@text=".child.name"` fails).

```moonbit
fields={
  // built through the registration scope at make() time — a forward
  // reference by name, no import cycle
  "greeting": @component.FieldSpec::comp("Greeting", args={ "name": Str("world") }),
},
```

```html
<x render=".greeting"></x>           <!-- default ("main") view -->
<x render=".greeting" as="edit"></x> <!-- a named view -->
<x render=".greeting" as=".mode"></x> <!-- view chosen by a field at runtime -->
```

The child draws its own view from its own fields, so inside `Greeting`'s view
`@text=".name"` reads the child's `name`. This is the idiomatic way to display
nested structure: make the nested thing a component and render it, rather than
trying to path into it. For a list of children use `render-each` (see the
iterate-a-list recipe); to flip which view renders, see the switch-between-views
recipe. Runnable version: `examples/render_child.mbt`.
