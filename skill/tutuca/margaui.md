# Tutuca — MargaUI Styling

Reach this file to add **MargaUI** (the Tailwind v4 / daisyUI-compatible
class library) styling to a tutuca app: link its theme, and compile the
utility classes your views reference into CSS. If you only need
scoped/global component CSS, [styles.md](./styles.md) is enough.

In the MoonBit port the split is: **tutuca collects, a Tailwind v4
compiler compiles, the host injects.** The MoonBit side gathers every
literal class the compiled views can show —
`app.scope.comps.collect_classes()` (or, per compiled view,
`@anode.ANode::collect_classes`) — that class list is compiled to CSS,
and the host injects the result as `<style id="margaui-css">`.

The compile step runs **in MoonBit** via
[`marianoguerra/tailwindcss`](https://github.com/marianoguerra/tailwindcss-moonbit),
a MoonBit port of the Tailwind v4 compiler — no JS margaui package, no CDN, no
network at runtime. margaui's whole `@import` graph is snapshotted into an
embedded bundle once (the wasm demos and the in-browser playground use the same
compiler + bundle), and the host compiles the collected classes against it with
`@tw.compile_sync`. See [Compile in MoonBit](#compile-in-moonbit-what-the-demos-do).

## Get margaui

You do **not** need margaui's JS package — the compiler is the MoonBit
`marianoguerra/tailwindcss` port and the class CSS is built from an embedded
bundle (see [Compile in MoonBit](#compile-in-moonbit-what-the-demos-do)). The
light and dark theme variables are compiled into that CSS too.

The only thing you may still fetch from margaui is the **extra theme palettes**
(dracula, nord, …), which are plain CSS custom-property stylesheets with no
MoonBit equivalent. Link one lazily when the user picks it:

```html
<link rel="stylesheet" href="https://marianoguerra.github.io/margaui/themes/dracula.css" />
```

(or vendor those `.css` files for a fully offline build). Light + dark need no
link — they are in the compiled `margaui-css`.

## Dark mode and the other palettes

A margaui theme is a block of CSS custom properties (`--color-*`, `--radius-*`,
…) under a `[data-theme="<name>"]` selector, and every class it compiles reads
those through `var(--color-*)`. So switching theme is **one attribute flip on
`<html>`** — the compiled stylesheet never changes:

```js
document.documentElement.dataset.theme = "dark";
```

Two things to know, both of which bite if you assume otherwise:

- **Dark mode never turns itself on.** `dark.css` is keyed on
  `[data-theme="dark"]` alone — there is no `prefers-color-scheme` fallback and
  no `.dark` class. Link `theme.css` and do nothing else and the page is light
  forever, on every machine. Following the OS is your job:

  ```js
  const dark = matchMedia("(prefers-color-scheme: dark)");
  document.documentElement.dataset.theme = dark.matches ? "dark" : "light";
  ```

- **`theme.css` is only light + dark.** It is literally
  `@import"./light.css";@import"./dark.css";`. margaui ships ~33 more palettes
  (dracula, nord, cyberpunk, …) as sibling files, each linked separately and
  each cheap:

  ```html
  <link rel="stylesheet" href="https://marianoguerra.github.io/margaui/themes/dracula.css" />
  ```

  Link it **after** `theme.css`: `light.css` claims plain `:root` as well as
  `[data-theme=light]`, which ties on specificity with `[data-theme=dracula]`,
  so a palette only wins by coming later in the cascade.

When compiling in MoonBit (the demos), light + dark are compiled **into**
`margaui-css` (the entry imports `themes/theme.css`), so no `theme.css` link is
needed and light/dark work offline. The same cascade rule still applies to the
extra palettes: their lazily-added `<link>`s must come after `margaui-css`. The
demos guarantee that by pre-placing an empty `<style id="margaui-css">` early in
`<head>` — the compile step upserts that element in place, so it stays ahead of
any palette link appended later.

## Compile in MoonBit (what the demos do)

The wasm demos (`demo/storybook_wasm`, `demo/universal_wasm`) compile margaui
**in MoonBit** via `marianoguerra/tailwindcss`, so there is no CDN import and
styling works offline. The moving parts, all in-repo:

- **The bundle.** `cmd/margaui-bundle` (a dev tool) runs the tailwindcss
  `bundle` graph walk (`@tw.collect_imports`) over an adapted margaui entry
  (`demo/assets/margaui.entry.css`) and emits `demo/margaui/bundle_gen.mbt` — the
  `@import` map as an embedded `Array[(String, String)]`, plus the entry string.
  Regenerate against a margaui checkout (default `../margaui`) with:

  ```sh
  moon run --target native cmd/dev -- margaui-bundle
  ```

- **The compile helper.** `demo/margaui`'s
  `compile_classes(classes) -> String` builds a `MemoryStylesheetLoader` from the
  embedded bundle and calls `@tw.compile_sync(margaui_entry, …).build(classes)`
  (`compile_sync` is the wasm-gc-safe path — no async runtime).

- **The host.** After `mount()`, the host compiles + injects in one step:

  ```moonbit
  let css = @margaui.compile_classes(app.scope.comps.collect_classes())
  @wglue.inject_style(doc, "margaui-css", css)   // app/wasm inject_style
  ```

  and re-runs it from the exported `refresh_margaui()` after a dyncomp bundle
  registers new classes. No `globalThis.__tutuca_classes`, no page-side compile.

The adapted entry differs from margaui's own `entry.css` in two ways: the bare
`@import "tailwindcss"` is inlined as tailwindcss.css's four `@layer`/`@import`
lines (its nested `./tw/*` paths are margaui-root-relative and resolve wrong
otherwise), and the scan-only `@source` line is dropped (candidates come from
`collect_classes()`, not content scanning). To adopt this in your own app,
add the `marianoguerra/tailwindcss` dep, generate a bundle the same way, and
call `compile_sync` after mount.

## Wire it into tutuca

The integration is three steps, all on the MoonBit side: after mounting,
**collect** the class set, **compile** it, **inject** the CSS.

**wasm-gc target** (the `demo/*_wasm` pattern): `mount()` compiles + injects in
MoonBit; the page only pre-places an empty `<style id="margaui-css">` in
`<head>` (so injection keeps a stable, early cascade position — palette links
appended later still win) and calls `exports.mount()`:

```moonbit
// in the host's mount(), after the app is built:
let css = @margaui.compile_classes(app.scope.comps.collect_classes())
@wglue.inject_style(doc, "margaui-css", css) // app/wasm inject_style upserts by id
```

Export a `refresh_margaui()` that re-runs the same two lines, and call it from
the loader after a dyncomp bundle registers new classes.

**js target**: same shape with `app/browser`'s `@glue.inject_style`. If the
compile must run in the page instead of the module (e.g. the in-browser
playground, which mounts freshly-compiled user code in an iframe), ship the
compiler to js as a small executable that publishes a compile function — see
`playground/margaui_js` (published as `globalThis.__tutucaMargaui`) and its use
in `playground/web/runtime.js`. Either way there is no JS margaui package, no
CDN import, and no `globalThis` class hand-off between MoonBit and the page.

## Pitfall: assembled class names are invisible to the scanner

`collect_classes` only reads **constant** class literals out of compiled
templates. It cannot see a class name that is assembled rather than
written out verbatim, so the margaui CSS for that class is never emitted
and it renders unstyled. Two cases:

- **Interpolated templates** — `:class="$'bg-{.color}'"` contributes only the
  constant prefix `bg-`, never `bg-red` / `bg-blue`. Same for any `{…}` segment.
- **Classes built in a handler** — anything a `compute` entry returns
  (e.g. a `headerClass` that builds `"progress-" + color`) is never
  scanned at all; the collector only reads view templates, not MoonBit
  bodies.

(Literal `@then` / `@else` strings on `@if.class` — e.g.
`@if.class=".active" @then="'btn-success'" @else="'btn-ghost'"` — **are**
collected, so those don't need the workaround.)

Workaround: add a hidden "decoy"/palette view on the component that lists every
possible assembled class as a real literal, so the collector picks them up:

```moonbit
views={
  // enumerate color × utility so each full class name appears verbatim;
  // never rendered — registration is enough for the collector to see it
  "_margauiClasses": "<p class=\"bg-red bg-blue progress-red progress-blue\"></p>",
},
```

`storybook/examples/personal_site.mbt` has the worked version: its
`_margauiClasses` view interpolates a **MoonBit** helper
(`ps_category_decoy_classes()`) into the view **string at construction
time**, so the color tables stay the single source of truth while the
template still carries literals. The cost is that the palette and the
compute entries can drift apart with no check catching it; keep them adjacent and
update both together. (This is the same rule
[component-design.md](./component-design.md) gives for runtime-assembled
margaui classes.)

## When authoring class lists

Write margaui/Tailwind classes as **literal lists** in `class=` /
`:class` so the collector sees them. Load the margaui skill alongside
this one if available (`tutuca install-skill --margaui-skill`) — it
lists the available components and their canonical class strings, which
is what the `compile` step expects.

## See also

- [styles.md](./styles.md) — scoped/global component CSS.
- [advanced.md](./advanced.md) — dynamic bindings, drag & drop, and other
  advanced view features.
- [cli.md](./cli.md) — `install-skill --margaui-skill` installs the
  margaui skill.
