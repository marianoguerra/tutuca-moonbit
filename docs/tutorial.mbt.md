# Using tutuca (MoonBit)

This is the MoonBit companion to the JS
[tutuca tutorial](https://marianoguerra.github.io/tutuca/tutorial.html): the
same framework, driven from MoonBit. Views — the HTML-ish template strings —
port **verbatim** from JS; what changes is the code around them: state is a
plain MoonBit struct, and every handler is compiler-checked against it.

Every code block below tagged `mbt check` is compiled and executed by
`moon test docs`, so this document cannot drift from the API.

The examples here build each view inline with `@anode.View::new(raw_view="…")`
and match dispatches as raw `Input(name, args)` strings — the shortest form to
read on one screen, and the escape hatch for genuinely dynamic views. For real
components the recommended path is **ahead-of-time views**: keep the template in
an `.html` file and run `tutuca gen-views`, which compiles it and generates a
typed `<Comp>Msg` so a misspelled or unhandled `@on` handler is a *compile
error* rather than a silent no-op. See the "Views (`views~` + `gen-views`)"
section of the [README](../README.mbt.md), `demo/counterlib/` for the worked
example, and the playground's View tab.

## The mental model

Three rules explain everything else:

1. **State is a single immutable value.** The whole app is one tree of
   `Value`s; component instances are nodes in it.
2. **The view is a pure function of the value.** No subscriptions, no stores,
   no watchers — render the value, get a DOM.
3. **Every handler returns a new state.** An update takes the state struct
   and returns a replacement; the framework swaps it into the tree
   (copy-on-write, so untouched siblings keep their identity) and re-renders
   once per interaction.

Components never hold references to each other — they communicate by **path**:
a `send` addressed to one target, or an `intent` that walks a route until
something answers. Events are not wired as DOM listeners either — they are
delegated at the root and routed back through the tree.

## Notation reference

The template language uses one-character sigils, each mapping to one way of
resolving a name:

| Syntax | Meaning |
|---|---|
| `.name` | a component **field** (single level — no dotted paths) |
| `$name` | a **`mutate`/`compute`** call (or a generated mutator) |
| `name` | an **update** dispatch (bare lowercase name, `Input` bucket) |
| `@name` | a local **binding** from iteration or scope enrichment |
| `^name` | a **macro parameter** |
| `*name` | a **dynamic binding** (provide/lookup) |
| `.seq[.key]` | sequence/map **item access** |
| `'text'`, `$'a {.b} c'` | string literal, string template |
| `truthy? .x`, `equals? .a .b` | predicates (predicate-first): `empty?` / `truthy?` / `falsy?` / `null?` / `equals?` |

## Your first component

A component is a **view file** plus whatever that file cannot state. The file
holds three blocks — the state schema, the behaviour, and the templates — and
`tutuca gen-views` turns all three into `counter_component`, which already
carries the name, the compiled views, the styles, the codec, the schema and the
compiled handlers:

```html
<!-- tutorial.html -->
<script type="tutuca/state">
  state Counter { count : Int }
</script>

<script type="tutuca/script">
  on inc { .count += 1 }
  on dec { .count -= 1 }
</script>

<template id="Counter">
  <div>
    <button class="dec" @on.click="dec">-</button>
    <span class="count" @text=".count"></span>
    <button class="inc" @on.click="inc">+</button>
  </div>
</template>
```

Which leaves the MoonBit port of the canonical counter with nothing to say:

```mbt check
///|
test "the generated counter is a complete component" {
  // Views call update by bare name: @on.click="dec". Both names are answered
  // in the file's `tutuca/script` block, which `gen-views` compiles and
  // composes AHEAD of the `update~` this does not pass.
  //
  // Write a handler that block cannot compile — one that walks a path, or
  // builds a child component — and `gen-views` says which one, by name. That
  // one comes back here as an `update~`, and the rest stay where they are.
  counter_component() |> ignore
}
```

Things to notice:

- **The view file declares the state.** `CounterState` is generated from the
  `<script type="tutuca/state">` block, along with its zero value and its
  codec, so no MoonBit here writes a field list twice.
- **It declares the behaviour too.** A `<script type="tutuca/script">` block
  is checked against that schema — `.count` has to be a field, and `+=` has to
  be arithmetic — and compiled into a match over the same dispatch a
  hand-written arm takes.
- **What is left is what neither block can state.** A seed value, an intent's
  options, a handler that reaches for a path or builds a child: those are
  arguments to `counter_component(...)`, and everything else is the file.
