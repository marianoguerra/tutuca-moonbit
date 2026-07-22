---
name: tutuca
description: Use when authoring or reviewing tutuca components in the MoonBit port — `@component.component(...)` definitions with a typed state struct, `#|` raw-string HTML views, `@`-directives, the `update` dispatch match plus `mutate` / `compute` and the typed render buckets, macros, `ModuleDef` modules — or when testing with `moon test` + the `@harness` package, or running the embedded `tutuca` CLI (`lint` / `render` / `show`). Covers the post-edit `tutuca lint` → `moon test` → `tutuca render --title "<example>"` verification recipe.
---

<!-- The MoonBit tutuca skill lives at skill/tutuca/ in this repo and is
     embedded into the CLI binary by the dev `dist` tooling — edit here. -->

# Tutuca (MoonBit port)

Tutuca is an immutable-state SPA framework. This skill covers the MoonBit
port (`marianoguerra/tutuca`): components are built with
`@component.component(...)` from a plain state struct
(`derive(ToJson, FromJson)`) over the `@tutuca.Value` value layer, modules
are `ModuleDef` values, and tests run under `moon test`. Read
[core.md](./core.md) first for the framework primer.

## Verifying changes

After editing a tutuca module, run these before declaring the edit done:

```sh
tutuca lint                          # undefined fields/handlers (exit 2 on errors)
moon test                            # @harness interaction tests (non-zero on failures)
tutuca render --title "<example>"    # mount the example covering the change (exit 3 on crash)
```

`tutuca` here is the project's **embedded CLI binary** — a native `main`
that hands its own `ModuleDef` to `@cli.plan_with_module(argv, Some(module))`
(see [cli.md](./cli.md)); there is no path-based module loading. Full
recipe — when to skip `moon test`, adding a covering example — in
[core.md](./core.md#verifying-changes).

## Companion skills

When authoring tutuca code, also load this if available:

- **margaui** — the Tailwind v4 / daisyUI-compatible class library. Reach
  for it when the project uses MargaUI / Tailwind class lists in `class=` /
  `:class=`. See [margaui.md](./margaui.md) for how the MoonBit port
  collects class names and hands them to margaui's compiler.

(The JS skill's `immutable-js` companion does not apply here: state is the
`@tutuca.Value` enum — `Null` / `Bool` / `Num` / `Str` / `List` / `Map` /
`Fn` / `Obj` — not immutable.js collections.)

## Routing

| Task                                                                                           | File                            |
| ---------------------------------------------------------------------------------------------- | ------------------------------- |
| Authoring `@component.component(...)`, views, fields, events, conditional display | [core.md](./core.md)           |
| Iterating lists — `@each` / `render-each`, `@when` filtering, `@enrich-with`, `@loop-with` pagination | [iteration.md](./iteration.md) |
| Macros — `@anode.Macro` definitions, `<x:name>` calls, slots, registration | [macros.md](./macros.md) |
| Component CSS — `style` / `common_style` / `global_style` scoping and pitfalls | [styles.md](./styles.md) |
| Designing components — responsibilities, state ownership, channel choice, do's & don'ts | [component-design.md](./component-design.md) |
| Embedded CLI commands, flags, exit codes, linter rules                                         | [cli.md](./cli.md)             |
| `Bubble` / `send`-`Receive` / async `request`-`Response` channels, catch-all arms, `RequestFn` registration | [request-response.md](./request-response.md) |
| Drag & drop, dynamic bindings (`*x`), pseudo-`x`, custom collections via the `Obj` trait | [advanced.md](./advanced.md)   |
| Setting up MargaUI styling — `collect_classes()`, the CDN compile step, `inject_style` | [margaui.md](./margaui.md)     |
| Runtime semantics — path steps, transaction lifecycle, dyn-var teleporting, async key pinning (`live_path`) | [semantics.md](./semantics.md) |
| Authoring tests — `moon test` blocks, the `@harness` mount/drive/read API, designing handlers for testability | [testing.md](./testing.md) |
| Task-oriented recipes — iteration, filtering, conditional content, conditional attributes, dynamic vars, composition, events | [patterns/README.md](./patterns/README.md) |

Read `core.md` first. Reach for the others only when the task touches
them — each is referenced inline from `core.md` so you'll be pointed
there when relevant.
