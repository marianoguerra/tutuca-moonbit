# Tutuca — The Component Spec

Read this file when declaring or changing what a component IS: the
`spec:` section — how a field's type is spelled, what
mutators a field kind generates, handle/express surfaces, slots, named initial
states, and the `pred`s and `invariant`s the component keeps.

The spec is the source of truth for a component's state. `gen` reads it
and writes the MoonBit state struct, the codec, the descriptor and the typed
message enums; nothing you write restates it. Change a field here, regenerate,
and every read of it in every view and handler is re-checked.

## The two blocks

The split is what a reader can rely on: the **spec** block says what the
component is, the **script** block says what it does. Read the first and you
know the component's shape, its channels, its wiring and its rules without
reading a handler.

| Spec block (`spec:`) | Script block (`logic:`) |
| --- | --- |
| `state`, `struct`, `enum`, `property` — data and private-by-default abstract state | `receive`, `intent`, property `get`/`set` — the transitions |
| `protocol`, `implements`, `handle`, `express` — the boundary | `enrich`, `enrich-scope` — render-time bindings |
| `provide` / `lookup` — the wiring | parameterized `compute` — a `name(args…)` a view calls |
| `pred`, `invariant` — the rules it keeps | — |
| `where` — the domains its fields are drawn from | — |

A `where` sits beside them because it is the same kind of statement about the
state, narrowed to one field — and because it is the half a generator can read
BACKWARDS, which is what separates it from a rule. See *Field domains* below.

A rule sits in `spec:` because it has no statements, no effects and no
arguments: it is a fact about the state, not a step. A `compute` stays in the
`logic:` section because it is not declared to answer yes or no — and so does a
`pred` that takes an argument or reads the loop binder, which is a render-time filter
about one row rather than a rule about the component.

## The block

A view file declares its component's data contract in a small language that
spells its types the way MoonBit does, alongside the templates that read it:
```tutu
spec:
  Counter:
    field label :: String
    field count :: Int
    field history :: List.of(Int)

    message reset_to(Int)
```

One `state` per component, named after the template id it gives views to
(`id="Counter"` → `state Counter`). A file whose templates are unnamed writes a
bare `state { … }`; a file either names every component or none of them,
exactly as its templates do.

Top-level declarations include `state`, `struct`, `enum`, `protocol`,
`import protocol`, `handle`, and `express`. The last two name the component
whose implicit protocol they describe. A named component may also declare
`implements` on its `state`; see [protocols.md](./protocols.md). Inside a
`state` body, sections say how protocol properties, views, and dynamic bindings
are implemented — see *Dynamic bindings* below.

The schema goes in a `spec:` section and not a `view:` one, because script content
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
| a child component | `Instance`, `Instance.of(Sibling)`, or `Instance.of(P)` / `Instance.of(P && Q)` for a protocol constraint |
| anything at all | `Any`, `Array[Any]` |

The builtin names are **reserved** — a user type called `Any` would silently
change what every `Any` in the file means.

An open set and a closed one share one runtime shape (`Map[String, Bool]`) and
one spelling: `Set[String]` says any string is a member, `Set[Visibility]` says
the members are that enum's cases. The container decides the zero — a set starts
EMPTY — and the enum decides the membership, which is one idea in each place.

A list of child components is written with the ELEMENT's name, and a sibling
`state` is a name a field may use:

```tutu
spec:
  Item:
    field completed :: Bool
    field text :: String

  Items:
    field items :: List.of(Instance.of(Item))
```

Iterate it with `each(value, key in it.items){render(value)}` and append
instances with `Some({ items: s.items + [item.make(Map([]))] })` (the complete
pairing is in [patterns/todo-list.md](./patterns/todo-list.md)). `Array[Item]`
and `Array[Any]` generate the SAME field — `items : Array[@tutuca.Value]` —
so the element type costs nothing at runtime and buys the check: the `each`
body is read against `Item`'s schema, and `@value.txet` is caught. A component
from another file is `List.of(Instance.of(Item))`; a list of components whose
shapes genuinely differ is `List.of(Instance)`.

`Array[Any]` is the last resort, for a list whose elements are not even all
components — a decoded JSON payload, say. `Any` is its scalar counterpart: one
`@tutuca.Value` field. Before reaching for either, check whether the value is
really a `T?` (absent), a `struct` (a record with known fields), or a
`Map[String, V]`.

