# Tutuca — The State Schema

Read this file when declaring or changing a component's data contract: the
`<script type="tutuca/state">` block, how a field's type is spelled, what
mutators a field kind generates, message buckets, slots, and named initial
states.

The schema is the source of truth for a component's state. `gen-views` reads it
and writes the MoonBit state struct, the codec, the descriptor and the typed
message enums; nothing you write restates it. Change a field here, regenerate,
and every read of it in every view and handler is re-checked.

## The block

A view file declares its component's data contract in a small language that
spells its types the way MoonBit does, alongside the templates that read it:
```html
<script type="tutuca/state">
  state Counter { label: String, count: Int, history: Array[Int] }
receive Counter { ResetTo(Int) }
</script>
```

One `state` per component, named after the template id it gives views to
(`id="Counter"` → `state Counter`). A file whose templates are unnamed writes a
bare `state { … }`; a file either names every component or none of them,
exactly as its templates do.

Six declaration keywords and no more — `state`, `struct`, `enum`, and the three
message buckets `receive` / `bubble` / `response`. There is no nesting level
above them: a `<template id>` already says which component a thing belongs to,
so a second place to say it would be a second place to get it wrong.

The schema goes in a `<script>` and not a `<template>`, because script content
is raw text to an HTML parser and template content is markup — an `Array[Int]`
inside a template would be read as an `<Int>` element.

## Field types

| you mean | you write |
| -------- | --------- |
| bool | `Bool` |
| int | `Int`, `Int8`, `Int16`, `UInt`, `UInt8`, `UInt16` (each range-checked on decode) |
| float | `Double` |
| text | `String`, or an `enum` |
| list | `Array[T]`, `(A, B)` |
| nullable | `T?` |
| record / variant | `struct R { … }`, `enum V { … }` |
| set, closed members | `Set[E]`, where `E` is an `enum` |
| set, open members | `Set[String]` |
| ordered map | `Map[String, V]` |
| a child component | a sibling `state`'s name, `Component`, or `Component[Name]` |
| anything at all | `Any`, `Array[Any]` |

The builtin names are **reserved** — a user type called `Any` would silently
change what every `Any` in the file means.

An open set and a closed one share one runtime shape (`Map[String, Bool]`) and
one spelling: `Set[String]` says any string is a member, `Set[Visibility]` says
the members are that enum's cases. The container decides the zero — a set starts
EMPTY — and the enum decides the membership, which is one idea in each place.

`Array[Any]` is the spelling for a heterogeneous list, most often a list of
component instances:

```html
<script type="tutuca/state">
  state Items { items: Array[Any] }
</script>
```

generates `items : Array[@tutuca.Value]`. Iterate it with
`<div @each=".items"><x render-it></x></div>` and append instances with
`Some({ items: s.items + [item.make(Map([]))] })` (the complete pairing is in
[patterns/todo-list.md](./patterns/todo-list.md)). When every element has one
known shape, prefer `Array[T]` — the reads stay typed and the views are checked
against the element schema. `Any` is the scalar counterpart: one
`@tutuca.Value` field.

