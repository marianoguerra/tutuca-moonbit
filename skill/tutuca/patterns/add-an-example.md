# Add an example for a component

**Problem:** show a component (and its states) so `tutuca render`, the
harness tests, and the demo hosts can all mount it.

Add `ExampleDef`s to the module's `ModuleDef`:

```moonbit
pub fn foo_module() -> @component.ModuleDef {
  let foo = foo_comp()
  @component.ModuleDef::new(name="foo", components=[foo], examples=[
    { component: "Foo", title: "Empty", args: {}, view: None },
    {
      component: "Foo",
      title: "Loading",
      args: { "isLoading": Bool(true) },
      view: None, // or Some("edit") to render a named view
    },
  ])
}
```

`args` is a `Map[String, Value]` seeding the root instance; a
component-typed slot must hold a real instance —
`item.make({...})` (which returns the instance as a `Value`), not a
bare `Map`. To show request-driven
states, parameterize the module with `requests?` and build the example's
module with a fixture (`respond(Ok(...))` / `respond(Err(...))` / never
respond to hold a loading state) — the pattern in `storybook/examples/request.mbt`.

The same example is then reachable three ways: `tutuca render --title
"Loading"` (embedded CLI), `@harness.mount_example(foo_module(),
"Loading")` (tests), and a demo host page mounting the module. If a demo
host keeps a catalog (like `demo/examples`), register the module in its
example list.