**Refused, each with its own message**: `Int64`/`UInt64` (state travels as JSON,
where a number is a Double and whole values above 2^53 do not survive the trip —
carry one as a `String`), a `Map` keyed by anything but `String` (a JSON
object's key is a string), and a type that contains itself with no `?` or
`Array` in between (it has no size and no zero).

Behaviour is not declared here. A parameterized observation is still a method:
declare it as `compute name(args…)` and call it with `name(…)`. Predicates and
invariants remain named boolean rules because contracts attach to them.
A zero-argument derivation that depends on render context (the loop binder, an
enriched binding, or `*lookup`) also remains a `compute`: its answer belongs to
one render position, not to the component as an independently readable member.
Semantic commands, messages/intents, and asynchronous work remain handlers.

## Properties

Properties are the component's unified member model. A state field is an
implicit private read/write property. An explicit property can derive its
value, redirect a write, or do both. Properties are private by default; add
`pub` only when a parent, host, storybook, or property fuzzer may drive it:

```tutu
spec:
  Counter:
    field count :: Int

    property count :: Int ~public:
      get: it.count
      set: it.count

    property magnitude :: Int ~public

    property label :: String

logic:
  Counter:
    property magnitude :: Int:
      get: if (it.count < 0) | -it.count | it.count
      set:
        if (it.count < 0)
        | it.count := -value
        | it.count := value

    property label :: String:
      get: @str{count: @(it.count)}
```

The compact form names a backing field after `get` or `set`; its type must
match the property type. Bare `get` / `set` opt into a script implementation.
Those implementations have fixed signatures: a getter returns the declared
property type and a setter receives one implicit `value` of that type. There is
no argument list to declare and no overload surface to keep in sync.

Every property is readable. Writing is opt-in: omit `set` for a read-only
property. Visibility is independent: `label` above is a private read-only
property, while `count` and `magnitude` are public. A complex setter is a
synchronous, pure, atomic state transition. It
may update several internal fields and its successor must satisfy the same
domains, predicates, and invariants as any handler result, but it cannot send,
raise an intent, construct a component, or enqueue another transaction. A
refusal changes nothing. `Transactor::set_property(path, name, value)` also
works through a child path and rebuilds the parent spine in the current
transaction, so do not add a message merely to expose a synchronous value
assignment.

Protocols use the same abstract surface without implementation details:

```text
protocol Adjustable = "example/Adjustable@1" {
  property { value: Int set, label: String }
}
```

An implementing state binds those names in its `property` section. Public
fuzzing derives writes only from properties marked `pub`. A protocol binding
may expose a private local property under the protocol's public member name.

Views read properties with `it.name`; an explicit property wins over a same-named
field. Inside script bodies, use `state.name` when the raw stored field is what
you mean. The legacy `it.name` spelling in a script body remains the canonical
printed form for raw state, but new code should prefer `state.name` wherever a
same-named property could make the distinction unclear.

## Property actions in views

An event can update an implicit or explicit writable property directly. These
are synchronous property transitions, not messages, so they do not add cases
to the generated input enum:

```tutu
spec:
  Actions:
    field query :: String
    field open :: Bool
    field selection :: String
    field items :: List.of(String)
    field tags :: Set.of(String)

view:
  Actions:
    input(value: it.query, ~on_input: it.query := e.value)
    button(~on_click: it.open := !it.open):
      "toggle"
    button(~on_click: it.selection := default):
      "clear"
    each(value, key in it.items):
      div():
        button(~on_click: it.items.delete_at(key)):
          "remove"
        button(~on_click: it.tags.toggle(value)):
          "tag"
```

The field's **kind** decides which operations are valid:

| Field kind | MoonBit type | Property operations |
| ---------- | ------------ | ------------------- |
| scalar / record / component | the declared type | assignment, `:= default` |
| bool | `Bool` | assignment; toggle with `it.x := !it.x` |
| list | `Array[...]` | `push`, `insert_at`, `set_at`, `delete_at`, `clear` |
| map / omap | `Map[String, ...]` | `set_at`, `delete_at` |
| set | `Set[String]`, `Set[Enum]` | `add`, `remove`, `toggle` |
| nullable | `T?` | assignment; `:= default` writes `None` |

`= default` writes the declared type's zero. For a nullable property that is
`None`; it is not an empty string. Collection operations are atomic and retain
the existing no-op rules for missing keys or out-of-range positions.

The runtime may implement these operations with a generated table, but names
such as `setX`, `resetX`, `toggleX`, and `removeInXAt` are not language or
manifest surface. Do not dispatch or document them. Code that needs to perform
an externally callable semantic action declares a message; code that needs to
expose synchronous abstract state declares a `pub` property.

There is deliberately **no `updateX`** and no `updateInXAt`. Both would take a
function value and apply it to the current one, and a view can write values but
never a lambda — so no template could ever call either. Transforming a value in
place is what the handler language is for.

Emptiness / truthiness / null checks are not generated — use the boolean
predicates `empty?`, `truthy?`, `null?` in a conditional slot instead (e.g.
`hide(it.x.is_empty())`, `show(it.view == "detail")`).

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

```tutu
spec:
  Board:
    field title :: String
    field editor :: Instance.of(Sheet)  // a sibling component in this file
    field preview :: Instance           // a slot, resolved by `slots~`
    field remote :: Instance.of(Legend) // a component from another module

  Sheet:
    field text :: String
```

`Instance.of(Legend)` names a component this file does **not** declare — one
from another module, resolved through the registration scope at make time — or
a PROTOCOL, where the file declares one under that name. A sibling component is
the better answer when there is one.

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

## Handle and express surfaces

`handle` declares the messages and intents a component accepts, beyond the
`@on` handlers its views name. Its two sections generate typed enums
(`BoardReceive` / `BoardIntent`) that `update` matches. `express` is the dual:
it declares messages and intents that the component may initiate.

```tutu
spec:
  Board:
    field rows :: List.of(Any)
    field loading :: Bool

    message reset

    message focus_row(Int)

    message load_rows_ok(List.of(Any))

    message load_rows_failed(String)

    message load_rows_unhandled

    intent row_picked(Int)

    express intent save_rows
```

Declare a case the way it is **used**: `focusRow`, not `FocusRow`. The same
name reappears as `receive focusRow(n)` in `logic:`. A deliberately
raw outbound name is quoted (`send("focus_row", 3)`); an operation declared in
`express` is unquoted (`intent save_rows`). The generator makes the UpperCamel
MoonBit variant (`BoardReceive::FocusRow`) from it — the capital belongs to
the generated code, not to what you write. An UpperCamel declaration still
parses, but `gen` reports it as a `message-case` warning.

`message` is what something `send`s to this component **by address**; `intent`
is what reaches it because a walk routed here — a descendant's `ask(~route: dyn)`, or
an intent that took the default `dyn lex` route. A bucket the component has no
use for is simply absent. What a parent asks of a child goes through `receive`
— a slot is a handle, not a channel.

A declared payload is **decoded at the boundary**, at the type it names —
the same codec a field of that type goes through, so `loadRowsOk(Array[Row])`
hands the arm an `Array[BoardRow]` rather than a `@tutuca.Value` to unpack.
The types are the field types: scalars, `Array[T]`, `Map[String, V]`, a
`struct`, an `enum`, a `T?`, a tuple. `Any` and `Component` stay
`@tutuca.Value`, because that is what they declare.

A dispatch whose arguments do not fit falls into `Unknown` — never coerced —
**and is reported** as `BAD_PAYLOAD` on the refusal channel, carrying the
argument list that did not fit. Declaring `focusRow(Int)` and sending it a
string is a bug in the sender, and the report is what tells it apart from a
name nobody sent. `Any` buys silence here, which is a reason to declare the
shape you mean.

Note the three `LoadRows…` names in the `message` list. An intent's **answers**
are ordinary messages, so they are declared where every other message is; and
declaring them is what makes `ask("load_rows", ~route: lex)` a *request* rather than a
notification. Nobody writes that down twice — the generator reads this list and
fills the intent's opts in. Channel semantics are in
[messages-and-intents.md](./messages-and-intents.md).
Named and implicit component contracts are in [protocols.md](./protocols.md).

## Dynamic bindings (`provide` / `lookup`)

For passing a value "context-style" to a deep descendant without threading it
through every component in between. Two sections inside a `state` body:

```tutu
spec:
  Board:
    field theme :: String
    field sheets :: Map.of(String, String)
    field sel_id :: String
    field slot :: Instance.of(Slot)

    provide theme = it.theme
    provide sel = it.sheets[it.sel_id]
    provide Cell = self

  Slot:
    field made :: String

    lookup theme
    lookup color = "gray"
    lookup Cell
```

```tutu
view:
  Slot:
    em(style: @str{color: @(dyn.theme)})
```

A **`provide`** publishes a name to the whole subtree below the component,
re-evaluated every time it renders. A lowercase name publishes a VALUE, and its
expression must be **addressable** — `it.field` or `it.seq[key]` and nothing else
— because a provide doubles as the path a `render(dyn.name)` resumes
through. There is no shorthand for "the field of the same name": write
`theme = it.theme`.

A **`lookup`** names what it WANTS, not who supplies it. `theme` is the whole
declaration; `color = "gray"` adds the fallback used when nothing above
provides it (without one, a miss reads as null). The local name IS the provided
name — there is no alias. Multiple providers may use the same name; the nearest
one in the live render ancestry shadows the others.

An **uppercase** name publishes a component TYPE rather than a value, and
`self` is the only thing it can be: `Cell = self` injects this component as
`Cell` for its whole subtree, so something below that builds a `Cell` gets this
one rather than whatever is registered under that name. A published type is not
a render target — it has no path, so `render(dyn.Cell)` resolves to nothing.

**A body reads one too — any body, in either block.** `dyn.<name>` is the same
question the view asks, answered at the same position, whether the body is a
transition, a value, or a rule:

```tutu
spec:
  Card:
    field label :: String
    field accent :: String

    message stamp

    lookup theme

    pred on_brand: it.accent == dyn.theme

logic:
  Card:
    receive stamp:
      it.label := @str{@(it.label) (@(dyn.theme))}

    compute theme_label: dyn.theme
```

A transition is answered from its DISPATCH position, along the same `dyn`/`lex`
route an intent walks. A `compute`, a `pred`, a `~when` and an `enrich` are
answered from their RENDER position — they are called while the view is being
built, so the render stack is what has the answer, and it is the same stack a
`*theme` in a slot beside them reads. Both resolve the same declared `lookup`,
so the two agree.

The host resolves this component's declared lookups before it enters the card
and the body reads one of the answers — from the dispatch position for a
handler, from the render chain for a `compute` / `pred` / `~when` / `enrich`.
So a `dyn.<name>` a body writes and a `dyn.<name>` a template writes get the same value,
in a card exactly as in a MoonBit component. A `dyn.<name>` the `spec:` section does
not declare is `DYN_NOT_DECLARED`: whether a producer is above you at render
time is a runtime fact, but whether you ever asked for the name is not.

`name(…)` is render-only where `dyn.<name>` is not, and the reason is the difference
between them: a `compute` really is the render stack's answer, and a body calls
one bare.

The provide/lookup declarations themselves reach the host as source text in the
manifest, and the host evaluates them against the instance while rendering,
exactly as it does for a component written in MoonBit. Only the handler-side
read costs the module an import (`control.lookup`), and only a card that writes
one has it.

`provide` and `lookup` are **not reserved field names** — a declaration opens
on `field`, so `field provide :: String` is still a field.

Runtime mechanics, and the `dyn`/`lex` routes a handler resolves a name along:
[semantics.md](./semantics.md) *Name lookup*. Authoring the MoonBit side:
[advanced.md](./advanced.md) *Dynamic bindings*.

## Methods no view calls

The bucket enums are built from the names the views reference, so a callable
**no view of this component calls** — a method a PARENT asks of it, say — would
have no constructor. Name it in `logic:`, which is where callables live:

```tutu
logic:
  Entry:
    /// Whether this entry matches a query, for a parent's `@when` filter.
    pred contains_text(q): ((it.title.lower()).contains(q.lower()) || (it.description.lower()).contains(q.lower()))
```

The `spec:` section declares no BEHAVIOUR — no statements and no effects. It does
declare the component's RULES, which are neither: see *Contracts* below.
a `logic:` entry names the component the way a `view:` entry does, and is needed
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

**This table is the CONDITIONAL SLOT's vocabulary too.** `show`, `hide` and
a conditional attribute parse through the same grammar and resolve against the same
table, so `truthy? .items` cannot mean one thing in a `pred` and another in a
`show`, and `not (empty? .kind)` is written the same way in both. What a slot
does not take is the half that needs a body: a nested read, an `if`,
arithmetic, and a bare parameter — see
[core.md](./core.md#conditional-display).

`is` compares and `not` negates, and each meaning keeps one spelling: `is` is
written INFIX (`it.tab == "a"`), `not` in front of its operand.

## Changing a collection

A collection is changed by a statement that names the place and the operation,
receiver first:

```tutu
spec:
  Playlist:
    field songs :: List.of(String)
    field tags :: Set.of(String)
    field by :: Map.of(String, String)

    message add(String)
    message rename(String)
    message drop(Int)
    message mark(String)
    message credit(String, String)

logic:
  Playlist:
    receive add(title):
      it.songs.push(title)

    receive rename(t):
      it.songs.set_at(0, t)

    receive drop(i):
      it.songs.delete_at(i)

    receive mark(tag):
      it.tags.toggle(tag)

    receive credit(k, v):
      it.by.set_at(k, v)

view:
  Playlist:
    ul():
      each(song in it.songs):
        li():
          @(song)
```

These are the same receiver operations available in a view property action.
The receiver is written directly (`it.songs.push`, `it.songs.set_at`,
`it.tags.toggle`), so there is one source spelling in both places.

| receiver | what it takes |
| -------- | ------------- |
| list `List.of(T)` | `push(v)`, `insert_at(i, v)`, `set_at(i, v)`, `delete_at(i)`, `clear()` |
| set `Set.of(String)` / `Set.of(Enum)` | `add(k)`, `remove(k)`, `toggle(k)` |
| map `Map.of(String, V)` | `set_at(k, v)`, `delete_at(k)` |

`clear()` is the list's alone: a list is the one receiver with no other way to
be emptied, since the value language has no list literal to assign instead.

**Those are the only spellings.** There is one name per operation and no
aliases, so a handler either names an operation or names nothing.

An index out of range is a **no-op**, not a crash: `set_at`/`delete_at` past
the end leave the collection alone, and `insert_at` *at* the length appends,
because inserting at the end is a real answer.

> **A property action is not a handler.** `it.items.delete_at(key)`,
> `it.hide_completed := !it.hide_completed`, and `it.query := e.value` are
> resolved from the declared member and field kind. They do not dispatch a
> message and cannot be intercepted by an `update` arm. Write a handler when
> the action has semantic meaning beyond the property operation; mark a
> property `~public` only when an external caller should be allowed to read or
> synchronously set it.

## Building a value

An aggregate is spelled where it is used: the type's name, and its fields
named in parentheses.

```tutu
spec:
  struct Song(title :: String, plays :: Int, moods :: List.of(String))

  Playlist:
    field draft :: String
    field songs :: List.of(Song)
    field tags :: List.of(String)

    message add
    message reset

logic:
  Playlist:
    receive add:
      it.songs.push(Song(title: it.draft, plays: 0))

    /// A collection is emptied and refilled, not assigned.
    receive reset:
      it.tags.clear()
      it.tags.push("p")
      it.tags.push("q")

view:
  Playlist:
    ul():
      each(song in it.songs):
        li():
          @(song.title)
```

- The type is spelled the way the **`spec:` section** spells it — `Song(…)`,
  and it has to be one that section declares (`struct R(…)` for a record) or a
  component in the file. It shares the name table with the spec reader, so
  `Song(…)` and `field songs :: List.of(Song)` cannot come to mean different
  things.
- A field the call does not name keeps the **type's zero**, so `Song(title:
  it.draft)` is a song with no plays and no moods.
- **There is no list or map literal**, so a collection *inside* an aggregate
  cannot be filled in the call — it arrives empty, and a later statement fills
  it through a path (`it.songs[0].moods.push("rock")`) or the field is filled
  before the aggregate is built.
- The call is **checked**: `Song(ttile: …)` reports that `Song` has no field
  `ttile`, from the same declaration the state path walk uses.

### What the ahead-of-time backend refuses

A card compiles the block directly to its component wasm module and supports
the cases below; the ahead-of-time `gen` emitter targets MoonBit and has
these limits. It **refuses the arm** rather than miscompiling it — it prints
`<Comp>: <name> stays in MoonBit — <why> (script-refusal)`, drops the name
from what the block answers, and leaves it in your `update` match to write in
MoonBit. Nothing breaks silently, but a card that runs is not proof the same
block emits to MoonBit.

Writing or reading **through an index** — `it.songs[i]` — needs a bounds check
the backend does not emit, wherever the place is rooted; the named collection
methods (`set_at` / `delete_at`) carry their own and are the way to say it.

Elsewhere, three things a body may otherwise say:

- **a path into a binding** — `@value.completed`, which is what a `~when` over
  a list of child component *instances* wants. the loop binder whole is fine
  (`lower @value`, `len (str @value)`, `has .picked @value`).
- **`send(…, ~to: …)`** — an addressed send. The position is what the backend does not
  emit; `send` (to self) and `intent` compile.
- **a coercion `num` cannot make** — `num` converts a number, so a number
  arriving inside an `Any` (a file input's metadata `Map`, say) is unpacked in
  MoonBit. `str` renders any value and is not affected.

## Field domains (`where`)

A type says `currentIndex` holds an `Int`, which is true and useless. What is
actually true is `0 <= currentIndex < len(items)` — a relation between two
fields, which no type can state. A `where` clause states it:

```tutu
spec:
  Gallery:
    field items :: List.of(String)
    field entries :: Map.of(String, String)
    field current_index :: Int
    field current_key :: String
    field count :: Int

    where it.current_index is_index_of it.items

    where it.current_key is_key_of it.entries

    where it.count >= 0

view:
  Gallery:
    div():
      span():
        @(it.current_index)
      " "
      b():
        @(it.current_key)
```

Several clauses may name one field and they **conjoin** (`where n >= 0` beside
`where n <= 100`). Unlike a rule, a `where` has no name, so there is nothing
for two of them to collide over.

**Prefer the type where the type says it.** `where count >= 0` is already
spelled `count : UInt`, which is checked on decode and needs no clause. Reach
for `where` when the bound is tighter than a width (`between 0 and 100`) or
when the relation mentions another field — which is the case no type covers.

### The vocabulary

It is **closed**, and that is the design rather than a first cut. Every clause
below can be read in two directions: forwards to reject a value, and backwards
to produce one. That second direction is the whole point — see *Why not an
invariant* below.

| you mean | you write |
| -------- | --------- |
| a position in a list | `where i is index of .items` |
| …or nothing selected | `where i is index of .items or none` |
| a key the map holds | `where k is key of .entries` |
| a member of a set | `where t is member of .tags` |
| a set within a set | `where some is subset of .allTags` |
| an ordering, vs. a literal or another field | `where n >= 0`, `where hi >= .lo` (`>=` `>` `<=` `<`) |
| a range, inclusive | `where n between 0 and 100` |
| a closed set of strings | `where level is one of ["debug", "info"]` |
| …or an enum's cases | `where level is one of Priority` |
| …or whatever a sibling list holds | `where value is one of .options` |
| a collection's length | `where items len <= 100`, `where tags len between 1 and 10` |
| never empty | `where items is nonempty` |

Anything outside this list is a `pred` or an `invariant`. A clause the block
cannot state is refused by name, with the vocabulary in the message.

The three list- and set-shaped relations answer three different questions, and
picking the wrong one is the common mistake:

- `is index of .items` — the field stores a POSITION, and the clause bounds it
  by the list's length.
- `is one of .options` — the field stores the VALUE, and the clause bounds it
  by the list's contents. This is a select field: its options are ordered, so
  they are an `Array` rather than a `Set`, and what it keeps is the option
  itself.
- `is member of .tags` — the field stores a member of a `Set`, where order is
  not a fact the collection has.

All three read backwards, which is what a generator needs: a draw for
`is one of .options` comes out of the list, so a run presses values the
component can actually take instead of spending itself on refusals.

### What a `where` does at runtime

Three doors, and they catch different things:

| when | what it covers |
| --- | --- |
| at the field write | the field being written — `it.current_index := 99` is turned down and the instance is unchanged |
| in the arm, before its effects flush | every field, for a handler `logic:` declares — the same place an `invariant`'s guard sits, so an arm that raises effects and then leaves a field out of domain sends nothing |
| after the transition | every field, for every path — a property write, a hand-written `update~` arm — including `it.items.clear()`, which says nothing about `currentIndex` and leaves it stranded |

Any of the three **abandons** the transition and raises a `Refusal` with code
`OUT_OF_RANGE`, carrying the **field** where a rule's refusal carries its name.

The middle door is CALLED rather than compiled, which is the opposite of what
an `invariant`'s guard does and is the point: a rule is an arbitrary
expression the generator has to be able to spell, while a relation is one the
runtime already evaluates at the third door. So the arm emits the declaration
and asks `@tutuca.first_broken_domain`, and the two doors cannot answer
differently.

The third door is the one a hand-written `update~` arm gets, and it has the
limit every rule has there: the successor is checked after the arm returned, so
effects it fired have already gone out. The state rolls back; they do not.

There is no `format`. A rule needs a hand-written sentence because an arbitrary
boolean cannot say why it failed; a relation knows what it wanted and what it
got, so the sentence is composed:

```
`currentIndex` is 99, which is not an index of `items` (3 items)
```

**Unknown is not wrong**, the same rule an invariant follows. A clause whose
target field holds something it cannot read admits the value rather than
refusing it — a partially understood schema must not become a component that
refuses every write.

### Why not an invariant

`invariant in_range: it.current_index >= 0 && it.current_index < items_len()` checks
exactly the same thing, and for checking alone it is the right tool. The
difference is what a **generator** can do with each.

A rule is an arbitrary boolean, so a generator can only filter: draw, ask,
discard. For `0 <= i < len(items)` over a three-element list that lands about
one time in 2^30, so the filter gives up rather than narrowing — and the fuzzer
spends its whole run on states no interaction could reach.

A `where` is a named relation, so the same declaration is a **range to draw
from**. `statedef/arb` draws a constrained field after the fields its domain
names, and every draw is in range. That is the reason the vocabulary is closed:
a relation that cannot be inverted belongs in a rule.

One inference comes free and is worth knowing: `where i is index of .items`
with no `or none` says an index always exists, so the generator never produces
an empty `items`. Write `or none` when the empty list is a real state.

`or none` is about SENTINEL INTEGERS — `-1`, or `0` over an empty list — which
is a convention no type can state, and it is why only `index of` has the
clause. A **nullable** subject needs none of it: every relation reads one shape
and admits anything else, so `sel : String?` under `where sel is key of .byKey`
already means "a key it holds, or nothing selected", and the generator draws
both. Say the absence in the TYPE and the relation follows.

### In a card, and in any dynamic component

A `pred` and an `invariant` are COMPILED INTO a card's wasm module: the card
declines its own transition, before its buffered effects reach the host.

A domain is not compiled in, and cannot be — the vocabulary exists to be read
backwards by a generator and forwards by `core/domain.mbt`, and the guest world
has no shape for either. So the declaration LEAVES the guest: the card compiler
writes it into the bundle manifest (`"domains"` per component) and the host
enforces it, at the two doors the host owns — a property write, and the
successor of a guest transition. The successor is checked
**before** the guest's buffered control calls go out, so nothing is sent for a
transition the host will not adopt.

Two consequences worth knowing:

- A `where` in a card is enforced, and enforced whole — including the
  cross-field relations no per-field constraint could state.
- A host reading a manifest **drops** a relation it does not recognise rather
  than refusing the bundle. A guest built against a later vocabulary still
  mounts; it is simply not held to the clause this host could not read. Unknown
  is not wrong, at the wire as much as at the value.

### What it does NOT do

- **It is not part of the fingerprint.** A domain narrows which values are
  legal; it does not change how a stored one is read. Tightening a `where`
  costs what tightening an `invariant` costs — nothing.
- **A cycle is refused** at build time (`where a >= .b` beside `where b >= .a`),
  because a field is generated after the fields its domain names and a cycle
  has no such order.

## Contracts (`requires` / `ensures` / `invariant`)

A `pred` gives a rule about the state a **name**, and it is declared in the
SPEC block, inside the `state` body it is about. Where you ATTACH it says which
of the three kinds of rule it is, and the runtime keeps all three:

```tutu
spec:
  Ledger:
    field here :: Int
    field there :: Int
    field total :: Int

    pred can_push: (it.here > 0)

    pred empty: (it.here == 0)

    /// An INVARIANT: checked after EVERY dispatch, including the ones written
    /// later that never mention it, and including plain property writes.
    invariant conserved: ((it.here + it.there) == it.total)
```
```tutu
logic:
  Ledger:
    /// A PRECONDITION: asked before the body, against the state as it arrived.
    receive push:
      ~requires: can_push
      it.here -= 1
      it.there += 1

    /// A POSTCONDITION: asked after the body, against where it landed.
    receive drain:
      ~ensures: empty
      it.here := 0
```

**Why the rule and the clause live in different blocks.** The clause is local —
it says when THIS handler applies — so it sits on the handler's header. The
rule is not: `canPush` is a fact about the ledger, `can_push()` reads it from a
view, and an `invariant`'s attachment point is the component itself. Declaring
them beside the fields is what lets a reader learn what a component promises
without opening the handlers.

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

Both backends keep them identically — the card compiler emits the rule into the
component module, while `gen` emits a `guard` in the generated MoonBit
arm, ahead of the effect queue's flush.

Four things to know about the clauses themselves:

- The clause takes a **name**, and the `pred` it names takes **no arguments**.
  A rule that needs one of the handler's arguments is about that dispatch
  rather than about the component; guard it with `if` inside the body.
- At most one `requires` and one `ensures` per handler. Two rules become one by
  naming their `and`: `pred canMove { canPush and (not .busy) }`.
- Contracts attach to transitions only — `on`, `receive`, `intent`. An `enrich` writes bindings, and a `compute` is a value.
- An `invariant` is a `pred` with a role, so `conserved()` still reads from a
  view and `~when="conserved"` still filters a row. It covers **every**
  dispatch, in three degrees:

  | dispatch | when the rule is asked | effects if it fails |
  | --- | --- | --- |
  | a handler `logic:` declares | inline, before the effect queue flushes | never fire — the transition is whole or not at all |
  | a property write (`it.here := 3`, `it.items.push(v)`) | after the successor is built | there are none to fire |
  | a hand-written MoonBit `update~` arm | after the successor is built | **may already have fired** — the state is rolled back, they are not |

  Only the first carries the rule's `format` sentence, because a `format` is
  compiled beside the rule at the moment it fails. The other two report the
  rule's NAME and the state that was rejected.

- **An `invariant` that reads a `dyn.<name>` decides nothing on the two new paths.**
  The runtime asks it after a property write or a hand-written `update~`
  arm, which is not a render position, so a dynamic binding reads null there
  and the rule answers neither true nor false. Unknown is not wrong: the
  transition goes through. Read as `name(…)` from a view it still works
  normally. Keep an invariant on `it.field`s if you want it enforced everywhere.

- **A rule in `spec:` takes no arguments and reads no `@`-binding.** One
  that needs either is about a particular render rather than about the
  component — a `~when` filter over the loop binder, or a `pred containsText(q)` a
  parent calls. Those stay in `logic:`, where the other render-time
  callables are, and a parameterised rule in `spec:` is refused by name.

- **The declared initial states are checked at build time.** Every
  `fixtures:` fixture is asserted against every invariant by a test
  `gen` writes into the generated module — a rule that does not hold in
  the state the component starts in is broken before anything happens. The
  schema's zero is deliberately not checked: a wrapper is normally called with
  `initial~`, which the generator cannot see.

### `format` — what the rule says when it fails

A rule may carry the sentence to say when it does **not** hold. It is an
ordinary expression, almost always a `@str{…}` template, evaluated against the
state that was rejected — so the values in it are the ones that made the rule
false:

```tutu
spec:
  Post:
    field slug :: String
    field title :: String
    field published :: Bool

    /// A post needs a title before it can go out.
    pred has_title:
      ~format: @str{Cannot publish "@(it.slug)": the title is empty.}
      (it.title.trim() != "")
```
```tutu
logic:
  Post:
    receive publish:
      ~requires: has_title
      it.published := true
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
ran and had nothing to do. `@tutuca.on_runtime_notice` is the centralized
channel where that distinction goes:

```moonbit nocheck
// nocheck: `post_module` is the reader's own module
let h = @harness.mount(post_module(), "Post")
let refused = @harness.refusals_while(() => h.click(".publish"))
assert_eq(refused[0].code, Precondition)
assert_eq(refused[0].rule, "hasTitle")
assert_eq(refused[0].sentence, "Cannot publish \"draft-2\": the title is empty.")
// …and the state that was rejected, which nothing else can reach
```

- `@tutuca.on_runtime_notice(f)` switches it on and answers the uninstall;
  refusals arrive as `RuntimeNotice::Refused`, while protocol mismatches use
  `RuntimeNotice::ProtocolMismatch`;
  `@harness.refusals_while(body)` is that pair around one stretch of driving,
  and `@harness.no_refusals(body)` **fails** the test if anything was refused —
  which is what makes a test about a guarded button mean something.
- A `Refusal` carries `code`, `asked`, `rule`, `sentence`, `state` and `path`,
  and `to_line()` renders it. The codes are `PRECONDITION`, `POSTCONDITION`,
  `INVARIANT` (a rule refused it), `NO_HANDLER` (nothing claimed the name),
  `PATH_UNRESOLVED` (nothing was there) and `BAD_PAYLOAD` (the name IS declared
  here and the arguments did not fit what it declares). `BAD_PAYLOAD` is the
  one code whose `state` is not a state: it carries the argument list, because
  no arm ran and that is the thing to go and look at.
- **A decline is not a refusal.** An `update` arm answering `Unchanged` — this
  arm ran and nothing moves — is the intended design and stays quiet.
- One dispatch produces at most one record, and it is off until a host asks —
  a record carries the rejected state, so nothing pays for it until somebody
  wants it.

## Schema without templates

A file may carry a `spec:` section and **no** `view:` section at all. That is how a
component whose views are built in MoonBit — a macro user, a dynamically
assembled tree — still gets a generated state type: the schema lives in a view
file, so it needs a view file even when it has no views. Such a file emits the
state half only, and no view surface.

The same applies per component: one file may give templates to some and declare
state alone for others. `gen` reports the latter as
`state-without-views (hint)` rather than an error, since it is also what a
mistyped component name looks like.

A component with **no schema block** gets the view half only — no state type, no
codec, no descriptor, and no checked reads. There is no weaker substitute; the
answer to a file without one is to declare the schema.

## Named initial states

Named initial states go in a block of their own, because a default is a value
and not a type:

```tutu
fixtures:
  "fresh":
    it.label = "Counter"

  "with-history":
    ~doc: "What it looks like once it has been used."
    it.count = 3
    it.history = [1, 2, 3]
```

A fixture is an **envelope**: `value` holds the field map, and `doc`, `view`,
`tags`, `default`, `drive` and `intents` sit beside it. Those keys are one level
above the field names — they describe the fixture where the field names describe
the component — so none of them needs a sigil, and none can collide with a
field you declare.

Each `value` is checked against the schema — a fixture setting a field the
schema dropped fails the build — and becomes `CounterState::fresh()` plus a
public `counter_init_args("fresh")` for a ModuleDef example.

`drive` is a list of the steps a `tests:` scene takes, run after the value
is seeded. It is the honest way to write a state a component ARRIVES at:

```tutu
fixtures:
  "three rows":
    ~doc: "A list that has been used, arrived at by using it."
    ~drive:
      type("input.draft", "one")
      click("button.add")
```

A scene then starts from it by name — `"init": "three rows"` — so a state worth
showing and a state worth testing are written once.

`view` names which of the component's views to show the fixture under, which is
the one thing a value cannot say about itself: a `Todo` has a `main` and a `row`
over the same fields. A name the component does not declare falls back to `main`.

`default: true` marks the fixture a host shows when nothing named one — what a
visitor meets. A card that marks none mounts at the schema's zero; a card that
marks one is met the way its author meant. It is a HOST's question, not a test's:
a `tests:` scene with no `"init"` still starts at the zero, because a
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

A generator writes `"constraint": null` for a field with nothing to say,
which is the shape to copy.

## See also

- [core.md](./core.md#component-skeleton) — what you write beside the generated
  state: the handler buckets.
- [cli.md](./cli.md#gen--ahead-of-time-views) — running `gen`, and
  every diagnostic it can report.
- [patterns/todo-list.md](./patterns/todo-list.md) — a schema, its views and its
  handlers as one worked pair.
