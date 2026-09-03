# storybook-gallery

**A consumer example.** This directory is what `tutuca new-storybook` writes,
committed unedited (bar the module name and this note), and it depends on the
PUBLISHED `marianoguerra/tutuca`. It exists to answer what `moon check` in the
tutuca repo cannot: whether the storybook packages survived `moon publish`,
whether `app/wasm/loader.mjs` is where `build.mjs` looks for it, and whether the
tree the scaffolder emits actually builds. Run it after a release, before
announcing one.

A storybook gallery of this project's tutuca components: a sidebar of stories,
a live pane for each, and per-story Instance, Trace, Fuzz, Spec and Raw
inspectors.

## Build and serve

```sh
node build.mjs        # moon build --target wasm-gc --release page, then dist/
tutuca storybook dist # or any static server over dist/
```

Needs `moon` and Node >= 20, and a browser with the JS String Builtins proposal
(Chrome/Edge). The first build fetches `marianoguerra/tutuca` from mooncakes.

## Adding a story

A story is an **example on a `ModuleDef`**, not an entry in a list:

```moonbit
pub fn counter_module() -> @component.ModuleDef {
  @component.ModuleDef::new(name="counter", components=[counter_component()], examples=[
    { component: "Counter", title: "Zero", args: Map([]), view: None },
    { component: "Counter", title: "Seeded", args: { "count": Num(7) }, view: None },
  ])
}
```

`page/main.mbt` projects those into stories with
`@sb.stories_of_modules([...])`. Add a module to that call and every example it
declares shows up. The same examples are what `@harness.mount_example` mounts in
a test, so a story and a test cannot disagree.

Overrides are ordinary `.map`s over the projected list — `Story` is `pub(all)`:

```moonbit
stories.map(s => if s.id == "counter-counter-seeded" { { ..s, init: true } } else { s })
```

- `init: true` — the host dispatches `init` into the pane after mount, for a
  story whose root loads its data that way. Tutuca has no lifecycle, so nothing
  infers this.
- `renderable: false` — listed in the sidebar, never mounted. For a fixture
  whose view is deliberately malformed.
- `section` / `description` — sidebar grouping and the blurb under the title.

## Adding a component

Write the view file, then generate its MoonBit module:

```sh
tutuca gen page/my_thing.html
```

The generated `page/my_thing_view_gen.mbt` is checked in and never hand-edited;
`tutuca watch page/` regenerates on save. Then build a `ModuleDef` around
`my_thing_component()` and add it to `sections()` in `page/main.mbt`.

## What each file is

| File | |
| --- | --- |
| `page/main.mbt` | the story set and the five wasm entry points |
| `page/counter.html` | a demo component's views + spec + script |
| `page/counter_view_gen.mbt` | generated from it — regenerate, never edit |
| `page/moon.pkg` | the executable's `link.exports` list |
| `index.html` | the page: the margaui `<style>` slot, `#app`, the loader |
| `build.mjs` | wasm build, wasm-opt, and the JS the page needs beside it |

The gallery itself is `marianoguerra/tutuca/storybook/ui/wasm`. This project is
the executable around it, because a wasm-gc export list is per-package `link`
configuration and cannot come from a dependency.

## Options

`@sbw.mount` takes more than the sections:

```moonbit
let sections = sections()
@sbw.mount(
  sections,
  themes=["light", "dark"],        // the palettes the switcher offers
  panels=@panelsw.all(sections),   // the tabs — drop it for stories only
) |> ignore
```

The tabs are opt-in because they are what most of the wasm IS: dropping the
`panels~` argument and the `@panelsw` import takes the page from ~3.1 MB to
~1.25 MB (`--release`, before wasm-opt).
