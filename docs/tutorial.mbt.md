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

Components never hold references to each other — they communicate by **path**
(`send`, `bubble`, `request`), and events are not wired as DOM listeners:
they are delegated at the root and routed back through the tree.

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

A component is a plain **state struct** plus a call to
`@component.component(...)`: a name, a view (the template string), the
initial state, and typed handler buckets. The MoonBit port of the canonical
counter:

```mbt check
///|
fn counter() -> @component.Component {
  counter_component(
    // views call update by bare name: @on.click="dec". `CounterMsg` is
    // generated from those names, so adding one to the view breaks this match
    // until it is answered.
    update=(s, msg, _ctx) => {
      match CounterMsg::from_dispatch(msg) {
        Some(Inc) => Some({ count: s.count + 1 })
        Some(Dec) => Some({ count: s.count - 1 })
        Some(Unknown(_, _)) | None => None
      }
    },
    // Every handler the views raise is answered here, `inc` included:
    // there is one place for them.
  )
}

///|
/// A ModuleDef bundles components (+ macros + request handlers + examples).
/// One ModuleDef value drives the tests, the storybook gallery and the CLI.
fn counter_module() -> @component.ModuleDef {
  @component.ModuleDef::new(name="counter", components=[counter()])
}
```

Things to notice:

- **The view file declares the state.** `CounterState` is generated from the
  `<script type="tutuca/state">


