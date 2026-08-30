# The storybook, as a library

The gallery in `storybook/` is not this repo's private tooling: it ships, and a
project that depends on `marianoguerra/tutuca` can build one over its own
components. This document is how, and why it is shaped the way it is.

| Package | What it is | Ships |
| --- | --- | --- |
| `storybook` | the model: `Story`, `Section`, `sections_of`, and the projection (`stories_of_module`, `stories_of_modules`) | yes |
| `storybook/ui` | the gallery shell: sidebar, filter, focus mode, per-story panes and the tab strip. Knows what a panel IS — a key, a label, a field prefix and a closure — and nothing about what one contains. Backend-agnostic — `moon test` drives it on the in-memory DOM | yes |
| `storybook/ui/panels` | what they contain: the value explorer, the recorder, the fuzz driver, the spec views, and the host sessions behind them | yes |
| `storybook/ui/wasm` | the browser host: URL and theme services, the DOM event bridge, the compiled margaui sheet. Imports no panel layer | yes |
| `storybook/ui/panels/wasm` | the panels' browser half: the animation frame, the profiler marks, the click a Trace pick consumes | yes |
| `storybook/inspector` | the components the panels are drawn with | yes |
| `storybook/examples` | **this repo's own 52 stories** and the fixtures the lint and view sweeps run over | no |
| `demo/storybook_wasm` | this repo's page: an export list and a story set | no |

The line between the last two rows and the rest is the whole design. A gallery
is a library; a *story set* is editorial content about one project's components,
and there is no reason for anyone else to carry ours.

## Three doors to a story set

**The projection**, and the one to reach for:

```moonbit
@sb.stories_of_modules([counter_module(), todo_module()], section_of=m => match m.name {
  "counter" => "Basics"
  _ => "Data"
})
```

One story per `ExampleDef` the module declares. A `ModuleDef` already names its
components and the args each example seeds them with — that is a story minus the
editorial part — so nothing is restated and nothing can fall out of step. The
same examples are what `@harness.mount_example` mounts in a test.

**One module**: `@sb.stories_of_module(m, section?)`.

**By hand**: `@sb.Story::new(id~, title~, module_~, root~, ...)`, for a component
that declares no examples. Use it knowing the hazard the other two doors close:
a `Component` value carries an id bound to the scope it was registered in, so an
arg holding a **child component instance** renders only if it was made from the
very `Component` the story's module registers. An `ExampleDef`'s args are built
inside that module and cannot get this wrong. A hand-written `Story` can, and
the symptom is a blank slot inside an otherwise live story — so `mount` warns
through `@tutuca.warn` rather than leaving you to find it.

### What the projection derives, and what it cannot

| Field | From |
| --- | --- |
| `id` | `slug("<module> <component> <title>")`, suffixed `-2`, `-3` on a collision |
| `title` | `"Component · Title"`, or the component name when the example is untitled |
| `root`, `args`, `view` | the `ExampleDef` |
| `section` | the `section~` / `section_of~` argument |
| `description`, `init`, `renderable` | nothing — no `ExampleDef` field implies them |

`Story` is `pub(all)`, so the last row is a `.map` with a record update:

```moonbit
stories.map(s => if s.id == "todo-todo-remote" { { ..s, init: true } } else { s })
```

`init` in particular is not guessed. Tutuca has no lifecycle; a story whose root
loads its data on `init` needs the host to send one, and a gallery that
dispatched messages nobody asked for would be worse than one that needs a line.

## The page

```moonbit
pub fn mount() -> Unit {
  let sections = sections()
  @sbw.mount(
    sections,
    themes=["light", "dark"],
    panels=@panelsw.all(sections),   // the standard tabs; omit for stories only
  )
  |> ignore
}
```

`storybook/ui/wasm` is a library, not a page. A project still writes an
executable package that re-exports five entry points — `mount`, `on_event`,
`on_popstate`, `on_fuzz_tick`, `refresh_margaui` — because a wasm-gc export list
is per-package `link` configuration and cannot come from a dependency. It also
writes an `index.html` and a build script. All three are scaffolded:

```sh
tutuca new-storybook my-gallery
cd my-gallery && node build.mjs && tutuca storybook dist
```

`tutuca storybook` is a static file server and knows nothing about any of this:
a bundle is a directory with an `index.html` and a `.wasm` beside it.

## Options

- **`themes~`** — the palettes the switcher offers, `margaui_themes()` by
  default (35 names). `storybook/ui` imports no margaui: the list is data, and
  the stylesheets are fetched from `theme_base_url~` on first selection.
- **`panels~`** — the tabs beside Story, as a `PanelSet`. The default is none,
  and that is a **linking** decision: `storybook/ui` and `storybook/ui/wasm`
  import no panel layer, so a page that never names `@panelsw.all(sections)`
  carries no inspector, no recorder and no fuzz driver in its wasm. On the
  scaffolded gallery that is 3.1 MB with the panels and 1.25 MB without
  (`--release`, before wasm-opt).

  A `PanelDef` is a key, a label, a field prefix, a build closure and three
  flags (`live`, `keep`, `with_story`); a `PanelSet` adds the gallery-wide
  fields the panels own, the components their values are instances of, the
  intents they answer, and an `attach` the shell calls with the mounted app.
  That is the whole contract, so a project can write its own tab — a diff
  against a golden render, a props table — without touching the shell.
- **`intents~`** (wasm host only) — the page's own request handlers, merged
  after the gallery's URL services on the walking LEX leg.

## What the gallery imposes

Its chrome is written in margaui/Tailwind utility classes (`btn btn-ghost`,
`tabs tabs-sm`, `bg-base-100`, …), and the wasm host compiles the collected
class set in MoonBit and injects it — no CDN, works out of the box. The price is
that the gallery brings margaui to the page. `themes~` and `theme_base_url~`
soften that; restyling the chrome itself is not currently a seam.

## Testing a gallery

`@sbui.mount` is generic over `@vdom.DomWalk`, so the whole thing runs on
`@memdom` under `moon test` — which is how `storybook/ui`'s own tests and this
repo's corpus test (`storybook/examples/gallery_test.mbt`) drive it, tabs,
trace, fuzz and all.

## Why `storybook/examples` stays behind

Not because it is unfinished, but because it is *ours*: 52 demos with a curated
`name -> section` table and a `name -> (title, description)` table, plus the
fixture set the `gen-views` sweep and `benchmarks` run over. A consumer needs
none of it, and the projection means nobody has to borrow a story set to get a
gallery.

The rule that keeps the split honest is `scripts/check-publish-graph.mjs` in
`ci`: no shipping package may import an excluded one — in a `for "test"` block
either, since test files travel in the tarball too.
