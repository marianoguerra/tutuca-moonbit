# Playground examples

These are the editable sources the `<mb-playground>` embeds load — standalone
**teaching editions**, deliberately distinct from `storybook/examples/`:

- compact (they fit an editor pane), framework-free inline styles instead of
  margaui classes, and a bare `fn build() -> @component.ModuleDef` entry;
- compiled **in the browser** against the packages `assemble.mjs` exposes
  (`@tutuca` is the module-root facade, plus `@component`, `@anode`, …).

Don't sync them from the storybook ports — edit them for what reads well in a
small embedded editor. No moon package includes these files, so CI compiles
each one via `moon run --target native cmd/dev -- check-examples`
(`scripts/check-playground-examples.mjs`); run that after touching them or
after any library API change.
