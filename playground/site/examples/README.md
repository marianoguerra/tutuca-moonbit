# Playground examples

These are the editable sources the `<mb-playground>` embeds load — standalone
**teaching editions**, deliberately distinct from `storybook/examples/`:

- compact (they fit an editor pane), framework-free inline styles instead of
  margaui classes, and a bare `fn build() -> @component.ModuleDef` entry;
- compiled **in the browser** against the packages `assemble.mjs` exposes
  (`@tutuca` is the module-root facade, plus `@component`, `@anode`, …).

Each example is a PAIR: `foo.mbt` (the Component tab) and `foo.html` (the View
tab), named by the embed's `src` / `view` attributes in `../index.html`. The
views are compiled ahead of time — the page runs the same generator
`tutuca gen-views` does, and hands the result to the compiler as extra files of
the example's package, so `foo.mbt` can name `<comp>_views()` and `<Comp>Msg`
with no import. Name every template (`<template id="Counter">`), so one file
can carry a whole module's components; a view file with no `<template>` id
would need the `<!-- name: X -->` fallback instead.

No checked-in `*_view_gen.mbt` here: unlike `storybook/examples/`, these are
generated in the browser on every run, so they are NOT registered in the
`gen-views` task.

Don't sync them from the storybook ports — edit them for what reads well in a
small embedded editor. No moon package includes these files, so CI compiles
each one (generating its views first) via
`moon run --target native cmd/dev -- check-examples`
(`scripts/check-playground-examples.mjs`); run that after touching them or
after any library API change.
