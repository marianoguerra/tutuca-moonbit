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
starting state IS one — `<script type="tutuca/fixtures">` in the view file, read
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

Nothing else to do: a gallery projects its story set from the modules it is
given, so the example you just declared IS a story
(`@sb.stories_of_modules([foo_module(), ...])`). Its id is
`slug("<module> <component> <title>")`, its title is `"Foo · Loading"`, and its
args and view are the ones above.

What a projection cannot derive, because no `ExampleDef` field implies it, is a
`.map` over the projected list — `Story` is `pub(all)`:

```moonbit nocheck
// nocheck: `stories` is the list the reader projected from their own modules
stories.map(s => if s.id == "foo-foo-loading" { { ..s, init: true } } else { s })
```

- `init: true` for a root that loads its data on `init` (tutuca has no
  lifecycle, so the host has to be told to send one).
- `renderable: false` for a fixture that should be listed but never mounted.
- `section` / `description` for the sidebar grouping and blurb.

See [../storybook.md](../storybook.md), and
[build-a-gallery.md](build-a-gallery.md) for the whole path from a module to a
served page.
