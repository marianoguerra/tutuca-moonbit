# Tutucard — Single-file Tutuca components

Read this first when the deliverable is a **card**: one HTML file that a page
can check, compile to a `tutuca:component` wasm module, instantiate, and mount
without shipping the MoonBit compiler.

A card and an ahead-of-time Tutuca component use the same view, state, and
handler languages. The difference is deployment and extension: a card stays
inside the closed card language; a compiled component may add arbitrary
MoonBit and package wiring.

## Choose the card path deliberately

Use a card when portability, live editing, embedding, or toolchain-free use is
more important than arbitrary MoonBit integration. Use a compiled component
when you need to name a MoonBit value: imports, closures, custom `Obj`
implementations, hand-written view functions, host adapters, or `ModuleDef`
composition beyond what the card file declares.

Do not infer the path from `.html` alone. A view file with an adjacent
generated module and a MoonBit component builder is the ahead-of-time path.

## Card anatomy

A card keeps its concerns in one file:

```html
<script type="tutuca/spec">
  state Counter {
    count: Int
    property { count: Int { get .count set .count } }
  }
</script>

<script type="tutuca/script">
  receive inc { .count += 1 }
  compute label { $'count: {.count}' }
</script>

<script type="tutuca/test">
{
  "increments": { "steps": [
    { "click": "button.inc" },
    { "expect": "text", "at": "output", "is": "count: 1" },
    { "expect": "state", "at": ".count", "is": 1 }
  ] }
}
</script>

<template id="Counter:main" data-root>
  <button class="inc" @on.click="inc">+</button>
  <output @text="$label"></output>
</template>
```

- `tutuca/spec` declares components, field types, public properties, records, enums, flags,
  message buckets, dynamic `provide`/`lookup`, named initial states, and the
  `pred` / `invariant` rules the component keeps.
- `tutuca/script` declares receives, derived values, enrichment, intents,
  effects, collection updates, and the `requires` / `ensures` clauses that
  attach a spec-block rule to one transition.
- `tutuca/init` contains named fixtures. A fixture may provide a value, drive
  steps, documentation, and a default marker.
- `tutuca/test` contains named interaction scenes. It is optional but should
  accompany behavior that can regress.
- Templates render the component. A card without a template has nothing to
  mount. Styles may be written in the same view file or supplied by the host.

