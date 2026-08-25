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
receive Counter { resetTo(Int) }
</script>
```

One `state` per component, named after the template id it gives views to
(`id="Counter"` → `state Counter`). A file whose templates are unnamed writes a
bare `state { … }`; a file either names every component or none of them,
exactly as its templates do.

Five declaration keywords and no more — `state`, `struct`, `enum`, and the two
message buckets `receive` / `intent`. There is no nesting level
above them: a `<template id>` already says which component a thing belongs to,
so a second place to say it would be a second place to get it wrong. Inside a
`state` body, two SECTIONS say where a value comes from — see *Dynamic
bindings* below.

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
verbatim: `@on.click="removeInItemsAt @key"`, `@on.input="setQuery e.value"`,
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
predicates `empty?`, `truthy?`, `null?` in a conditional slot instead (e.g.
`@hide="empty? .x"`, `@show=".view is 'detail'"`).

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

Two optional variants declare the messages a component receives, beyond the
`@on` handlers its views name. Each generates a typed enum
(`BoardReceive` / `BoardIntent`) that `update` matches:

```html
<script type="tutuca/state">
  state Board { rows: Array[Any], loading: Bool }
  receive Board { reset, focusRow(Int), loadRowsOk(Array[Any]),
                  loadRowsError(String), loadRowsUnhandled }
  intent Board { rowPicked(Int) }
</script>
```

Declare a case the way it is **used**: `focusRow`, not `FocusRow`. The same
name reappears as `receive focusRow(n)` in the script block and as
`send 'focusRow' 3` in a view, and the generator makes the UpperCamel MoonBit
variant (`BoardReceive::FocusRow`) from it — the capital belongs to the
generated code, not to what you write. An UpperCamel declaration still parses,
so old blocks keep working; `gen-views` reports it as a `message-case` warning.

`receive` is what something `send`s to this component **by address**; `intent`
is what reaches it because a walk routed here — a descendant's `intent dyn`, or
an intent that took the default `dyn lex` route. A bucket the component has no
use for is simply absent. What a parent asks of a child goes through `receive`
— a slot is a handle, not a channel.

Note the three `LoadRows…` names in the `receive` list. An intent's **answers**
are ordinary messages, so they are declared where every other message is; and
declaring them is what makes `intent lex 'loadRows'` a *request* rather than a
notification. Nobody writes that down twice — the generator reads this list and
fills the intent's opts in. Channel semantics are in
[messages-and-intents.md](./messages-and-intents.md).

## Dynamic bindings (`provide` / `lookup`)

For passing a value "context-style" to a deep descendant without threading it
through every component in between. Two sections inside a `state` body:

```html
<script type="tutuca/state">
  state Board {
    theme: String
    sheets: Map[String, String]
    selId: String
    slot: Slot
    provide { theme = .theme, sel = .sheets[.selId], Cell = self }
  }
  state Slot {
    made: String
    lookup { theme, color = 'gray', Cell }
  }
