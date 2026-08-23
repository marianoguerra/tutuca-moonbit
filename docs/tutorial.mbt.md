# Using tutuca (MoonBit)

This document is the MoonBit companion to the JS
[tutuca tutorial](https://marianoguerra.github.io/tutuca/tutorial.html). It
uses the same framework from MoonBit. Views are HTML-like template strings.
They port **verbatim** from JS. The code around them changes: state is a
plain MoonBit struct, and the compiler checks every handler against it.

`moon test docs` compiles and runs every code block below that is tagged
`mbt check`. Thus this document cannot drift from the API.

The examples here build each view inline with `@anode.View::new(raw_view="…")`
and match dispatches as raw `Input(name, args)` strings. This is the shortest
form to read on one screen, and the escape hatch for dynamic views. For real
components, use **ahead-of-time views**: put the template in an `.html` file
and run `tutuca gen-views`. The tool compiles the file and generates a typed
`<Comp>Msg`. A misspelled or unhandled `@on` handler then gives a *compile
error*, not a silent no-op. See the "Views (`views~` + `gen-views`)"
section of the [README](../README.mbt.md), `demo/counterlib/` for the worked
example, and the playground's View tab.

## The mental model

Three rules explain everything else:

1. **State is a single immutable value.** The whole app is one tree of
   `Value`s; component instances are nodes in it.
2. **The view is a pure function of the value.** There are no subscriptions,
   no stores, and no watchers. You render the value, and you get a DOM.
3. **Every handler returns a new state.** An update takes the state struct
   and returns a replacement. The framework puts it into the tree
   (copy-on-write, so untouched siblings keep their identity) and re-renders
   once per interaction.

Components never hold references to each other. They communicate by
**path**: a `send` addressed to one target, or an `intent` that walks a
route until something answers. Events are not wired as DOM listeners either.
They are delegated at the root and routed back through the tree.

## Notation reference

The template language uses one-character sigils. Each sigil maps to one way of resolving a name:

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
holds three blocks: the state schema, the behaviour, and the templates.
`tutuca gen-views` turns all three into `counter_component`. That value
already carries the name, the compiled views, the styles, the codec, the
schema, and the compiled handlers:

```html
<!-- tutorial.html -->
<script type="tutuca/state">
  state Counter { count : Int }
</script>

<script type="tutuca/script">
  receive inc { .count += 1 }
  receive dec { .count -= 1 }
</script>

<template id="Counter">
  <div>
    <button class="dec" @on.click="dec">-</button>
    <span class="count" @text=".count"></span>
    <button class="inc" @on.click="inc">+</button>
  </div>
</template>
```

The MoonBit side of the counter then needs no more code:

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
  `<script type="tutuca/state">` block, together with its zero value and its
  codec. Thus no MoonBit here writes a field list twice.
- **The view file declares the behaviour too.** The checker reads the
  `<script type="tutuca/script">` block against that schema: `.count` has to
  be a field, and `+=` has to be arithmetic. The compiler turns the block
  into a match over the same dispatch that a hand-written arm takes.
- **What is left is what neither block can state.** A seed value, an intent's
  options, and a handler that reaches for a path or builds a child are
  arguments to `counter_component(...)`. Everything else is in the file.