For the complete schema and script grammar, read [schema.md](./schema.md).
For template directives, start with [core.md](./core.md#notation-reference)
and load [events.md](./events.md) or [iteration.md](./iteration.md) as needed.

## What cards can express

Cards support the full declared state shapes: scalars, arrays, maps, sets,
options, tuples, records, enums, flags, `Any`, and sibling component slots.
Their handler language covers:

- field and nested collection updates;
- simple field-backed properties and fixed-signature complex property getters/setters;
- `receive`, `compute`, `enrich`, and `enrichScope` in the script block, and
  `pred` / `invariant` in the spec block beside the state they are about;
- `requires` and `ensures` clauses attaching one of those rules to a
  transition, with user-facing `format` text on the rule;
- `send`, addressed `sendAt`, `intent`, `forward`, `reply`, `fail`, and
  `stop`;
- conditionals, arithmetic, comparisons, string templates, and the closed
  reading vocabulary documented in [schema.md](./schema.md#the-reading-vocabulary);
- `new` plus `@cur` for declared records and sibling component instances.

This is compiled behavior, not an interpreter fallback. The browser compiles
the checked card to a core wasm component and the Tutuca host mounts it.

## Limits and refusals

The card compiler rejects a malformed file, but it may **refuse one
declaration** it cannot lower while compiling the rest. Review the build's
`refusals`; a refused handler is absent from the manifest and the host treats
its name as unhandled. Never treat a mounted card as proof that every declared
handler compiled.

Current language boundaries that matter when authoring are:

- a transition has no render row or render stack, so `@binding`, `$method`,
  and `*dynamic` reads are refused there; `@cur` is the transition-owned
  exception;
- `sendAt` accepts literal and parameter keys, but a path whose key is reread
  from live state cannot be represented by the guest ABI and is refused;
- collection mutations use the canonical `push`, `insertAt`, `setAt`,
  `deleteAt`, `add`, `remove`, and `toggle` names; parsed aliases such as
  `clear`, `delete`, `set`, and `removeAt` have no backend behavior;
- a child component is an opaque host-owned instance token, so a card may
  carry, render, and message it but cannot traverse into its fields.

The ahead-of-time MoonBit emitter has a different refusal set. When the same
file must work on both paths, validate both; see
[schema.md](./schema.md#what-the-ahead-of-time-backend-refuses).

## Wax escape hatch

A trusted host may opt into a card's `tutuca/wax` block to implement a refused
or otherwise inexpressible declaration in the language the module itself uses.
This is an advanced escape, not the default authoring surface:

- `allowWax` / `allow_wax` is **off by default** and belongs to the host, not
  the card;
- bind a declaration by defining `card_<role>_<name>` (qualified with the
  component name in a multi-component card); other functions are helpers;
- use the playground's WAX output to copy the generated calling idioms and
  field accessors instead of inventing ABI operations;
- the safety screen accepts functions but refuses imports, memories, data,
  exports, start functions, globals, tables, and runtime-reserved names, so an
  escape cannot add authority;
- an escape is opaque to dependency analysis and therefore widens the card's
  generated import surface to the documented helper vocabulary even when it
  uses only part of it.

Prefer moving to the compiled MoonBit path when hand-written Wax becomes more
than a narrow bridge. Pass `allowWax: true` to `mountCard` or `driveCard` only
when the host explicitly trusts and intends to enable the block.

## Multiple components and children

A card may declare several components. Keep one spec block, qualify each
script block, and qualify template ids:

```html
<script type="tutuca/spec">
  state Todos {
    draft: String, items: Array[Todo]
    property { count: Int { get } }
  }
  state Todo  { text: String, done: Bool }
</script>

<script type="tutuca/script" for="Todos">
  get count { len state.items }
</script>

<script type="tutuca/script" for="Todo">
  receive toggle { .done = not .done }
</script>

<template id="Todos:main" data-root>...</template>
<template id="Todo:main">...</template>
```

The root is the first declared component unless a template has `data-root`.
Scenes may choose another component with their `component` key.

A handler builds a sibling with the same `new` and `@cur` vocabulary used for
records:

```tutuca
receive add {
  new Todo
  @cur.text = .draft
  @cur.done = false
  .items.push @cur
}
```

`new Todo` opens the sibling's argument map; writes to `@cur` fill it; the
first read of `@cur` materializes one child instance. A card carries only the
child token. It cannot read or write through that child, such as
`.items[0].text`; dispatch a message to the child instead.

## State, startup, and fixtures

A card starts from the selected schema or fixture value. `receive init` is not
a lifecycle hook: the host, fixture drive, or scene must send `init`.

Use `tutuca/init` for named, inspectable states and repeatable demonstrations.
Use its drive form when the important state should be reached through real
interactions rather than copied as an opaque value. Use `tutuca/test` for
assertions; fixtures and tests serve different purposes even though both may
drive the component.

## Contracts and failures

Contracts are observable behavior. Give a predicate or invariant a `format`
sentence so a rejected transition explains itself. In a card scene, assert
that output with `expect: log`.

Do not use `refused` as the default card assertion. A card guest normally
answers an unknown receive as `unhandled`, and a host-origin call does not get
the component's internal generated-field fallback; therefore the host often
has no refusal to report. Use `log`
for failed `requires`, `ensures`, and invariants. The distinction and examples
are in [testing.md](./testing.md#assert-on-log-not-just-on-the-dom).

## Styling and embedding

Literal `class` and `:class` values can be collected and compiled with
MargaUI/Tailwind by the embedding host. An `mb-card` host using its `margaui`
option can compile those classes for the preview. Runtime-built class strings
are invisible to the collector, so keep class vocabularies literal or add a
literal decoy view as described in [margaui.md](./margaui.md).

Use card-local style blocks for styles the card owns. Remember that component
CSS scoping and host-global CSS solve different problems; see
[styles.md](./styles.md).

## Validation

Use the card playground for the normal edit loop: it checks and recompiles the
card, remounts the preview, shows state and activity, and runs embedded scenes.
Before handoff:

1. Ensure the checker reports no schema, script, or template issue.
2. Run every `tutuca/test` scene and inspect failures step by step.
3. Assert both visible behavior and settled state. For rejected contract
   transitions, assert `log` so a selector typo cannot look like a valid veto.
4. Exercise every declared component and fixture, not only the root/default.
5. Inspect the mounted card at the intended width/theme, especially when using
   MargaUI or host-provided styles.

The runtime exposes `__tutucard.check(source, name)` for a non-mounting check.
For Node or browser automation, use `driveCard`; it checks, compiles,
instantiates, and drives in one call. Only use the lower-level synchronous
`__tutucard.drive` when the exact compiled guest and its matching manifest are
already mounted under the supplied key. Full scene syntax and APIs are in
[testing.md](./testing.md#testing-a-card-script-typetutucatest).

## Card scene essentials

A scene is a named object with ordered `steps`. It may choose `component`,
`init`, `args`, `intents`, and raw renderer output. Drivers include click,
type, key, check, fire, drag, and root send. Readers include text, texts,
attribute, property, input value, checked state, match count, state, HTML,
render count, log, and refusals.

Selectors are one compound selector: a tag plus `#id`, `.class`, and
`[attribute]` qualifiers. Descendant selectors and selector lists are not
supported. Omit `is` from an expectation to record its current value before
turning the useful observations into assertions.

Read [testing.md](./testing.md#testing-a-card-script-typetutucatest) whenever
you add or review scenes; it is the authoritative field and verb reference.

## Moving between paths

To graduate a card to a compiled Tutuca component, keep the state, script,
templates, fixtures, and styles; add `gen-views`, the MoonBit component/module
wiring, and harness tests. The ahead-of-time emitter reports each script arm it
cannot compile as a named refusal, leaving that behavior for MoonBit instead of
dropping it.

To make a compiled component portable as a card, first remove dependencies on
MoonBit-only handlers and host wiring. Do not assume a successful
`gen-views` build proves the card backend accepts the same surface; check and
run the card itself.

## Related references

- [schema.md](./schema.md) — card language and backend refusal details.
- [events.md](./events.md) — the event data a card can safely read.
- [messages-and-intents.md](./messages-and-intents.md) — communication and
  intent fixtures.
- [testing.md](./testing.md) — complete card scene reference and automation.
- [margaui.md](./margaui.md) — host-compiled utility/component classes.
