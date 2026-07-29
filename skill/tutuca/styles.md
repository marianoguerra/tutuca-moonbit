# Tutuca — Styles

Read this file when authoring `style` / `common_style` / `global_style`
blocks or debugging CSS that silently doesn't apply.

## Where styles live

Styles live in the view file: a `<style>` inside a `<template>` is that view's
style, one at file level is the component's `common_style`, and one marked
`data-global` is its `global_style`.

```html
<script type="tutuca/state">
  interface styled { record state {} }
</script>

<!-- scoped to all views of this component -->
<style>.shared { color: yellow; }</style>
<!-- injected unscoped -->
<style data-global>.app-thing { color: green; }</style>

<template id="Styled">
  <style>.mine { color: red; }</style>
  <p class="mine">x</p>
</template>
<template id="Styled:two">
  <style>.mine { color: orange; }</style>
  <p class="mine">two</p>
</template>
```

The generated `<c>_common_style` / `<c>_global_style` are plain strings the
wrapper passes; `Component::compile_style()` produces the compiled text;
`Components::compile_styles()` the whole registry's — injection is host
territory (`@glue.install_styles(app, doc)` in the browser hosts, the
harness's `h.styles()` in tests).

## Scoping, and what it does to your CSS

A view's own `style` and the component's `common_style` are wrapped in a
component-scoped selector (`[data-cid="N"]{ … }`, plus `[data-vid]` for a
per-view style), so their CSS lands *inside* a style-rule block.

A useful consequence: **bare declarations with no selector** (e.g.
`color: red; padding: 1rem;`) land directly inside that wrapper, so they style
the component's **root element** — the host node carrying `data-cid` (plus
`data-vid` for a per-view style). Reach for this to style a component's own
outer element without adding a wrapper selector; nested rules with a selector
(`.mine { … }`) target descendants instead.

## What must go in `global_style`

Because the CSS sits inside a style-rule block,
top-level-only constructs break there and the browser silently drops them —
put them in `global_style` (injected verbatim, no wrapper) instead:

- Non-nestable at-rules: `@import`, `@charset`, `@namespace`, `@font-face`,
  `@keyframes`, `@page`, `@property`, `@counter-style`, `@font-feature-values`,
  `@font-palette-values`, `@view-transition`. (Conditional group rules —
  `@media`, `@supports`, `@container`, `@layer`, `@scope`, `@starting-style` —
  *do* nest and stay in `style`/`common_style`.)
- Rules whose leading selector is `html`, `body`, or `:root`: once scoped they
  become descendant selectors that never match.

**Nothing checks this.** No lint rule covers either case, `moon check` cannot see
inside a CSS string, and the browser drops the offending rule without a console
message — which is exactly why the list above is worth knowing by heart. A
`@keyframes` that quietly never applies looks identical to one that does.

## See also

For Tailwind / MargaUI utility classes (compiling `class=` literals into
CSS) and the `collect_classes()` + `inject_style` wiring, see
[margaui.md](./margaui.md).
