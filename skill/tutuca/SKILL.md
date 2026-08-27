---
name: tutuca
description: Author, review, debug, and test Tutuca MoonBit components and Tutucard single-file UI cards. Use for Tutuca HTML views, state and script blocks, generated view modules, ModuleDef wiring, events, messages and intents, component tests, card scenes, styling, playgrounds, and the tutuca CLI.
---

# Tutuca and Tutucard

Tutuca is an immutable-state UI framework for MoonBit. A view file holds the
typed state schema, templates, styles, and optionally a small handler language.
There are two authoring paths over that same file format:

| Path | Choose it when | Build and test |
|---|---|---|
| **Compiled Tutuca component** | The UI needs MoonBit functions, imports, custom objects, host wiring, or a reusable `ModuleDef` | `tutuca gen-views` or `tutuca watch`, then `moon check` and `moon test` |
| **Tutucard** | The UI should remain one portable HTML file and use only the schema, script, template, style, fixture, and scene languages | The card runtime compiles it to a component wasm module in the browser; validate with the card checker and its `tutuca/test` scenes |

Read [tutucard.md](./tutucard.md) first for a card. Read
[core.md](./core.md) first for a compiled component. Load only the additional
references needed for the task.

## Working method

1. Identify the path from the surrounding files and requested deployment.
   An HTML file is not necessarily a card: an adjacent generated
   `*_view_gen.mbt` and MoonBit component builder indicate the compiled path.
2. Inspect the schema and templates before changing handlers. Generated
   message and handler enums are view-driven.
3. Keep behavior in `tutuca/script` when the language expresses it. On the
   compiled path, use MoonBit for refused script arms and host/module wiring.
4. Regenerate generated view modules; never edit a `*_gen.mbt` file directly.
5. Validate the chosen path, including interaction tests for observable
   behavior and a browser check for visual changes.

## Invariants worth keeping in context

- State is immutable. A handler returns a successor; the transactor commits it
  and rerenders.
- `.field` reads state, `$name` calls a derived handler in a value position,
  and `@name` reads the current render binding. Event handler names are bare.
- Event handlers belong in `update` on the compiled path. End its dispatch
  match with `_ => Unhandled`; `Unchanged` vetoes while `Unhandled` falls
  through to generated mutators.
- View expressions do not traverse arbitrary state paths. Use a child render,
  a computed value, or enrichment; a render binding may read one member.
- Tutuca has no automatic `init` lifecycle. The host or a test must send it.
- Generated bucket enums are closed over names referenced by the views. Change
  the view, regenerate, then implement the new arm.
- Literal class names can be collected for Tailwind/MargaUI. Runtime-assembled
  class names cannot.

## References by task

### Start and architecture

- [core.md](./core.md) — compiled component primer, generated names,
  `Component`, `ModuleDef`, handler buckets, rendering, and host mounting.
- [tutucard.md](./tutucard.md) — card anatomy, capabilities, limits,
  multi-component cards, authoring loop, and when to graduate to MoonBit.
- [component-design.md](./component-design.md) — state ownership,
  responsibilities, composition, and communication choices.
- [playground.md](./playground.md) — the MoonBit in-browser playground, where
  view and MoonBit sources compile as a pair. This is distinct from Tutucard.

### Views, state, and behavior

- [schema.md](./schema.md) — state types, records, enums, flags, slots,
  generated mutators, `tutuca/init`, the script language, `new` and `@cur`,
  contracts, and script refusals.
- [events.md](./events.md) — event payloads, generated message types,
  modifiers, safe event paths, files, and custom events.
- [iteration.md](./iteration.md) — `@each`, filtering, enrichment,
  pagination, and custom collections.
- [messages-and-intents.md](./messages-and-intents.md) — messages, addressed
  sends, intent routes and outcomes, forwarding, replies, and async delivery.
- [protocols.md](./protocols.md) — shared component contracts, implicit and
  named operations, semantic views/properties, constraints, and strict versus
  gradual validation.
- [macros.md](./macros.md) — reusable view markup and slots.
- [styles.md](./styles.md) — scoped, common, and global component CSS.
- [advanced.md](./advanced.md) — drag and drop, dynamic bindings, pseudo-`x`,
  and `Obj` collections.
- [semantics.md](./semantics.md) — paths, transaction order, dynamic lookup,
  and keyed async delivery; load for subtle runtime bugs.

### Quality and delivery

- [testing.md](./testing.md) — `moon test`, the in-memory `@harness`, card
  scene syntax, record mode, intent fixtures, and headless card driving.
- [margaui.md](./margaui.md) — collecting and compiling Tailwind/MargaUI
  classes, runtime injection, and literal-class constraints.
- [cli.md](./cli.md) — installing and using `gen-views`, `watch`, CSS
  generation, storybook serving, diagnostics, and exit codes.
- [patterns/README.md](./patterns/README.md) — short task recipes and complete
  examples; use after choosing the architecture and language path.

## Verification

For a compiled component, regenerate its view and run the project-appropriate
targets. At minimum:

```sh
tutuca gen-views path/to/view.html --name Component
moon check
moon test
moon fmt
moon info
```

Use `tutuca watch` while iterating. In this project, prefer the repository task
runner described by its `AGENTS.md`; it also checks generated-file drift and
all supported targets.

For a card, compile/check it with the card runtime, run every embedded
`tutuca/test` scene, and inspect the mounted result. See
[tutucard.md](./tutucard.md#validation) and
[testing.md](./testing.md#testing-a-card-script-typetutucatest).
