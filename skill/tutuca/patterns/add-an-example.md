# Add an example for a component

**Problem:** show a component (and its states) so the harness tests, the
storybook and the demo hosts can all mount it.

Add `ExampleDef`s to the module's `ModuleDef`:

```moonbit nocheck
// nocheck: `foo_comp` is the reader's own component
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

An example is MoonBit because a `ModuleDef` is assembly: it names the
components a module registers and the arguments an example seeds them with,
neither of which is a fact any one component's block could state. (A plain
starting state IS one — `<script type="tutuca/init">` in the view file, read
back as `<Comp>State::fresh()` / `<comp>_init_args("fresh")`.)

`args` is a `Map[String, Value]` seeding the root instance; a
component-typed slot must hold a real instance —
`item.make({...})` (which returns the instance as a `Value`), not a
bare `Map`. To show intent-driven
states, parameterize the module with `intents?` and build the example's
module with a fixture (`answer(Ok(...))` / `answer(Failed(...))` /
`answer(Pass)` / never answer at all to hold a loading state) — see
*The ModuleDef convention* in
[core.md](../core.md).

The same example is then reachable two ways: `@harness.mount_example(
foo_module(), "Loading")` in a test, and the storybook / a demo host page
mounting the module.

## Landing it in the gallery

A gallery built from a compiled registry has more steps, and skipping any of them
is **silent** rather than broken — the example appears, just unlabeled or in the
wrong place:

1. **Register the module** in the registry the gallery reads.
2. **Give its name a section.** Sidebar grouping is a curated
   `name -> section` map, not derived from the module.
   An unlisted name falls into **"Other"**, appended last. A section you add
   that is not in `section_order` still renders, but after all the ordered ones.
3. **Give it a title and description**, in the same file's `name -> (title,
   description)` map. Unlisted, the story's title falls back to the raw
   registry name and its description to the empty string.

All three are display metadata: nothing about the component or its tests depends
on them.
