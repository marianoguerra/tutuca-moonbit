# Tutuca — MargaUI Styling

Reach this file to add **MargaUI** (the Tailwind v4 / daisyUI-compatible
class library) styling to a tutuca app: link its theme, and compile the
utility classes your views reference into CSS. If you only need
scoped/global component CSS, [styles.md](./styles.md) is enough.

In the MoonBit port the split is: **tutuca collects, a Tailwind v4
compiler compiles, the host injects.** The MoonBit side gathers every
literal class the compiled views can show —
`app.scope.comps.collect_classes() -> Array[String]` (or, per compiled view,
`@anode.ANode::collect_classes(set) -> Unit`, which *fills* a `@set.Set[String]`
you pass in rather than returning one) — that class list is compiled to CSS, and
the host injects the result as `<style id="margaui-css">`.

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

A wasm-gc host compiles margaui **in MoonBit** via
`marianoguerra/tailwindcss`, so there is no CDN import and styling works
offline. The moving parts:

- **The bundles.** `cmd/css-bundle` (a dev tool) runs the tailwindcss `bundle`
  graph walk (`@tw.collect_imports`) over each entry in `css/assets/` and emits
  two embedded modules — `css/tailwind_bundle_gen.mbt` and
  `css/margaui_bundle_gen.mbt`, each an `@import` map as an
  `Array[(String, String)]` plus its entry string. Regenerate both with:

  (regenerated from the pinned upstream releases by the tutuca repo's
  `css-bundle` task — not something a consuming project runs)

  The task clones margaui from GitHub at the ref pinned in
  `scripts/fetch-margaui.mjs` into the gitignored `_build/margaui`, and downloads
  the `tailwindcss` npm tarball at the version pinned in
  `scripts/fetch-tailwind.mjs` into `_build/tailwind` — no local checkout to set
  up, and the pins are what make the committed bundles reproducible. Bump a pin
  to pick up new CSS.

  Stock Tailwind's `theme`/`preflight`/`utilities` come from **npm**, not from
  margaui's `tw/` directory. margaui vendors a hand-maintained mirror of those
  files that has run behind upstream, and the MoonBit compiler is ported from one
  exact Tailwind tag — so the stylesheets are pinned to that same tag, and
  `fetch-tailwind.mjs` fails the build if the two pins drift apart.

- **The compile helpers.** `css`'s
  `compile_margaui(ArrayView[String], polyfills? : Int) -> String raise` builds a
  `MemoryStylesheetLoader` over both bundles (margaui's entry imports `./tw/*`,
  which live in the Tailwind one) and calls
  `@tw.compile_sync(margaui_entry, …).build(classes)` — `compile_sync` is the
  wasm-gc-safe path, no async runtime. `compile_tailwind` is the same against
  stock Tailwind alone, with no component layers. Both **raise**, so a caller
  needs a `try` or its own `raise`; both take the class list as an `ArrayView`,
  which `collect_classes()`'s `Array` coerces to.

