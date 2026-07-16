# Tutuca — MargaUI Styling

Reach this file to add **MargaUI** (the Tailwind v4 / daisyUI-compatible
class library) styling to a tutuca app: link its theme, and compile the
utility classes your views reference into CSS. If you only need
scoped/global component CSS, [styles.md](./styles.md) is enough.

In the MoonBit port the split is: **tutuca collects, margaui compiles,
the host injects.** The MoonBit side gathers every literal class the
compiled views can show — `app.scope.comps.collect_classes()` (or, per
compiled view, `@anode.ANode::collect_classes`) — and the browser host
hands that list to margaui's `compile` (a JS function) and injects the
resulting CSS.

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

**wasm-gc target** (the `demo/*_wasm` pattern): the wasm `main` sets
`globalThis.__tutuca_classes` via the `@core` FFI, and the shared loader's
`applyMargaui()` compiles + injects — called **after** `mount()`, because
the wasm module's top-level await races the page's inline scripts (see
`demo/counter_wasm/loader.mjs`).

## Pitfall: assembled class names are invisible to the scanner

`collect_classes` only reads **constant** class literals out of compiled
templates. It cannot see a class name that is assembled rather than
written out verbatim, so the margaui CSS for that class is never emitted
and it renders unstyled. Two cases:

- **Interpolated templates** — `:class="$'bg-{.color}'"` contributes only the
  constant prefix `bg-`, never `bg-red` / `bg-blue`. Same for any `{…}` segment.
- **Classes built in a method** — anything a `MethodFn` returns (e.g. a
  `headerClass` that builds `"progress-" + color`) is never scanned at
  all; the collector only reads view templates, not MoonBit bodies.

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

`examples/personal_site.mbt` has the worked version: its
`_margauiClasses` view interpolates a **MoonBit** helper
(`ps_category_decoy_classes()`) into the view **string at construction
time**, so the color tables stay the single source of truth while the
template still carries literals. The cost is that the palette and the
methods can drift apart with no check catching it; keep them adjacent and
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
