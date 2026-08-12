# Tutuca — The State Schema

Read this file when declaring or changing a component's data contract: the
`<script type="tutuca/state">` block, which WIT spelling a field wants, what
mutators a field kind generates, message buckets, slots, and named initial
states.

The schema is the source of truth for a component's state. `gen-views` reads it
and writes the MoonBit state struct, the codec, the descriptor and the typed
message enums; nothing you write restates it. Change a field here, regenerate,
and every read of it in every view and handler is re-checked.

## The block

A view file declares its component's data contract in a small subset of WIT,
alongside the templates that read it:

```html
<script type="tutuca/state">
  interface counter {
    record state {
      label: string,
      count: s32,
      history: list<s32>,
    }
    variant receive { reset-to(s32) }
  }
</script>
```

One `interface` per component, named after the template id it gives views to
(`id="Counter"` → `interface counter`), and exactly one `record state` in each.
No `package` line: the module supplies it.

The schema goes in a `<script>` and not a `<template>`, because script content
is raw text to an HTML parser and template content is markup — a `list<s32>`
inside a template would be read as an `<s32>` element.

## Field types

| you mean | you write |
| -------- | --------- |
| bool | `bool` |
| int | `s8`..`s32`, `u8`..`u32` (each range-checked on decode) |
| float | `f32` / `f64` |
| text | `string`, `char`, or an `enum` |
| list | `list<T>`, `tuple<A, B>` |
| nullable | `option<T>` |
| record / variant | `record R`, `variant V` |
| set, closed members | `flags F` |
| set, open members | `text-set` |
| ordered map | `value-omap`, `text-omap` |
| a child component | the sibling interface's name, `component`, `own<c>`/`borrow<c>`, or a `resource` |
| anything at all | `any`, `values` |

The last four rows are marker names rather than WIT constructs: WIT has no open
type and no user generics, so a set with open membership, an ORDERED map (WIT's
own `map` is unordered by definition) and a child-component slot have no
structural spelling. The marker names are **reserved** — a user type shadowing
`any` would silently change what every `any` in the file means.

`type tags = text-set` is a transparent alias: the field gets the marker's type,
not a nominal type of its own.

`values` is exactly `list<any>` — the spelling for a heterogeneous list, most
often a list of component instances:

```html
<script type="tutuca/state">
  interface items {
    record state { items: values }
  }
</script>
```

generates `items : Array[@tutuca.Value]`. Iterate it with
`<div @each=".items"><x render-it></x></div>` and append instances with
`Some({ items: s.items + [item.make(Map([]))] })` (the complete pairing is in
[patterns/todo-list.md](./patterns/todo-list.md)). When every element has one
known shape, prefer `list<T>` — the reads stay typed and the views are checked
against the element schema. `any` is the scalar counterpart: one
`@tutuca.Value` field.

**Out of the subset**, each with its own message: `s64`/`u64` (state travels as
JSON, where integers past 2^53 lose precision), `result`, `future`, `stream`,
`world`s, and a `func` declared as a **method on a resource** (a method belongs
to the component, not to a handle). `map<K, V>` is real WIT but the parser does
not carry it yet.

## What each field kind generates

Every declared field becomes a struct field of the generated state type, and
the field's **kind** decides which camelCase mutators come with it. The
generated names keep their **JS spelling** — that is what makes views port
verbatim: `@on.click="removeInItemsAt @key"`, `@on.input="setQuery value"`,
`@on.click="toggleView"` all call generated mutators.