- **The host.** After `mount()`, the host compiles + injects in one step:

  ```moonbit
  let css = @css.compile_margaui(app.scope.comps.collect_classes())
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

## Compile at build time (the CLI)

If your views are ahead-of-time compiled (`gen-views`), you do not need to
compile in the browser at all — the CLI runs the same collection over the view
**files** and writes a stylesheet:

```sh
tutuca gen-margaui-css  src/ -o public/app.css   # Tailwind + margaui components
tutuca gen-tailwind-css src/ -o public/app.css   # stock Tailwind only
```

Paths follow `watch`'s rule: a directory contributes the `.html` files that
already have a generated sibling, so pointing it at a project root does not try
to compile `index.html`. Defaults to the current directory. The stylesheets are
compiled into the binary — no Node, no CDN, no margaui checkout.

The same literal-only limit applies (see "What the collector cannot see" below).
`--print-classes` shows exactly what was collected, one name per line, and
`--classes <file>` feeds back the names a view assembles at run time. Note that
an interpolated `$'badge badge-{.kind}'` contributes its literal prefix
`badge-`, which compiles to nothing — a stub in the list, not the real name.

Other flags: `--entry <file>` compiles your own CSS entry instead of the
embedded one (resolving its `@import`s from disk, so a project theme or
`@source` setup works), and `--polyfills <0..3>` matches the compiler's levels.

While authoring, let `watch` do both — view modules and stylesheet stay current
together, so a class you just typed is styled by the time you reload:

```sh
tutuca watch src/ --margaui-css public/app.css
```

It runs the same collect/compile/write path the one-shot command does, over
every watched view, once per settled batch. `--css-entry` / `--css-classes`
forward to `--entry` / `--classes`; pass them if your build does.

## Wire it into tutuca

The integration is three steps, all on the MoonBit side: after mounting,
**collect** the class set, **compile** it, **inject** the CSS.

**wasm-gc target**: `mount()` compiles + injects in MoonBit; the page only pre-places an empty `<style id="margaui-css">` in
`<head>` (so injection keeps a stable, early cascade position — palette links
appended later still win) and calls `exports.mount()`:

```moonbit nocheck
// nocheck: `app` is the reader's mounted App
// in the host's mount(), after the app is built:
let css = @css.compile_margaui(app.scope.comps.collect_classes())
@wglue.inject_style(doc, "margaui-css", css) // app/wasm inject_style upserts by id
```

Export a `refresh_margaui()` that re-runs the same two lines, and call it from
the loader after a dyncomp bundle registers new classes.

**js target**: same shape with `app/browser`'s `@glue.inject_style`. If the
compile must run in the page instead of the module (e.g. an in-browser
playground that mounts freshly-compiled user code in an iframe), ship the
compiler as a small **wasm-gc** executable exporting `compile(classesJson) ->
css` (built release plus `wasm-opt`, roughly 0.5 MB) and call it from the page
after mount. Either way there is no JS margaui package, no CDN import, and no
`globalThis` class hand-off between MoonBit and the page.

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

```moonbit nocheck
// nocheck: a bucket argument, not a top-level item
views={
  // enumerate color × utility so each full class name appears verbatim;
  // never rendered — registration is enough for the collector to see it
  "_margauiClasses": "<p class=\"bg-red bg-blue progress-red progress-blue\"></p>",
},
```

When the class set is driven by a MoonBit table (a color list, a
kind → class map), keep one source of truth by interpolating a helper
into the view **string at construction time** — the template still
carries plain literals by the time the collector reads it:

```moonbit nocheck
// nocheck: `COLORS` is the reader's own list
fn decoy_classes() -> String {
  // one entry per assembled class, joined space-separated:
  // "bg-red bg-blue progress-red progress-blue"
  COLORS.map(c => "bg-\{c} progress-\{c}").join(" ")
}

views["_margauiClasses"] = @anode.View::new(
  "_margauiClasses",
  raw_view="<p class=\"\{decoy_classes()}\"></p>",
)
```

The cost is that the palette and the compute entries can drift apart
with no check catching it; keep them adjacent and update both together.
(This is the same rule [component-design.md](./component-design.md)
gives for runtime-assembled margaui classes.)

## When authoring class lists

Write margaui/Tailwind classes as **literal lists** in `class=` /
`:class` so the collector sees them. margaui is daisyUI-compatible:
component classes (`btn`, `card`, `input`, `badge`, `join`, …) plus the
Tailwind v4 utilities. A starter vocabulary — enough for a typical app
shell, all compiling against the embedded bundle:

```html
<!-- app shell: a centered column -->
<div class="max-w-md mx-auto p-4 flex flex-col gap-3">
  <!-- panel -->
  <div class="card bg-base-200">
    <div class="card-body">
      <h2 class="card-title">Todos</h2>
      <!-- toolbar row -->
      <div class="flex gap-2 items-center">
        <input class="input w-full" placeholder="What needs doing?" />
        <button class="btn btn-primary btn-sm">Add</button>
      </div>
      <!-- an item row; completed state = 'opacity-60 line-through' -->
      <div class="flex gap-3 items-center w-full">
        <input type="checkbox" class="checkbox" />
        <span class="w-full">Buy milk</span>
        <button class="btn btn-soft btn-sm btn-error btn-circle">✕</button>
      </div>
      <!-- grouped controls + a counter -->
      <div class="join">
        <button class="btn btn-sm join-item">All</button>
        <button class="btn btn-sm join-item btn-outline">Active</button>
      </div>
      <span class="badge badge-neutral">3 left</span>
    </div>
  </div>
</div>
```

Buttons compose a kind (`btn-primary` / `btn-success` / `btn-error` /
`btn-ghost` / `btn-soft` / `btn-outline`) and a size (`btn-xs` /
`btn-sm`) onto the base `btn`; `input`, `checkbox`, `badge` and `card`
follow the same base-plus-modifier pattern. For state-dependent styling,
remember the collector rule above: switch between **full literals** with
`@if.class` (`@then="'opacity-60 line-through'" @else="''"`), never
assemble a class name from parts. If a dedicated margaui skill is
available in your environment it has the full component catalogue; this
vocabulary is enough when it isn't.

## See also

- [styles.md](./styles.md) — scoped/global component CSS.
- [advanced.md](./advanced.md) — dynamic bindings, drag & drop, and other
  advanced view features.
- [cli.md](./cli.md) — `install-skill` installs this skill (the tutuca
  one; margaui's is not bundled).
