# Tutuca — Authoring in a Playground

Read this file when writing tutuca code for an **in-browser playground**
— an environment that compiles and mounts a component module from
editable sources, with no filesystem, no `tutuca` CLI, and no `moon`
toolchain. Everything else in this skill still applies; this file covers
what differs.

## Same generator, same names

A playground runs the **same view generator** `tutuca gen-views` does,
in the browser, on every run — so every generated name documented in
[cli.md](./cli.md) applies verbatim. Naming derives from the template /
component names in the view source:

| In the view file | Generated |
| ---------------- | --------- |
| `<template id="Items">` / `state Items` | `items_views()`, `ItemsState`, `ItemsState::zero()`, `items_component(...)` |
| the `@on` names the templates use | `ItemsMsg` + `ItemsMsg::from_dispatch` (payload types per the table in [events.md](./events.md) *Generated `Msg` payload types*) |
| the `$`-callables / `@when` / `@enrich-with` names | `ItemsMethod`, `ItemsWhen`, … — one enum per bucket, carrying the names the script block does not answer (see [cli.md](./cli.md)) |

Name **every** template (`<template id="Counter">`) so one view source
can carry a whole module's components. The generated module is compiled
alongside your MoonBit source as an extra file of the same package, so
your code names `items_component` and `ItemsMsg` with **no import**.

## The pair convention

A playground example is a PAIR of sources compiled together:

- the **view** source — the `<template>`s, the
  `<script type="tutuca/state">` schema, and any `<style>`s, exactly as
  in an `.html` view file;
- the **component** source — MoonBit, ending in a bare entry point:

  ```moonbit nocheck
  // nocheck: `...` stands in for the reader's components
  fn build() -> @component.ModuleDef {
    @component.ModuleDef::new(name="demo", components=[...], examples=[
      { component: "Items", title: "Default", args: Map([]), view: None },
    ])
  }
  ```

The playground mounts the module's **first example** — order the
`examples` array so the one you want shown leads.

Typical imports available as package aliases: `@tutuca` (the value layer
and core), `@component`, `@anode`. Keep components compact — the sources
live in an editor pane.

## Verifying without `moon`

The repo loop (`gen-views` → `moon check` → `moon test`,
[core.md](./core.md) *Verifying changes*) collapses here to one step:
**recompile and read the diagnostics**. The same errors surface — an
unknown `.field` fails view generation, an unhandled `@on` name makes
the `Msg` match non-exhaustive — but there is no separate lint or test
run, and no way to run `@harness` tests.

Two consequences to work with:

- **You cannot open the generated module.** Errors that point into it
  arrive with positions in a file you can't see. Don't guess from the
  error text alone — re-derive what the generator produced from the
  naming rules above and the payload table in [core.md](./core.md); the
  bucket enums are closed and view-driven, so a "no such constructor"
  error means the view doesn't (or no longer does) reference that name.
- **Behavior is verified by interacting.** Mounting successfully proves
  the wiring; click through the flows a harness test would drive. Design
  handlers exactly as [testing.md](./testing.md) recommends anyway
  (granular named args, extracted pure fns) so the code ports unchanged
  into a real package with tests.

## Styling

Playgrounds typically compile margaui classes from the collected view
literals, same as any host ([margaui.md](./margaui.md)) — the
literal-only collector rule and the decoy-view workaround apply
unchanged. When in doubt, inline `style=` attributes or a view `<style>`
work with no compile step at all.