| Field kind | MoonBit type | Extra auto-generated mutators (for field `x`) |
| ---------- | ------------ | --------------------------------------------- |
| text | `String` | — |
| int / float | `Int` / `Double` | — |
| bool | `Bool` | `toggleX` |
| any | `@tutuca.Value` | — (`Null`, instances, `Fn`s, heterogeneous data) |
| list | `Array[...]` | `pushInX`, `insertInXAt`, `setInXAt`, `deleteInXAt`/`removeInXAt` |
| map / omap | `Map[String, ...]` | `setInXAt`, `deleteInXAt`/`removeInXAt` |
| set (`text-set`, `flags`) | `Map[String, Bool]` | `addInX`, `deleteInX`/`removeInX`, `hasInX`, `toggleInX` (Map-backed: member → `Bool(true)`) |
| comp | `@tutuca.Value` | — a slot, filled through the scope at `make()` (see [Slots](#slots)) |

**Every** field additionally gets `setX`, `resetX`, and `xLen` (`Null` for
non-sized values). A `compute` entry of the same name wins over the generated
one.

There is deliberately **no `updateX`** and no `updateInXAt`. Both would take a
function value and apply it to the current one, and a view can write values but
never a lambda — so no template could ever call either. Transforming a value in
place is what the handler language is for.

Emptiness / truthiness / null checks are not generated — use the boolean
predicates `empty?`, `truthy?`, `falsy?`, `null?`, `equals?` in a conditional
slot instead (e.g. `@hide="empty? .x"`, `@show="equals? .view 'detail'"`).

> **The kind is declared, not chosen at the call site.** There is no way for a
> `component()` caller to say a field is a set when the schema says it is a map:
> the kind is a projection of the declared type
> (`component/component.mbt:158-172`). Change the spelling in the schema.

A field that can hold "anything" is declared `any` — the dynamic escape hatch
inside an otherwise typed struct. That includes fields holding component
instances or `Fn` values: they survive state updates losslessly.

## Slots

A child-component field is a **slot**. It becomes a struct field typed
`@tutuca.Value` — `Null` in `zero()` — and the runtime fills it by creating the
child **through the registration scope** at `make()` time, so forward references
work by name (`component/component_test.mbt:418`):

```html
<script type="tutuca/state">
  interface board {
    record state {
      title: string,
      editor: sheet,          // a sibling interface in this file
      preview: component,     // any component, resolved by slots~
      remote: legend,         // declared below as a resource
    }
    resource legend {}
  }
  interface sheet {
    record state { text: string }
  }
</script>
```

A method-less `resource` names a component this file does **not** declare — one
from another module. A sibling interface is the better answer when there is one.
`own<c>` / `borrow<c>` reach the same place as the bare name and read worse.

The one thing no type can state is the child's **construction arguments**, and
that is all `slot_args~` carries:

```moonbit nocheck
// nocheck: a parameter list, not a compilable item
board_component(
  slot_args={ "editor": { "text": Str("draft") } },
  update=(s, msg, _ctx) => ...,
)
```

There is no `specs~` parameter and no `FieldSpec` type. Both were removed once
the schema became the single source of kinds and slot component names; only
`slot_args~` survived (`component/component.mbt:158-172`).

`slots~` names a slot the **schema could not name**, in either of the two ways it
can fail to:

- **the schema does not declare the field at all** — several components share one
  state type and hold different children. A view file gives each component its own
  interface and so never needs this; a component built by hand does.
- **the schema declares it as the bare `component` marker** — "a component slot"
  without saying which. The usual reason is a name kebab-case cannot round-trip
  (`DnDExample` → `d-n-d-example` → `DNDExample`), so the block cannot spell it:

  ```html
  record state { dnd: component }
  ```
  ```moonbit nocheck
  // nocheck: one bucket argument, not a compilable item
  slots={ "dnd": "DnDExample" }
  ```

Either way the name is folded **into** the schema, so the descriptor still
describes every field an instance has — which is what the inspector and
structural equality read.

> **A slot the schema NAMES is not overridable.** With `editor: sheet` declared,
> `slots={ "editor": "Other" }` is ignored and the slot still holds a `Sheet`:
> a caller contradicting a declared type would leave every reader of the
> descriptor disagreeing with the block
> (`component/component.mbt:173-200`). Change the spelling in the schema.

## Message buckets

Three optional variants declare the messages a component receives, beyond the
`@on` handlers its views name. Each generates a typed enum
(`CounterReceive` / `CounterBubble` / `CounterResponse`) that `update` matches:

```html
<script type="tutuca/state">
  interface board {
    record state { rows: values, loading: bool }
    variant receive { reset, focus-row(s32) }
    variant bubble { row-picked(s32) }
    variant response { load-rows(values) }
  }
</script>
```

`receive` is what a parent or sibling `send`s; `bubble` what a child raises;
`response` what a request resolves to. A bucket the component has no use for is
simply absent. What a parent asks of a child goes through `receive` — a slot is
a handle, not a channel. Channel semantics are in
[request-response.md](./request-response.md).

## Declared methods (`$`-callables)

A freestanding `func` names a method the MoonBit `compute` bucket has to answer:

```html
<script type="tutuca/state">
  interface counter {
    record state { count: s32 }
    summary: func() -> string;
  }
</script>
```

State is still data — this puts no behavior in the block. It names the method,
which is the only way to type a `$`-callable **no view of this component calls**
(the bucket enums are otherwise built from the names the views reference, so a
method nothing calls has no constructor). Views calling `$summary` would declare
it implicitly; declaring it here is for the callable that only code uses.

## Schema without templates

A file may carry a schema and **no** `<template>` at all. That is how a
component whose views are built in MoonBit — a macro user, a dynamically
assembled tree — still gets a generated state type: the schema lives in a view
file, so it needs a view file even when it has no views. Such a file emits the
state half only, and no view surface.

The same applies per interface: one file may give templates to some components
and declare state alone for others. `gen-views` reports the latter as
`state-without-views (hint)` rather than an error, since it is also what a
mistyped interface name looks like.

A component with **no schema block** gets the view half only — no state type, no
codec, no descriptor, and no checked reads. There is no weaker substitute; the
answer to a file without one is to declare the schema.

## Named initial states

Named initial states go in a block of their own, because a default is a value
and not a type:

```html
<script type="tutuca/init">
{ "fresh": { "label": "Counter" },
  "with-history": { "count": 3, "history": [1, 2, 3] } }
</script>
```

Each is checked against the schema — a fixture setting a field the schema
dropped fails the build — and becomes `CounterState::fresh()` plus a public
`counter_init_args("fresh")` for a ModuleDef example.

## Constraints (dynamic components only)

A compiled-in component states its bounds in MoonBit. A **dynamic component**
states them in `manifest.json`, in a `constraint` object beside each field —
the half a type cannot say. The host validates against it, generates the form
control from it, and projects it into the JSON Schema an agent reads.

```json
{ "name": "email", "ty": 0, "required": true,
  "constraint": { "maxLen": 254, "format": "email" } }
```

| key | means | applies to |
| --- | --- | --- |
| `min` / `max` | magnitude | numbers only |
| `minLen` / `maxLen` | characters on text, elements on a collection | text, lists, maps, sets |
| `pattern` | a regular expression the value must match | text |
| `format` | a JSON Schema format (`email`, `uri`, `date-time`, …) | text |
| `enumJson` | the allowed values, as a JSON array in a string | any |
| `defaultJson` | what a form pre-fills, as JSON in a string | any |

**Write only the keys you mean.** "Not stated" has two spellings in one object,
because the record mirrors WIT: `null` (or leaving the key out) for the four
bounds, which are `option<f64>` / `option<u32>`, and `""` for the four strings.
Four of the six are safe to write blank, which is exactly what makes the other
two a trap:

```json
"constraint": { "min": 0, "max": 0, "maxLen": 0, "pattern": "", "format": "" }
```

Three of those are blanks and three are **stated bounds**. `"maxLen": 0` forbids
every value — the form shows `≤ 0 chars` and Apply refuses the whole submission,
including the fields that were fine. `"min": 0, "max": 0` pins a number to
exactly zero, and on a field that is not a number it does nothing at all except
mislead every reader of the manifest.

A stated zero is a real bound and the host will not second-guess one. What it
does do is say something when a bound cannot apply to the field's type:

```
INERT_CONSTRAINT (hint) Message.createdAt: 'min' says nothing about
'createdAt', which is string — it is ignored when validating and dropped from
the generated schema; …
```

That arrives in `Bundle::diagnostics()` at load, and a bound the type cannot
carry never reaches the emitted JSON Schema — so an agent generating arguments
is not told a timestamp has a maximum of zero.

`tutuca new-guest` writes `"constraint": null` for a field with nothing to say,
which is the shape to copy.

## See also

- [core.md](./core.md#component-skeleton) — what you write beside the generated
  state: the handler buckets.
- [cli.md](./cli.md#gen-views--ahead-of-time-views) — running `gen-views`, and
  every diagnostic it can report.
- [patterns/todo-list.md](./patterns/todo-list.md) — a schema, its views and its
  handlers as one worked pair.
