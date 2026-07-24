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

There are two ways to run the compile step:

- **In MoonBit (offline, no CDN) — what the wasm demos do.** The
  [`marianoguerra/tailwindcss`](https://github.com/marianoguerra/tailwindcss-moonbit)
  package is a MoonBit port of the Tailwind v4 compiler. margaui's whole
  `@import` graph is snapshotted into an embedded bundle once, and the host
  compiles the collected classes against it with `@tw.compile_sync`. See
  [Compile in MoonBit](#compile-in-moonbit-what-the-demos-do) below.
- **In JS (quick start) — margaui's own `compile`.** The page imports
  margaui's `compile` (class names → CSS) from a CDN or a vendored copy and
  injects the result. Lightest to wire up; needs the network (or vendored
  files) at runtime. Described under [Get margaui](#get-margaui).

## Get margaui

margaui ships two pieces: a `compile` function (class names → CSS text)
and a `theme.css` stylesheet — both consumed by the **host page's JS**,
not by MoonBit code.

### CDN (no install)

```html
<link
  rel="stylesheet"
  href="https://marianoguerra.github.io/margaui/themes/theme.css"
/>
```

and in the page's module script,
`import { compile } from "https://cdn.jsdelivr.net/npm/margaui/+esm"`
(full wiring below).

### Vendoring

Copy a prebuilt `margaui.min.js` and a `theme.css` into the project and
import from the local path — useful for offline builds or pinning an
exact version:

```html
<link rel="stylesheet" href="./vendor/theme.css" />
<script type="module">
  import { compile } from "./vendor/margaui.min.js";
  // …
</script>
```

Trade-off: no runtime network dependency and a frozen version, at the
cost of updating the vendored files by hand.

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

Whatever the backend, the integration is the same three steps: after
mounting, **collect** the class set on the MoonBit side, **compile** it
with margaui on the JS side, **inject** the CSS.

**js target** (the `demo/examples` pattern): the MoonBit `main` publishes
the class list on `globalThis` through a tiny FFI, and the page's module
script compiles + injects:

```moonbit
///|
extern "js" fn publish_classes_ffi(classes : String) -> Unit =
  #|(s) => { globalThis.__tutuca_classes = s ? s.split(" ") : [] }

// in main, after App::from_module / @glue.install / install_styles:
publish_classes_ffi(app.scope.comps.collect_classes().join(" "))
```

```html
<script src="…/your_host.js"></script>
<script type="module">
  // the classic script above ran main() and published the class set
  // (module scripts are deferred, so ordering is guaranteed)
  const classes = globalThis.__tutuca_classes ?? [];
  if (classes.length > 0) {
    const { compile } = await import("https://cdn.jsdelivr.net/npm/margaui/+esm");
    const css = await compile(classes);
    const style = document.createElement("style");
    style.id = "margaui-css";
    style.textContent = css;
    document.head.appendChild(style);
  }
</script>
```

Alternatively compile in JS and hand the CSS back to MoonBit:
`@glue.inject_style(doc, "margaui-css", css)` (from
`marianoguerra/tutuca/app/browser`) upserts a `<style id=…>` element —
the same helper exists in `app/wasm` for the wasm-gc backend.

**wasm-gc target** (the `demo/*_wasm` pattern): the demos no longer use the JS
compile above — the wasm `mount()` compiles the collected classes in MoonBit and
injects `<style id="margaui-css">` itself (see
[Compile in MoonBit](#compile-in-moonbit-what-the-demos-do)). The page just
pre-places an empty `<style id="margaui-css">` in `<head>` (so injection keeps a
stable, early cascade position) and calls `exports.mount()`; there is no
page-side `compile` and no `globalThis` hand-off.

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