</script>
```

```html
<template id="Slot"><em :style="$'color: {*theme}'"></em></template>
```

A **`provide`** publishes a name to the whole subtree below the component,
re-evaluated every time it renders. A lowercase name publishes a VALUE, and its
expression must be **addressable** — `.field` or `.seq[.key]` and nothing else
— because a provide doubles as the path a `<x render="*name">` teleports
through. There is no shorthand for "the field of the same name": write
`theme = .theme`.

A **`lookup`** names what it WANTS, not who supplies it. `theme` is the whole
declaration; `color = 'gray'` adds the fallback used when nothing above
provides it (without one, a miss reads as null). The local name IS the provided
name — there is no alias. Because a lookup does not name its producer, **one
provide name has one producer per scope chain**.

An **uppercase** name publishes a component TYPE rather than a value, and
`self` is the only thing it can be: `Cell = self` injects this component as
`Cell` for its whole subtree, so something below that builds a `Cell` gets this
one rather than whatever is registered under that name. A published type is not
a render target — it has no path, so `<x render="*Cell">` resolves to nothing.

**A handler reads one too.** `*name` in a script block is the same question the
view asks, answered at the same position:

```
receive stamp {
  .label = $'{.label} ({*theme})'
}
```

The host resolves this component's declared lookups before it enters the card
and the handler reads one of the answers — so a `*name` a body writes and a
`*name` a template writes get the same value. A `*name` the `state` block does
not declare is `DYN_NOT_DECLARED`: whether a producer is above you at render
time is a runtime fact, but whether you ever asked for the name is not.

`$name` is still render-only, and for the reason `*name` no longer is: a
`compute` really is the render stack's answer, and a body calls one bare.

The provide/lookup declarations themselves reach the host as source text in the
manifest, and the host evaluates them against the instance while rendering,
exactly as it does for a component written in MoonBit. Only the handler-side
read costs the module an import (`control.lookup`), and only a card that writes
one has it.

`provide` and `lookup` are **not reserved field names** — the section opens on
the word followed by a brace, so `provide: String` is still a field.

Runtime mechanics, and the `dyn`/`lex` routes a handler resolves a name along:
[semantics.md](./semantics.md) *Name lookup*. Authoring the MoonBit side:
[advanced.md](./advanced.md) *Dynamic bindings*.

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

The state block declares no behaviour at all — only data.
`for=` names the component the way a `<template id>` does, and is needed
only in a file that declares more than one.

## The reading vocabulary

The expression language — the block's and a conditional slot's, which are one
language — is **closed**: fifteen builtins and five operator families, and no
way to add a sixteenth. That is what makes it
total, and what lets both backends implement the same thing.

Application is **juxtaposition** and parentheses are required wherever
precedence would otherwise be implicit: `contains (lower .title) (lower q)`.
There is no precedence table to remember and none to get wrong.

| builtin | arity | answers |
| ------- | ----- | ------- |
| `empty?` `truthy?` `null?` | 1 | the shape predicates no operator says — `empty?` is total where `(len x) is 0` is not, and `truthy?` treats an empty collection as falsy where a plain read does not |
| `len` | 1 | the size of a text, list, set or map |
| `has` | 2 | a KEY in a set or map, a VALUE in a list — `has .picked @value` |
| `contains` | 2 | substring, text only |
| `min` `max` | 2 | the smaller / larger number |
| `clamp` | 3 | a number held between two bounds |
| `int` `num` | 1 | a number as a whole / as itself (a CONVERSION, not a coercion of an `Any`) |
| `str` | 1 | any value rendered as text |
| `lower` `upper` `trim` | 1 | the text, folded / trimmed |

The operator families are `and` `or` (chain freely); `is` `is not` `<` `<=`
`>` `>=` (exactly two operands, so `a < b < c` is refused); `implies`
(`a implies b` is `(not a) or b`, the shape most cross-field rules take); `+`
`-`; and `*` `/` `mod`. **Mixing families in one unparenthesized chain is a
parse error**, and the message names the parentheses to add. `not` negates,
and `if c { a } else { b }` is an expression — both arms required, because an
expression has to have a value.

**This table is the CONDITIONAL SLOT's vocabulary too.** `@show`, `@hide` and
`@if.<attr>` parse through the same grammar and resolve against the same
table, so `truthy? .items` cannot mean one thing in a `pred` and another in a
`@show`, and `not (empty? .kind)` is written the same way in both. What a slot
does not take is the half that needs a body: a nested read, an `if`,
arithmetic, and a bare parameter — see
[core.md](./core.md#conditional-display).

`equals?` and `falsy?` are retired: `is` says the first and `not` says the
second, and one meaning keeps one spelling. Both still parse — a compiled
dyncomp bundle carries its view markup as a string and the host parses it at
load time, so a spelling cannot simply be deleted — and `gen-views` hints
where one is left.

## Changing a collection

A collection is changed by a statement that names the place and the operation,
receiver first:

```html
<script type="tutuca/state">
  state Playlist { songs: Array[String], tags: Set[String], by: Map[String, String] }
  receive Playlist { add(String), rename(String), drop(Int), mark(String),
                     credit(String, String) }
