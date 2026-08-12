---
name: tutuca
description: Use when authoring or reviewing tutuca components in the MoonBit port — an `.html` view file with `<template>` views, `@`-directives and a `<script type="tutuca/state">` schema, compiled by `tutuca gen-views` / `tutuca watch` into a typed MoonBit module; the handlers beside it (`update` dispatch match, `compute`, `swap`, the render buckets), macros, styles, `ModuleDef` modules and storybook examples; `@component.component(...)` calls for views built in MoonBit; testing with `moon test` + the `@harness` package; Tailwind/margaui class compilation (`gen-margaui-css`); and authoring in the in-browser playground. Covers the post-edit `gen-views` → `moon check` → `moon test` verification recipe.
---

# Tutuca (MoonBit port)

Tutuca is an immutable-state SPA framework. This skill covers the MoonBit
port (`marianoguerra/tutuca`): a component is declared in an `.html` view file
— its state, its templates, its styles — which `tutuca gen-views` compiles
into a MoonBit module beside it, over the `@tutuca.Value` value layer. What
you write is the handlers. Modules are `ModuleDef` values, and tests run under
`moon test`. Read [core.md](./core.md) first for the framework primer.

## Verifying changes

After editing a tutuca module, run these before declaring the edit done:

```sh
tutuca gen-views <view>.html --name <Comp>   # …or leave `tutuca watch` running
moon check                                   # handlers vs state, views vs types
moon test                                    # @harness interaction tests
```

This is an ahead-of-time port: there is **no `tutuca lint` and no
`tutuca render`**. An undefined field or an unhandled `@on` handler is a
*build* error in the generated view module, not a finding from a run-time
linter you invoke separately — so `moon check` is the lint step. Full recipe in
[core.md](./core.md#verifying-changes); command details in
[cli.md](./cli.md).

## Companion skills

When authoring tutuca code, also load this if available:

- **margaui** — the Tailwind v4 / daisyUI-compatible class library. Reach
  for it when the project uses MargaUI / Tailwind class lists in `class=` /
  `:class=`. See [margaui.md](./margaui.md) for how the MoonBit port
  collects class names and hands them to margaui's compiler — it also
  carries a starter class vocabulary for when no margaui skill is
  available.

(The JS skill's `immutable-js` companion does not apply here: state is the
`@tutuca.Value` enum — `Null` / `Bool` / `Num` / `Str` / `List` / `Map` /
`Fn` / `Obj` — not immutable.js collections.)

## Routing

| Task                                                                                           | File                            |
| ---------------------------------------------------------------------------------------------- | ------------------------------- |
| Authoring views and handlers — the `.html` view file, the handler buckets (`update` / `compute` / `swap` / render), conditional display | [core.md](./core.md)           |
| Declaring state — the `<script type="tutuca/state">` schema, field spellings (`Array[T]`, `T?`, `Set[String]`, `Array[Any]`), generated mutators, slots, message buckets, `tutuca/init` fixtures | [schema.md](./schema.md) |
| `@on.<event>` handlers — handler argument names, generated `<Comp>Msg` payload types, modifiers, custom-element events | [events.md](./events.md) |
| Iterating lists — `@each` / `render-each`, `@when` filtering, `@enrich-with`, `@loop-with` pagination | [iteration.md](./iteration.md) |
| Macros — `@anode.Macro` definitions, `<x:name>` calls, slots, registration | [macros.md](./macros.md) |
| Component CSS — `style` / `common_style` / `global_style` scoping and pitfalls | [styles.md](./styles.md) |
| Designing components — responsibilities, state ownership, channel choice, do's & don'ts | [component-design.md](./component-design.md) |
| Embedded CLI commands, flags, exit codes, and every `gen-views` diagnostic (lint codes included) | [cli.md](./cli.md)             |
| `Bubble` / `send`-`Receive` / async `request`-`Response` channels, catch-all arms, `RequestFn` registration | [request-response.md](./request-response.md) |
| Drag & drop, dynamic bindings (`*x`), pseudo-`x`, custom collections via the `Obj` trait | [advanced.md](./advanced.md)   |
| Setting up MargaUI styling — `collect_classes()`, the MoonBit compile step, `inject_style` | [margaui.md](./margaui.md)     |
| Runtime semantics — path steps, transaction lifecycle, dyn-var teleporting, async key pinning (`live_path`) | [semantics.md](./semantics.md) |
| Authoring tests — `moon test` blocks, the `@harness` mount/drive/read API, designing handlers for testability | [testing.md](./testing.md) |
| Authoring in an in-browser playground — generated names without the CLI, the view+code pair convention, verifying without `moon` | [playground.md](./playground.md) |
| Task-oriented recipes — iteration, filtering, conditional content, conditional attributes, dynamic vars, composition, events, adding a storybook example, a complete todo app | [patterns/README.md](./patterns/README.md) |

Read `core.md` first. Reach for the others only when the task touches
them — each is referenced inline from `core.md` so you'll be pointed
there when relevant.
