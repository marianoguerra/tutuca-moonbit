# Tutucard — Single-file Tutuca components

Read this first when the deliverable is a **card**: one HTML file that a page
can check, compile to a wasm module, instantiate, and mount
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

```tutu
spec:
  Counter ~root:
    field count :: Int

    property count :: Int:
      get: it.count
      set: it.count

logic:
  Counter:
    receive inc:
      it.count += 1

    compute label: @str{count: @(it.count)}

view:
  Counter:
    @button(~class: "inc", ~on_click: inc){+}
    @" "
    @output{@(label())}

tests:
  "increments":
    click("button.inc")
    expect text("output") == "count: 1"
    expect state it.count == 1
```

- `spec:` declares components, field types, public properties, records, enums,
  flags, message and intent cases, dynamic `provide`/`lookup`, and the
  `pred` / `invariant` rules the component keeps.
- `logic:` declares receives, derived values, enrichment, intents,
  effects, collection updates, and the `requires` / `ensures` clauses that
  attach a `spec:` rule to one transition.
- `fixtures:` contains named fixtures. A fixture may provide a value, drive
  steps, documentation, and a default marker.
- `tests:` contains named interaction scenes. It is optional but should
  accompany behavior that can regress.
- `view:` renders the component. A card with no `view:` has nothing to
  mount. Styles may be written in the same file or supplied by the host.

For the complete schema and script grammar, read [schema.md](./schema.md).
For `view:` directives, start with [core.md](./core.md#notation-reference)
and load [events.md](./events.md) or [iteration.md](./iteration.md) as needed.

## What cards can express

Cards support the full declared state shapes: scalars, arrays, maps, sets,
options, tuples, records, enums, flags, `Any`, and sibling component slots.
Their handler language covers:

- field and nested collection updates;
- simple field-backed properties and fixed-signature complex property getters/setters;
- `receive`, `compute`, `enrich`, and `bind_with` in `logic:`, and
  `pred` / `invariant` in `spec:` beside the state they are about;
- `requires` and `ensures` clauses attaching one of those rules to a
  transition, with user-facing `format` text on the rule;
- `send`, addressed `send_at`, `intent`, `forward`, `reply`, `fail`, and
  `drop`;
- conditionals, arithmetic, comparisons, string templates, and the closed
  reading vocabulary documented in [schema.md](./schema.md#the-reading-vocabulary);
- constructor calls (`Todo(text: it.draft)`) for declared records and sibling
  component instances.

This is compiled behavior, not an interpreter fallback. The browser compiles
the checked card to a core wasm module — GC types, no component model, no
archive — and the Tutuca host mounts it. The module carries its own manifest,
so the `.wasm` is the whole distribution.

## Limits and refusals

The card compiler rejects a malformed file, but it may **refuse one
declaration** it cannot lower while compiling the rest. Review the build's
`refusals`; a refused handler is absent from the manifest and the host treats
its name as unhandled. Never treat a mounted card as proof that every declared
handler compiled.

Current language boundaries that matter when authoring are:

- a transition has no render row or render stack, so `~binding`, `$method`,
  and `*dynamic` reads are refused there;
- `send_at` accepts literal and parameter keys, but a path whose key is reread
  from live state cannot be represented by the guest ABI and is refused;
- collection mutations are `push`, `insert_at`, `set_at`, `delete_at`,
  `clear`, `add`, `remove`, and `toggle` — one name per operation, and
  `clear` is a list's alone;
- a field declared as a bare `Instance` (or by protocol) is a slot the HOST
  fills: pass an instance in and `@render(…)` draws it, and a list of them
  draws all of them. A card can `send_at` a literal path into such a slot,
  because a message needs an address and the host resolves the path.

The ahead-of-time MoonBit emitter has a different refusal set. When the same
file must work on both paths, validate both; see
[schema.md](./schema.md#what-the-ahead-of-time-backend-refuses).

## Multiple components and children

A card may declare several components. Each section names each component it
speaks about:

```tutu
spec:
  Todos ~root:
    field draft :: String
    field items :: List.of(Instance.of(Todo))
    property count :: Int

  Todo:
    field text :: String
    field done :: Bool
    message toggle

logic:
  Todos:
    property count :: Int:
      get: it.items.length()

  Todo:
    receive toggle:
      it.done := !it.done

view:
  Todos:
    @p{@(it.draft)}

  Todo:
    @p{@(it.text)}
```

The root is the first declared component unless one is marked `~root`.
Scenes may choose another component with their `~component:` option.

A handler builds a sibling the same way it builds a record — the component's
name, and its fields named in parentheses:

```tutu
receive add:
  it.items.push(Todo(text: it.draft, done: false))
```

The call names the sibling's arguments, and pushing it materializes one child
instance — a real instance in the parent's own state, not a token.

## State, startup, and fixtures

A card starts from the selected schema or fixture value. `receive init` is not
a lifecycle hook: the host, fixture drive, or scene must send `init`.

Use `fixtures:` for named, inspectable states and repeatable demonstrations.
Use its `~drive:` form when the important state should be reached through real
interactions rather than copied as an opaque value. Use `tests:` for
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

1. Ensure the checker reports no `spec:`, `logic:`, or `view:` issue.
2. Run every `tests:` scene and inspect failures step by step.
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

To graduate a card to a compiled Tutuca component, keep the file as it is —
same `spec:`, `logic:`, `view:`, `fixtures:` and styles; add `gen`, the
MoonBit component/module
wiring, and harness tests. The ahead-of-time emitter reports each script arm it
cannot compile as a named refusal, leaving that behavior for MoonBit instead of
dropping it.

To make a compiled component portable as a card, first remove dependencies on
MoonBit-only handlers and host wiring. Do not assume a successful
`gen` build proves the card backend accepts the same surface; check and
run the card itself.

## Related references

- [schema.md](./schema.md) — card language and backend refusal details.
- [events.md](./events.md) — the event data a card can safely read.
- [messages-and-intents.md](./messages-and-intents.md) — communication and
  intent fixtures.
- [testing.md](./testing.md) — complete card scene reference and automation.
- [margaui.md](./margaui.md) — host-compiled utility/component classes.