</script>

<script type="tutuca/script" for="Playlist">
  receive add(title)   { .songs.push title }
  receive rename(t)    { .songs.setAt 0 t }
  receive drop(i)      { .songs.deleteAt i }
  receive mark(tag)    { .tags.toggle tag }
  receive credit(k, v) { .by.setAt k v }
</script>
```

These mirror the **generated mutators** one for one, with the `In<Field>At`
infix dropped because the receiver is written: `pushInSongs` is `.songs.push`,
`setInSongsAt` is `.songs.setAt`, `toggleInTags` is `.tags.toggle`. One idea,
one spelling, wherever it is written.

| receiver | what it takes |
| -------- | ------------- |
| list `Array[T]` | `push v`, `insertAt i v`, `setAt i v`, `deleteAt i` |
| set `Set[String]` / `Set[Enum]` | `add k`, `remove k`, `toggle k` |
| map `Map[String, V]` | `setAt k v`, `deleteAt k` |

**Use those spellings.** A few aliases parse — `removeAt`, `delete`, `set`,
`clear` — and `gen-views` compiles some of them, but a **card** implements the
canonical names only and refuses the rest with `the interpreter does not
implement it either`. A handler that runs in a card and refuses under
`gen-views`, or the other way round, is a spelling problem and nothing deeper.

An index out of range is a **no-op**, not a crash: `setAt`/`deleteAt` past the
end leave the collection alone, and `insertAt` *at* the length appends, because
inserting at the end is a real answer.

> **A generated mutator is not a handler.** `removeInItemsAt @key`,
> `toggleHideCompleted` and `setQuery e.value` are answered by the RUNTIME from
> the field's declared kind. They are not compiled from the block, so no
> script-refusal can disable one and no `update` arm is needed to keep one
> working — a button wired to a mutator works whatever the block does or does
> not compile. Write a handler only when there is something the mutator does
> not say.

## Building a value (`new <Type>` / `@cur`)

The block language has **no literal for an aggregate** — no list, no map, no
record — because a value there is built by *mutating* it, which is what every
other statement already does. `new <Type>` puts that type's **zero** at the
**active target**, and the statements under it fill it in through `@cur`:

```html
<script type="tutuca/state">
  struct Song { title : String, plays : Int, moods : Array[String] }
  state Playlist {
    draft : String
    songs : Array[Song]
    tags  : Array[String]
  }
  receive Playlist { init }
</script>

<script type="tutuca/script" for="Playlist">
  receive init {
    new Song
    @cur.title = 'Ramble On'
    @cur.plays = 0
    @cur.moods.push 'rock'
    .songs.push @cur
  }

  /// A collection is built the same way and assigned whole.
  receive reset {
    new Array[String]
    @cur.push 'p'
    @cur.push 'q'
    .tags = @cur
  }
