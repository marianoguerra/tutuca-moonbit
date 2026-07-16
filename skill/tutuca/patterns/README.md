# Tutuca — Patterns

Task-oriented recipes: "how do I do X" with a minimal working snippet and the
one pitfall worth knowing. Each recipe is self-contained and brief; for the
full directive *semantics* behind a pattern, see [core.md](../core.md) and its
spokes. Many map 1:1 to runnable modules in this repo's `examples/*.mbt`.

New to Tutuca? Read [core.md](../core.md) first, then reach here for a specific
task.

## Iteration & lists

- [Iterate a list](iterate-a-list.md) — render one element per item with `@each` / `render-each`.
- [Filter a list](filter-a-list.md) — keep only matching items with `@when`.
- [Enrich each item](enrich-each-item.md) — expose derived per-item values as `@`-bindings.
- [Paginate a list](paginate-a-list.md) — slice the iteration with `@loop-with` `start`/`end`.
- [Filter and paginate a list](filter-and-paginate.md) — do both with `@loop-with` `keys` (filter-then-slice, identity preserved).

## Conditional content & attributes

- [Show or hide content](show-or-hide-content.md) — `@show` / `@hide` and the boolean predicates.
- [Switch between views](switch-between-views.md) — pick a component's own view with `as=` or `@push-view`.
- [Conditional attribute value](conditional-attribute-value.md) — set a class/title by condition with `@if` / `@then` / `@else`.
- [Tabbed interface](tabbed-interface.md) — a `currentView` field + predicates to show the panel and highlight the active tab.

## Context & dynamic bindings

- [Share state across the tree](share-state-across-the-tree.md) — `provide` / `lookup` and reading `*name`.
- [Edit through a dynamic target](edit-through-a-dynamic-target.md) — render `*name` and teleport edits back to the owner.

## Composition

- [Render a child component](render-a-child-component.md) — `<x render=".field">` and multiple views.
- [Reuse markup with macros](reuse-markup-with-macros.md) — `@anode.Macro` with parameters and slots.

## Data & events

- [Bind text and attributes](bind-text-and-attributes.md) — `@text`, `:attr`, `$'…'` templates, scope enrichment.
- [Handle events](handle-events.md) — `@on.<event>`, handler args, modifiers, custom events.
- [Read a picked file](file-input.md) — `@on.change="… value"` and the file-metadata `Map`.

## Component communication

- [Coordinate components](coordinate-components.md) — `bubble`, `send`/`receive`, async `request`/`response`.

## Examples & catalog

- [Add an example for a component](add-an-example.md) — an `ExampleDef` in the `ModuleDef`, driving `tutuca render`, the harness tests, and the demo hosts.
