# Tutuca — Styles

Read this file when authoring `style` / `common_style` / `global_style`
blocks or debugging CSS that silently doesn't apply.

```moonbit
priv struct NoState {} derive(ToJson, FromJson)

@component.component(
  views={
    "main": @anode.View::new("main", raw_view="<p class=\"mine\">x</p>", style=".mine { color: red; }"),
    "two": @anode.View::new("two", raw_view="<p class=\"mine\">two</p>", style=".mine { color: orange; }"),
  },
  name="Styled",
  init=NoState::{  },
  // scoped to all views of this component
  common_style=".shared { color: yellow; }",
  // injected unscoped
  global_style=".app-thing { color: green; }",
)
```

Styles are plain MoonBit strings (use `#|` raw strings for multi-line
CSS). `Component::compile_style()` produces the compiled text;
`Components::compile_styles()` the whole registry's — injection is host
territory (`@glue.install_styles(app, doc)` in the browser hosts, the
harness's `h.styles()` in tests).

A view's own `style` and the component's `common_style` are wrapped in a
component-scoped selector (`[data-cid="N"]{ … }`, plus `[data-vid]` for a
per-view style), so their CSS lands *inside* a style-rule block.

A useful consequence: **bare declarations with no selector** (e.g.
`color: red; padding: 1rem;`) land directly inside that wrapper, so they style
the component's **root element** — the host node carrying `data-cid` (plus
`data-vid` for a per-view style). Reach for this to style a component's own
outer element without adding a wrapper selector; nested rules with a selector
(`.mine { … }`) target descendants instead.

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

The linter flags both (`TOP_LEVEL_AT_RULE_IN_SCOPED_STYLE`,
`GLOBAL_SELECTOR_IN_SCOPED_STYLE`). For a genuine false positive, put a
`/* tutuca-lint-ignore */` comment on the same line as the flagged construct.

For Tailwind / MargaUI utility classes (compiling `class=` literals into
CSS) and the `collect_classes()` + `inject_style` wiring, see
[margaui.md](./margaui.md).