</script>
```

- The type is spelled the way the **state block** spells it — `new Song`,
  `new Array[String]`, `new Map[String, Int]` — and has to be one that block
  declares (`struct R { … }` for a record) or a built-in. It shares the name
  table with the state parser, so `new Int16` and `count : Int16` cannot come
  to mean different things.
- A field the build never touches keeps the **type's zero**, so `new Song`
  followed straight by `.songs.push @cur` appends an empty one.
- A `new` **resets** the target. Two records is two `new`s, and the first is
  not disturbed once it has been pushed somewhere.
- A **path into** the target works, so `new Song` then `@cur.moods.push 'rock'`
  fills a list *inside* the record. That is what makes one target enough:
  values are built outside-in.
- `@cur` is a **workbench, never output**. It belongs to the handler that built
  it, is gone when that handler ends, and never reaches a view — a template
  reading `@cur` reads nothing. An `enrich` may not bind the name either
  (`RESERVED_BIND`): an enricher's bindings *become* a view's scope, and the
  target is not something a component may publish.
- It is **checked**: the target's type comes from the `new`, and a path into it
  is walked with the same machinery a state path uses, so `@cur.dnoe` reports
  `Song has no field dnoe` and a `@cur` with no `new` above it is `NO_TARGET`.

`@cur = expr` with **no path** re-points the target at a value that is already
built, which is how you copy a row out, edit it and put it back. Note the
backend limits below before reaching for it.

### What the ahead-of-time backend refuses

A card INTERPRETS the block and has none of the limits below; `gen-views`
COMPILES it into MoonBit and has all of them. Each **refuses the arm** rather
than miscompiling it — it prints
`<Comp>: <name> stays in MoonBit — <why> (script-refusal)`, drops the name
from what the block answers, and leaves it in your `update` match to write in
MoonBit. Nothing breaks silently, but a card that runs is not proof the same
block compiles.

Around `new` / `@cur`: a `new` inside an `if` does not outlive the branch, and
`@cur = expr` needs a `new` in scope above it. Writing or reading **through an
index** — `.songs[i]`, `@cur.moods[0]` — needs a bounds check the backend does
not emit, wherever the place is rooted; the named collection methods
(`setAt` / `deleteAt`) carry their own and are the way to say it.

Elsewhere, three things a body may otherwise say:

- **a path into a binding** — `@value.completed`, which is what a `@when` over
  a list of child component *instances* wants. `@value` whole is fine
  (`lower @value`, `len (str @value)`, `has .picked @value`).
- **`sendAt`** — an addressed send. The position is what the backend does not
  emit; `send` (to self) and `intent` compile.
- **a coercion `num` cannot make** — `num` converts a number, so a number
  arriving inside an `Any` (a file input's metadata `Map`, say) is unpacked in
  MoonBit. `str` renders any value and is not affected.

## Contracts (`requires` / `ensures` / `invariant`)

A `pred` gives a rule about the state a **name**. Where you attach it says
which of the three kinds of rule it is, and the runtime keeps all three:

```html
<script type="tutuca/script" for="Ledger">
  pred canPush { .here > 0 }

  /// A PRECONDITION: asked before the body, against the state as it arrived.
  receive push requires canPush {
    .here -= 1
    .there += 1
  }

  /// A POSTCONDITION: asked after the body, against where it landed.
  receive drain ensures empty {
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
gives — and **reports**. The report is the point: "the transition did not
happen" is invisible on its own, and a contract is where you say which stillness
is a bug. There are two doors and exactly one of them fires: a host that
switched on the refusal channel (below) gets a record, and one that did not gets
the line `@tutuca.warn` has always printed
(`precondition_failed` / `postcondition_failed` / `invariant_failed`) —
redirect `@tutuca.warn_hook` to collect those in a test or route them to an
error pane.

Both backends keep them identically — the card interpreter evaluates the rule,
`gen-views` compiles it into a `guard` in the generated arm, ahead of the
effect queue's flush.

Four things to know about the clauses themselves:

- The clause takes a **name**, and the `pred` it names takes **no arguments**.
  A rule that needs one of the handler's arguments is about that dispatch
  rather than about the component; guard it with `if` inside the body.
- At most one `requires` and one `ensures` per handler. Two rules become one by
  naming their `and`: `pred canMove { canPush and (not .busy) }`.
- Contracts attach to transitions only — `on`, `receive`, `intent`. An `enrich` writes bindings, and a `compute` is a value.
- An `invariant` is a `pred` with a role, so `$conserved` still reads from a
  view and `@when="conserved"` still filters a row. It covers the transitions
  the **block** declares; the generated mutators a component answers by default
  are not among them.

### `format` — what the rule says when it fails

A rule may carry the sentence to say when it does **not** hold. It is an
ordinary expression, almost always a `$'…'` template, evaluated against the
state that was rejected — so the values in it are the ones that made the rule
false:

```html
<script type="tutuca/script" for="Post">
  /// A post needs a title before it can go out.
  pred hasTitle
    format $'Cannot publish "{.slug}": the title is empty.'
  { (trim .title) is not '' }

  receive publish requires hasTitle { .published = true }
</script>
```

- The `///` comment and the `format` do different jobs. The comment says what
  the rule **is**, statically; the format says what went wrong **this time**.
- Describe the FALSE case: a predicate is true when things are fine.
- `pred` and `invariant` only — a `compute` has no false case to describe.
- One per rule, and it answers a string (a bare number is refused with
  `FORMAT_TYPE`; put it in a template).
- A sentence that cannot be evaluated is dropped and the report still fires: a
  refusal that cannot describe itself is still a refusal.

### The refusal channel

Every silent no-op the runtime decides — an unresolvable path, a name nothing
answers, a rule that said no — looks from outside exactly like a handler that
ran and had nothing to do. `@tutuca.on_refusal` is where that distinction goes:

```moonbit nocheck
// nocheck: `post_module` is the reader's own module
let h = @harness.mount(post_module(), "Post")
let refused = @harness.refusals_while(() => h.click(".publish"))
assert_eq(refused[0].code, Precondition)
assert_eq(refused[0].rule, "hasTitle")
assert_eq(refused[0].sentence, "Cannot publish \"draft-2\": the title is empty.")
// …and the state that was rejected, which nothing else can reach
```

- `@tutuca.on_refusal(f)` switches it on and answers the uninstall;
  `@harness.refusals_while(body)` is that pair around one stretch of driving,
  and `@harness.no_refusals(body)` **fails** the test if anything was refused —
  which is what makes a test about a guarded button mean something.
- A `Refusal` carries `code`, `asked`, `rule`, `sentence`, `state` and `path`,
  and `to_line()` renders it. The codes are `PRECONDITION`, `POSTCONDITION`,
  `INVARIANT` (a rule refused it), `NO_HANDLER` (nothing claimed the name) and
  `PATH_UNRESOLVED` (nothing was there).
- **A decline is not a refusal.** An `update` arm answering `None`, and the
  generated mutator behind it, are the intended design and stay quiet.
- One dispatch produces at most one record, and it is off until a host asks —
  a record carries the rejected state, so nothing pays for it until somebody
  wants it.

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
{ "fresh": { "value": { "label": "Counter" } },
  "with-history": { "value": { "count": 3, "history": [1, 2, 3] },
                    "doc": "What it looks like once it has been used." } }
</script>
```

A fixture is an **envelope**: `value` holds the field map, and `doc`, `view`,
`tags`, `default`, `drive` and `intents` sit beside it. Those keys are one level
above the field names — they describe the fixture where the field names describe
the component — so none of them needs a sigil, and none can collide with a
field you declare.

Each `value` is checked against the schema — a fixture setting a field the
schema dropped fails the build — and becomes `CounterState::fresh()` plus a
public `counter_init_args("fresh")` for a ModuleDef example.

`drive` is a list of the steps a `tutuca/test` scene takes, run after the value
is seeded. It is the honest way to write a state a component ARRIVES at:

```html
<script type="tutuca/init">
{ "three rows": {
    "value": {},
    "doc": "A list that has been used, arrived at by using it.",
    "drive": [ { "type": "input.draft", "value": "one" },
               { "click": "button.add" } ] } }
</script>
```

A scene then starts from it by name — `"init": "three rows"` — so a state worth
showing and a state worth testing are written once.

`view` names which of the component's views to show the fixture under, which is
the one thing a value cannot say about itself: a `Todo` has a `main` and a `row`
over the same fields. A name the component does not declare falls back to `main`.

`default: true` marks the fixture a host shows when nothing named one — what a
visitor meets. A card that marks none mounts at the schema's zero; a card that
marks one is met the way its author meant. It is a HOST's question, not a test's:
a `tutuca/test` scene with no `"init"` still starts at the zero, because a
scene's starting point is a thing to write down.

The tutucard playground reads all of this. The **examples** tab edits the block,
and the **Examples** pane beside it mounts every fixture as a live card — seeded
from `value`, driven by `drive`, answered by `intents`, shown under `view`, with
the fixture's name as the title and its `doc` underneath.

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
