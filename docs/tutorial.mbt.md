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
components, use **ahead-of-time views**: put the view in a `.tutu` file
and run `tutuca gen`. The tool compiles the file and generates a typed
`<Comp>Msg`. A misspelled or unhandled `@on` handler then gives a *compile
error*, not a silent no-op. See the "Views (`views~` + `gen`)"
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
| `.name` | a component **property** (explicit properties win over implicit field properties) |
| `$name args…` | a parameterized **method/compute** call |
| `name` | an **update** dispatch (bare lowercase name, `Input` bucket) |
| `@name` | a local **binding** from iteration or scope enrichment |
| `^name` | a **macro parameter** |
| `*name` | a **dynamic binding** (provide/lookup) |
| `.seq[.key]` | sequence/map **item access** |
| `'text'`, `$'a {.b} c'` | string literal, string template |
| `truthy? .x`, `.a is .b` | one expression, the same language a `pred` body takes: the shape predicates `empty?` / `truthy?` / `null?`, the operators (`not` `and` `or` `is` `<` `<=` `>` `>=` `implies`) and the reading builtins |

Event attributes may instead contain a direct property action:
`.name = e.value`, `.open = not .open`, `.items.removeAt @key`, or
`.selection = default`. These are synchronous writes, not update messages.

## Your first component

A component is a **view file** plus whatever that file cannot state. The file
holds three sections: `spec:` (what it is), `logic:` (what it does) and
`view:` (how it draws). `tutuca gen` turns all three into `counter_component`. That value
already carries the name, the compiled views, the styles, the codec, the
schema, and the compiled handlers:

```
# tutorial.tutu
spec:
  Counter:
    field count :: Int

    message inc
    message dec

logic:
  Counter:
    receive inc:
      it.count += 1

    receive dec:
      it.count -= 1

view:
  Counter:
    @div{
      @button(~class: "dec", ~on_click: dec){-}
      @span(~class: "count"){@(it.count)}
      @button(~class: "inc", ~on_click: inc){+}
    }
```

The MoonBit side of the counter then needs no more code:

```mbt check
///|
test "the generated counter is a complete component" {
  // Views call update by bare name: `~on_click: dec`. Both names are answered
  // in the file's `logic:` section, which `gen` compiles and composes AHEAD
  // of the `update~` this does not pass.
  //
  // Write a handler that section cannot compile — one that walks a path, or
  // builds a child component — and `gen` says which one, by name. That
  // one comes back here as an `update~`, and the rest stay where they are.
  counter_component() |> ignore
}
```

Things to notice:

- **The view file declares the state.** `CounterState` is generated from the
  `spec:` section, together with its zero value and its codec. Thus no MoonBit
  here writes a field list twice.
- **The view file declares the behaviour too.** The checker reads the
  `logic:` section against that spec: `it.count` has to be a field, and `+=`
  has to be arithmetic. The compiler turns the section into a match over the
  same dispatch that a hand-written arm takes.
- **What is left is what neither section can state.** A seed value, an intent's
  options, and a handler that reaches for a path or builds a child are
  arguments to `counter_component(...)`. Everything else is in the file.