**Refused, each with its own message**: `Int64`/`UInt64` (state travels as JSON,
where a number is a Double and whole values above 2^53 do not survive the trip —
carry one as a `String`), a `Map` keyed by anything but `String` (a JSON
object's key is a string), and a type that contains itself with no `?` or
`Array` in between (it has no size and no zero).

Behaviour is not declared here. A `$`-callable no view of the component names —
a method a PARENT calls, say — is a `pred` or a `compute` in the
`<script type="tutuca/script">` block, beside every other callable.

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
| set (`Set[String]`, `Set[Enum]`) | `Map[String, Bool]` | `addInX`, `deleteInX`/`removeInX`, `hasInX`, `toggleInX` (Map-backed: member → `Bool(true)`) |
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
  state Board {
    title   : String
    editor  : Sheet             // a sibling state in this file
    preview : Component         // a slot, resolved by `slots~`
    remote  : Component[Legend] // a component from another module
  }

  state Sheet { text: String }
</script>
```

`Component[Legend]` names a component this file does **not** declare — one from
another module, resolved through the registration scope at make time. A sibling
`state` is the better answer when there is one.

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
  `state` and so never needs this; a component built by hand does.
- **the schema declares it as the bare `Component`** — "a component slot" without
  saying which, for a child the block has no name to reach:

  ```html
  state Board { dnd: Component }
  ```
  ```moonbit nocheck
  // nocheck: one bucket argument, not a compilable item
  slots={ "dnd": "DnDExample" }
  ```

Either way the name is folded **into** the schema, so the descriptor still
describes every field an instance has — which is what the inspector and
structural equality read.

> **A slot the schema NAMES is not overridable.** With `editor: Sheet` declared,
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
  state Board { rows: Array[Any], loading: Bool }
  receive Board { Reset, FocusRow(Int) }
  bubble Board { RowPicked(Int) }
  response Board { LoadRows(Array[Any]) }
</script>
```

`receive` is what a parent or sibling `send`s; `bubble` what a child raises;
`response` what a request resolves to. A bucket the component has no use for is
simply absent. What a parent asks of a child goes through `receive` — a slot is
a handle, not a channel. Channel semantics are in
[request-response.md](./request-response.md).

## Methods no view calls (`$`-callables)

The bucket enums are built from the names the views reference, so a `$`-callable
**no view of this component calls** — a method a PARENT asks of it, say — would
have no constructor. Name it in the script block, which is where callables live:

```html
<script type="tutuca/script" for="Entry">
  /// Whether this entry matches a query, for a parent's `@when` filter.
  pred containsText(q) {
    ((contains (lower .title) (lower q)) or
     (contains (lower .description) (lower q)))
  }
</script>
```

The state block declares no behaviour at all — it used to carry `func`, which
was the one thing that put a callable in a block whose own header says it holds
data. `for=` names the component the way a `<template id>` does, and is needed
only in a file that declares more than one.

## Contracts (`requires` / `ensures` / `invariant`)

A `pred` gives a rule about the state a **name**. Where you attach it says
which of the three kinds of rule it is, and the runtime keeps all three:

```html
<script type="tutuca/script" for="Ledger">
  pred canPush { .here > 0 }

  /// A PRECONDITION: asked before the body, against the state as it arrived.
  on push requires canPush {
    .here -= 1
    .there += 1
  }

  /// A POSTCONDITION: asked after the body, against where it landed.
  on drain ensures empty {
    .here = 0
  }
  pred empty { .here is 0 }

  /// An INVARIANT: checked after EVERY transition the block declares,
  /// including the ones written later that never mention it.
  invariant conserved { (.here + .there) is .total }
</script>
```

A rule that does not hold **abandons the whole transition** — no successor
state and no effects, which is the answer every other refusal in a body already
gives — and **reports** through `@tutuca.warn`
(`precondition_failed` / `postcondition_failed` / `invariant_failed`). The
report is the point: "the transition did not happen" is invisible on its own,
and a contract is where you say which stillness is a bug. Redirect
`@tutuca.warn_hook` to collect them in a test or route them to an error pane.

Both backends keep them identically — the card interpreter evaluates the rule,
`gen-views` compiles it into a `guard` in the generated arm, ahead of the
effect queue's flush.

Four things to know:

- The clause takes a **name**, and the `pred` it names takes **no arguments**.
  A rule that needs one of the handler's arguments is about that dispatch
  rather than about the component; guard it with `if` inside the body.
- At most one `requires` and one `ensures` per handler. Two rules become one by
  naming their `and`: `pred canMove { canPush and (not .busy) }`.
- Contracts attach to transitions only — `on`, `receive`, `bubble`,
  `response`. An `enrich` writes bindings, and a `compute` is a value.
- An `invariant` is a `pred` with a role, so `$conserved` still reads from a
  view and `@when="conserved"` still filters a row. It covers the transitions
  the **block** declares; the generated mutators a component answers by default
  are not among them.

## Schema without templates

A file may carry a schema and **no** `<template>` at all. That is how a
component whose views are built in MoonBit — a macro user, a dynamically
assembled tree — still gets a generated state type: the schema lives in a view
file, so it needs a view file even when it has no views. Such a file emits the
state half only, and no view surface.

The same applies per component: one file may give templates to some and declare
state alone for others. `gen-views` reports the latter as
`state-without-views (hint)` rather than an error, since it is also what a
mistyped component name looks like.

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
