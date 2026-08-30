# Tutuca — The Storybook Gallery

Read this file to give a project a gallery of its own components: a sidebar of
stories, a live pane for each, and per-story Instance, Trace, Fuzz, Spec and Raw
inspectors. The gallery is a library — a project supplies modules, not a shell.

The one idea it is built on: **a story is an example on a `ModuleDef`.** The
story set is a projection of your own modules, so adding a story is adding an
example where the component lives, and the same example is what
`@harness.mount_example` mounts in a test. There is no list to keep in step.

## Scaffold

```sh
tutuca new-storybook my-gallery
cd my-gallery
node build.mjs           # moon build --target wasm-gc --release page → dist/
tutuca storybook dist    # or any static server over dist/
```

That writes the only part a library cannot supply: a page package with the
wasm-gc `link.exports` list (per-package `link` configuration cannot come from a
dependency), an `index.html`, and a `build.mjs` that assembles `dist/`.

## Declaring stories

```moonbit nocheck
// nocheck: `counter_component` is the reader's own generated component
pub fn counter_module() -> @component.ModuleDef {
  @component.ModuleDef::new(name="counter", components=[counter_component()], examples=[
    { component: "Counter", title: "Zero", args: Map([]), view: None },
    { component: "Counter", title: "Seeded", args: { "count": Num(7) }, view: None },
    // `view` picks one of the component's named views (`<template
    // id="Counter:compact">`) instead of its default
    { component: "Counter", title: "Compact", args: Map([]), view: Some("compact") },
  ])
}
```

Then project them:

```moonbit nocheck
// nocheck: the modules are the reader's
fn sections() -> Array[@sb.Section] {
  let stories = @sb.stories_of_modules(
    [counter_module(), todo_module()],
    section_of=m => match m.name {
      "counter" => "Basics"
      _ => "Data"
    },
  )
  @sb.sections_of(stories, order=["Basics", "Data"])
}
```

| Call | Gives |
| --- | --- |
| `@sb.stories_of_module(m, section?)` | one `Story` per example the module declares, ids unique within it |
| `@sb.stories_of_modules(ms, section_of?)` | the same across modules, ids unique across the set |
| `@sb.Story::of_example(m, ex, ...)` | one story, when you want to pick |
| `@sb.sections_of(stories, order?)` | grouped for the sidebar; unlisted sections are appended, never dropped |
| `@sb.Story::new(...)` | a hand-written story, for a component that declares no examples |

Derived per story: `id` is `slug("<module> <component> <title>")`; `title` is
`"Component · Title"`, or the bare component name when the example is untitled;
`root`, `args` and `view` come from the `ExampleDef`.

## Overriding what cannot be derived

`Story` is `pub(all)`, so overrides are a `.map` with a record update:

```moonbit nocheck
// nocheck: `stories` is the projected list from above
stories.map(s => if s.id == "todo-todo-remote" { { ..s, init: true } } else { s })
```

- **`init: true`** — the host dispatches `init` into the pane after mount, for a
  root that loads its data that way. Tutuca has no lifecycle and no `ExampleDef`
  field implies this, so nothing infers it.
- **`renderable: false`** — listed in the sidebar, never mounted. For a fixture
  whose view is deliberately malformed.
- **`section` / `description`** — sidebar grouping and the blurb under the title.

## Mounting

```moonbit nocheck
// nocheck: `sections()` and the page's own intents are the reader's
pub fn mount() -> Unit {
  let sections = sections()
  @sbw.mount(
    sections,
    themes=["light", "dark"],           // the palettes the switcher offers
    panels=@panelsw.all(sections),      // the tabs; omit for stories only
    intents={ "loadData": [...] },      // the page's own services
  ) |> ignore
}
```

`@sbw` is `storybook/ui/wasm` — the browser host: it mounts the gallery, owns
the URL and theme services (`?story=&filter=&focus=&theme=`), bridges DOM
events, and compiles and injects the margaui sheet. `@sbui` is `storybook/ui`,
the backend-agnostic shell underneath; `@sbui.mount` is what a headless test
drives on the in-memory DOM. `@panelsw` is `storybook/ui/panels/wasm` — the
standard tabs plus the browser effects they need.

## The tabs

| Tab | Shows | Needs |
| --- | --- | --- |
| Story | the live instance | — |
| Instance | its fields, live, and its component's definition | — |
| Trace | a recording of what the app did: cut to one component by clicking it, downloaded as `.trace.jsonl`, loaded back, and replayed into the story | — |
| Fuzz | generated dispatches driven at the instance on screen, with shrinking | a `<script type="tutuca/spec">` block on the component |
| Spec / Raw | that block, parsed and verbatim | the same |

Panels are opt-in, and that is a linking decision rather than a taste one:
`storybook/ui` and `storybook/ui/wasm` import no panel layer, so a page that
never names `@panelsw.all(sections)` carries no inspector, no recorder and no
fuzz driver — 1.25 MB of wasm against 3.1 MB with them (`--release`, before
wasm-opt).

A tab is a `PanelDef`: a key, a label, a per-story field prefix, a closure that
builds its value from the story's instance, and three flags (`live` — rebuild
while the story changes; `keep` — survive leaving the tab; `with_story` — draw
the story above it). A `PanelSet` bundles those with the fields they own, the
components they are drawn with, the intents they answer, and the `attach` the
shell calls with the mounted app. Writing your own tab is writing one of those.

## Testing a gallery

`@sbui.mount` runs on `@memdom`, so a gallery is testable like anything else:

```moonbit nocheck
// nocheck: `sections()` is the reader's
test "the gallery mounts every story" {
  let doc = @memdom.document()
  let container = @vdom.DomNode::create_element(doc, "DIV", None, None)
  let _app = @sbui.mount(sections(), container, @vdom.RenderOpts::new(doc))
  assert_true(container.to_html().contains("data-cid"))
}
```

## Two failures worth knowing

- **A blank pane.** `Story.root` is looked up by name in the story's own scope;
  a name that resolves to nothing renders as nothing. `mount` warns through
  `@tutuca.warn` — read the console before hunting through the view.
- **A blank slot inside a live story.** An arg holding a component instance only
  renders if it was made from the very `Component` the story's module
  registers. Projected stories cannot get this wrong (an `ExampleDef`'s args are
  built inside that module); a hand-written `Story` can, and `mount` warns.
