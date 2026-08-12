# An inline handler language for tutuca views

A small, total expression language written beside the schema in a view file, so
that the simple two thirds of a component's handlers stop being MoonBit
transcription and become something the generator checks and writes.

Companion to [`wax-state-language-design.md`](wax-state-language-design.md),
which replaces the WIT subset in `statedef/` with a language that maps to
wasm-gc. That one is about *how state is declared*; this one is about *how a
handler is written*. They are independent — either can ship without the other —
and §8 notes the one place they meet.

[`predicates-and-invariants-design.md`](predicates-and-invariants-design.md)
builds on this one: it generalizes the conditions below into named predicates and
lets a predicate over state become an enforced invariant. It needs this language
and the state language both, so it comes after either.

## Context

A view file already carries two thirds of a component: the schema
(`<script type="tutuca/state">
`) and its fixtures
(`<script type="tutuca/init">`). Behaviour lives in a `.mbt` file, and across
the corpus most of what lives there is not logic.
Counting the ~196 dispatch arms in non-test code:
| tier | share | what it is |
|---|---|---|
| noise | **~40%** | `Some(SetLabel(_)) \| Some(ResetCount) => None` fall-throughs, and `Some(Unknown(_, _)) \| None => None` catch-alls. Exhaustiveness tax, nothing more. |
| one mutator | ~25% | `Some(OnInput(v)) => Some({ ..s, query: v })` — an existing `setX` / `toggleX` / `pushInX` written out longhand |
| small guarded | ~20% | a clamp, a cycle, a parse-or-keep, a two-field assign, an `if`/`else` |
| genuinely complex | ~15% | `ctx.send_at_path`, `walk_path`, request/response, node-replacing `swap`, dragInfo spelunking, dyncomp lifecycle |
Two thirds of the components in the tree need no `update` at all, because the
generated mutators already answer `setQuery value` and `toggleHideCompleted`
without anyone declaring them. The numbers above are what remains *inside* the
other third.
Three taxes are worth naming, because they are the ones this design removes.
**`inc` and `dec` are hand-written in every counter in the tree.** `updateX`
exists and takes a function value (`component/component.mbt:514-519`), but a
view can only pass values, never a lambda. So there is no mutator that adds one
to a number, and `Some(Inc) => Some({ count: s.count + 1 })` gets written again
in each example, each demo and each playground page.
**Nested mutation has no expression at all.**
`storybook/examples/nested_state.mbt:18-28` spends a whole helper — a guard on
the key's shape, a bounds check, a copy, a field rebuild — to toggle
`labels[i].done`. `Val` spells only `.field` and a one-level `.seq[.key]`
(`core/spec.mbt:49-62`), and no mutator takes a path, so this is the shape of
every nested write in the corpus.
**`MsgDef.payload` is parsed and used by nothing.** `statedef` already carries
full positional argument types for every `receive` / `bubble` / `response` case,
and `viewgen/check_state.mbt` never mentions them. Handler arguments are the one
thing in a view file that is not type-checked: `viewgen/ir.mbt:388-391` emits
them as an untyped array.
And the destination this design builds is one the linter already points at. When
a value slot is given a ternary, a comparison, a logical operator, a
call-with-args or a dotted path, `lint/parse_issue_rules.mbt:250-283` classifies
it and answers with some version of *"define a method on the component, then
reference it as `$name`"*. Today that means: leave the file, write MoonBit,
regenerate. All five messages are pointing at a place that does not exist yet.
## 1. The rule this changes, and the one it keeps
`skill/tutuca/core.md`'s Notation Reference states, today:
> Views are name-based: there is no arithmetic expression syntax in values, and
> no Vue- or Mustache-style `{{ … }}` placeholders. … Logic lives in `update` /
> `compute` / `swap` and the render buckets and is referenced by name; the
> template itself only routes data and events.
**That rule is deliberately retired**, and it is worth being clear that this is a
decision rather than an oversight. It was a good rule while the alternative to a
name was an unchecked string: a view that could compute could compute against
fields nobody verified, in a language nobody could report errors in. That is no
longer the alternative. A body written in a slot is parsed with spans,
type-checked against the schema, and compiled — a `:title="{ .rows[.sel].note }"`
that names a field the schema lacks fails generation, exactly as `.note` does
today.
What the retirement costs is real and is accepted: logic can now hide in a
`:title`, and reading a template no longer tells you where the logic is. §7
records that, and the answer is convention rather than grammar — anything used
twice, or worth a name, belongs in the block.
Two boundaries stay, and neither is a matter of taste:
- **Path-bearing slots take names only.** `@each`, `<x render>`, `<x render-it>`
  and `provide` must yield a `Step` through `Val::to_path_item`
  (`core/value_eval.mbt:278-284`), because dispatch, write-back and key pinning
  address data by position. An expression has no position. A body in one of those
  slots is refused, and the message says why.
- **A value slot is pure.** A body in `@text`, `:attr`, `@show`, `@hide`,
  `@if.<attr>`, `@then` or `@else` is evaluated on every render; it may read and
  compute, and it may not assign or dispatch. It is a `compute` entry written
  where it is used — which is exactly what it compiles to (§5).
## 2. The surface
### 2.1 The block
```html
<script type="tutuca/state">
  state Counter { label: String, count: Int, history: Array[Int] }
receive Counter { ResetTo(Int) }
</script>

<script type="tutuca/handlers">
  on add(d) {
    .count += d
    .history.push .count
  }
  on resetCount      { .count = 0; .history = [] }
  receive resetTo(n) { .count = n; .history.push n }

  compute label      { $'n={.count}' }
  when onlyVisible   { (not .hideCompleted) or (not @value.completed) }
</script>
```

Script content is raw text to an HTML parser, which is why the schema lives in a
`<script>` and not a `<template>` — and it buys the same two things here: `and`
and `<` need no entity escaping, and `viewgen/split.mbt` can slice the block out
of the original source with a line map, so **every declaration carries a real
span**. The WIT block cannot do this (`DefError::locus()` returns an identifier
to grep for, and `viewgen/split.mbt:487-560` scans the text to guess a line);
this block is ours, so it does it properly from the first commit.

Eight declaration kinds, one per bucket:

| kind | answers | body |
|---|---|---|
| `on` | an `@on` name — the `Input` arm | statements |
| `receive` / `bubble` / `response` | a case of the schema's `variant receive` / `bubble` / `response` | statements |
| `compute` | a `$name` in a value position | one expression |
| `when` | an `@when` iteration filter | one expression |
| `enrich` / `enrich-scope` | `@enrich-with` binds | statements assigning `@name` |

> **`when` does not survive the predicates design, and should not.** It is the
> same construct as a boolean `compute`: a name, one expression, no statements.
> What looks like a difference belongs to the slot rather than the declaration —
> what is in scope is decided by *where* a condition is used, and `@show` inside a
> loop already sees `@value`. The routing differs (`Alter` versus `compute`) and
> the author never writes it. The one genuine thing `@when` has is `iterData`,
> the `Map` a sibling `@loop-with` produced, which
> [`predicates-and-invariants-design.md`](predicates-and-invariants-design.md)
> absorbs as the `@iter` binding. After that, `when` is a *use* of a predicate,
> like `@show`, and the kind list is four rather than five.

A ninth, `pred`, is proposed in
[`predicates-and-invariants-design.md`](predicates-and-invariants-design.md): a
named boolean that can answer a `when`, a `compute` in a condition slot, an `if`
in a body, and — when it reads only state — an invariant the runtime enforces.
That document also splits `response` into a success arm and an error arm
(`response loadRows(rows)` beside `response loadRows error(e)`), which the
transactor has always been able to dispatch and the schema has never been able to
say.

`loop_with` is deliberately absent: it returns a slice plan (keys, a filter
decision, a window), not a value, and would need a vocabulary of its own for no
census weight. `swap` is absent for a different reason — it replaces the node
with *another component's instance*, and the value language has no component
reference; today the handler captures the `Component` in its closure. Changing a
node's identity stays a deliberate, visible act written in MoonBit.

### 2.2 Bodies in slots

**A slot whose value starts with `{` holds a body, not a name.** The ambiguity
resolves on the first character, and the character is free: today
`core/value_parse.mbt` reserves and rejects a bare `{…}` in any value token
("not a template; use `$'…'`"), so nothing that parses now changes meaning.

```html
<!-- handler slots -->
<button @on.click="{ .count += 1 }">+1</button>
<input @on.input="{ .query = value; .page = 0 }">

<!-- value slots -->
<x text="{ .first + ' ' + .last }"></x>
<p :class="{ if .ok { 'good' } else { 'bad' } }">…</p>
<div @show="{ (.n > 0) and (not .busy) }">…</div>
<td :title="{ .rows[.sel].meta.note }"></td>

<!-- refused: a path-bearing slot needs a name -->
<div @each="{ .items }">…</div>
```

Three rules make the two positions read consistently:

- **In a handler slot, a bare name is an event argument**, resolved against the
  closed table in `render/dom_event.mbt:38-57` — `value`, `valueAsInt`, `key`,
  `isAlt`, and the rest. In the block form a bare name is a declared parameter.
  The rule is the one the `@on` argument slot already follows, applied one level
  in.
- **In a value slot there are no bare names at all** — no parameters, no event.
  Only `.field`, `@bind`, `$method`, `*dyn`, literals and the builtins.
- The generator synthesizes a name for every body from view + node + slot, stable
  across regenerations so the drift check stays deterministic. It never enters a
  bucket enum, and an anonymous `compute` never enters `SchemaInfo.methods` —
  nothing outside can call it by name.

> **Bodies are an ahead-of-time feature.** A view compiled at runtime through
> `@anode.View::compile` has no generator behind it to emit the desugaring, so a
> body there is a parse error naming `gen-views`. The playground is unaffected —
> it runs viewgen in the browser. §6's interpreter is what would lift this.

### 2.3 Grammar

Two ideas carry the whole design: **application is juxtaposition**, and
**parentheses are required wherever precedence would otherwise be implicit.**

```
decl     := kind name params? body
kind     := 'on' | 'receive' | 'bubble' | 'response'
          | 'compute' | 'when' | 'enrich' | 'enrich-scope'
params   := '(' ident (',' ident)* ')'
body     := '{' stmt* '}'                 -- statement bodies
          | '{' expr '}'                  -- value bodies: compute, when, value slots

stmt     := place ('=' | '+=' | '-=') expr
          | place '.' method operand*           -- a mutating collection method
          | effect operand*                     -- send / bubble / request / stop
          | 'if' expr body ('else' body)?
          ;  statements end at a newline or a ';'

place    := '.' ident path*               -- a place in this component's state
          | '@' ident                     -- a bind; enrich / enrich-scope only
path     := '.' ident | '[' expr ']'

expr     := chain | operand
chain    := operand (op operand)+         -- every op in ONE family; see below
          | 'not' operand
op       := 'and' | 'or'                          -- logic
          | 'is' | 'is not' | '<' | '<=' | '>' | '>='   -- comparison, exactly one
          | '+' | '-'                                   -- additive
          | '*' | '/' | 'mod'                           -- multiplicative

operand  := literal | place | '@' ident '.' ident | '$' ident | '*' ident | ident
          | builtin operand*              -- juxtaposition, fixed arity
          | '(' expr ')'
          | '-' operand
          | 'if' expr body 'else' body
literal  := number | 'true' | 'false' | 'null' | "'text'" | "$'template {x}'"
```

**Mixing operator families in one unparenthesized chain is a parse error**, and
the message names the parentheses to add. So `(not .busy) and (.items.len > 0)`
and `(.view is 'detail') or .pinned` are how those are written, `a and b and c`
and `a + b - c` chain freely, and `a + b * c` is refused. There is no precedence
table to remember and none to get wrong; a comparison takes exactly two operands,
so `a < b < c` is refused too.

**Juxtaposition is unambiguous** because every callable has a known fixed arity
and the vocabulary is closed — builtins, effects and collection methods are
enumerated below, and there are no user-defined functions. `len .items` applies;
`.label = value` does not, because `value` is a parameter with arity zero. An
argument that is itself an expression takes parentheses, which is the same rule
as above: `.items.setAt (.i + 1) 'x'`.

### 2.4 The atoms are the view's atoms

`.field`, `@bind`, `@bind.member`, `$method`, `*dyn`, `'text'`, `$'…{x}…'`,
numbers and booleans are spelled here exactly as a view spells them
(`core/spec.mbt`'s `Val`). The language adds operators, statements and nesting;
it invents no new way to *name* a value.

That is the property worth protecting. It is why a predicate lifts out of a
`@show` into a `when` unchanged, why `$'n={.count}'` is the string form in both
places, and why an author who can read a tutuca view can read a handler body
without learning a second vocabulary.

Two extensions the view cannot spell, both deliberate:

- **`.a.b` and `.a[k].b`** — nested reads and nested *writes*. A view slot's name
  lookup stays one level; a body is checked code, and the generator knows every
  type along the path.
- **`@value.a.b`** — the same, past the one level `BindMember` allows.

### 2.5 Methods, builtins, effects

Mutating collection methods are **receiver-first**, and mirror the
runtime-generic mutators one for one with the `In<Field>At` infix dropped because
the receiver is written:

| written | the mutator it is |
|---|---|
| `.items.push v` | `pushInItems` |
| `.items.insertAt i v` | `insertInItemsAt` |
| `.items.setAt k v` / `.items.deleteAt k` | `setInItemsAt` / `deleteInItemsAt` |
| `.tags.add m` / `.remove m` / `.toggle m` | `addInTags` / `removeInTags` / `toggleInTags` |

Everything that *reads* is a prefix application, which is how a view already
writes a handler call (`setLabel 'sent!'`):

`len .items` · `min .a .b` · `max .a .b` · `clamp .page 0 (.n - 1)` ·
`int .raw` · `num .raw` · `str .n` · `lower .name` · `trim .q` ·
`contains .haystack .needle` · `has .tags 'urgent'`

plus the four shape predicates the views already have — `empty? .items`,
`truthy? .query`, `falsy? .x`, `null? .note`. `equals?` is not among them: `is`
says it, and a view's `equals? .view 'detail'` becomes `.view is 'detail'` —
`equals?` leaves the view slots too rather than surviving as a second spelling
(§10). These four are the closed set today; the predicates design opens it,
letting an author name their own and apply it the same way. Each
of the rest is in the set because the census showed it hand-written — `clamp` for
the 42 `prev`/`next` call sites, `int`/`num` for the `Num(Double)` ⇄ `s32` seam,
`lower`/`trim`/`contains` for the filter predicate.

Effects are prefix applications too, as statements: `send 'flash' .msg`,
`bubble 'rowPicked' @key`, `request 'loadData'`, `stop`. They cover the shape
that dominates — a message plus a flag set, as in
`receive init { request 'loadData'; .isLoading = true }`. There is no
`walk_path` and no `RequestOpts`: choosing a request's options and walking the
dispatch path are the parts a small language would model badly, and they stay in
MoonBit. Addressing *another* component — what `send_at_path` does — is §2.6.

### 2.6 `&` reifies a position

`send` addresses this component. The corpus's other shape addresses a sibling:

```moonbit
ctx.send_at_path(ctx.path().concat([FieldStep("status")]), "flash", [Str(text)])
```

The capability is real and the view language cannot spell it, because every
notation it has denotes a **value** and this one needs a **place**. One sigil is
still free — `Val` uses `.`, `@`, `$`, `*` and `^` — and `&` already means "a
reference to" in the wax type language (`&T`, `&?T`), so using it for a reference
to a place is the same word in both halves rather than a collision:

```
on save   { sendAt &.status 'flash' 'Saved'; .dirty = false }
on pick(k) { sendAt &.rows[k] 'select' }
```

**A place is not a value.** `&.rows[k]` denotes the position; `.rows[k]` denotes
what is there. That distinction is the point — a position survives the root being
rebuilt, which is what makes an async response land on the row that asked for it.

Three key forms exist, and they differ in *when* the key resolves. That is not
cosmetic: it is the async-race material `semantics.md` already documents.

| written | becomes | key resolved |
|---|---|---|
| `&.rows[3]` | `SeqStep(field~, key=KInt(3))` | now, literally |
| `&.rows[k]` — `k` a parameter | `SeqStep(field~, key~)` | now, from the value in hand |
| `&.sheets[.selId]` | `SeqAccessStep(seq_field~, key_field~)` | **every time it runs**, from live state — and pinned at request time |

Only the third follows a moving selection, and only the third can race. The
spelling makes the difference visible rather than inferred, which is the whole
reason to reify paths in the surface instead of building them behind one.

Two limits, both inherited: a place is **relative to this component** — the
generator concatenates `ctx.path()`, exactly as the MoonBit idiom above does by
hand — and `&.a[0][1]` is refused, because a `Path` step is field-then-key and
"a nested `.a[0][1]` is not expressible" (`core/path_path.mbt:29-35`).
`&.a[0].b[1]` is fine.

**Decided: `&` is legal in exactly one position — the first argument of
`sendAt`.** Not `bubbleAt`, not `requestAt`, and those two do not exist: a bubble
walks *up* the path it was raised on, and a request resolves through a registry
rather than a position, so neither has a target to name. `sendAt` is the only
effect that addresses somewhere, so it is the only one that takes a place.

The generator desugars the place into the path builder that already exists — no
new value kind, no runtime change — and `send 'x'` is exactly `sendAt &. 'x'`.

The two designs not taken, kept for the record:

*A place is a value.* A new `Value::Place(Path)` case makes places storable in an
`any` field and passable as a handler argument from a template —
`@on.click="edit &.rows[@key]"` — which is what a **generic editor** needs: one
component handed the position it edits, which is the shape
`patterns/edit-through-a-dynamic-target.md` works around today. The cost is not in
the language: a new case in `core`'s `Value` reaches `Eq`, `to_json`, the codec,
structural equality **and the guest ABI's `values.value` variant**
(`Nil | Boolean | Number | Text | List | Map | Instance`), which is a contract
change across the wasm boundary and a version bump for every bundle.

*A place is data.* Encode the steps as an ordinary `List` of `Map`s and give the
language a `place` builtin. No sigil, no ABI change, storable — and nothing is
typed, nothing is checked, and it reads like assembly. Named because it is the
fallback if the ABI change is refused.

Two things stay out of v1 in every design: **reading through a place** (a getter
makes places into lenses, and lenses want a setter next), and **root-relative
places** for `send_at_root`, which needs a spelling `&.` does not have.

## 3. Semantics

**Total by construction.** No loops, no recursion, no user-defined functions, and
**a body cannot call another body** — the vocabulary is closed and every name in
it is a builtin. Termination is a syntactic property, with no call graph to build
and no cycle to detect. (The predicates design keeps that property while allowing
one kind of composition: a `pred` may call only predicates declared *above* it,
so declaration order is the termination proof.) The cost is visible duplication
(the counter's `add` and
`resetTo` each write the same two statements, which is what `counter_at` shares
today), and that is the trade: duplication you can see beats a checker phase you
have to trust.

**Failure is no change.** An argument that does not match its inferred shape, a
narrowing out of range, an index past the end, a missing key, a division by
zero — the handler produces no new state. That is not a new contract: it is
exactly `None` from `update`, it is exactly what every generated mutator does on
a shape mismatch (`(inst.value)()` — the same instance, which the transactor
reads by `physical_equal` as "nothing happened"), and it is what
`storybook/examples/state_and_updates.mbt:30` hand-writes today so a bad number
leaves state untouched.

**One numeric surface.** `Value` has a single `Num(Double)`
(`core/spec.mbt:104-113`), so the language has one number type. Assigning into an
`s32` truncates and range-checks against the same bounds the generated `decode`
already emits, and fails — no change — outside them. `int x` and `num x` make the
conversion explicit where the author wants to see it.

**`+` concatenates two strings** and adds two numbers; the operands' static types
decide, and a mixed pair is a type error rather than a coercion. `$'…'` remains
the form for anything with more than two parts.

**Nested writes are the new capability.**

```
on toggleLabel(key) { .labels[key].done = not .labels[key].done }
```

replaces `ns_toggle_label` in full, including its guards: the key's shape and the
bounds check are what "failure is no change" already promises. The generator can
emit the spine rebuild because it knows every type on the path.

> **A divergence to record now rather than discover later.** The runtime `Path`
> has no bare-index step — `core/path_path.mbt:29-35` says a path addresses
> field-then-key, so `.a[0][1]` is not expressible. The MoonBit backend does not
> use `Path` at all (it rebuilds the struct), so it is unconstrained; an
> interpreted backend (§6) would be strictly less expressive here.

## 4. Types

The checker reuses `viewgen/check_state.mbt`'s environment and, more importantly,
its governing rule: **unknown is not wrong.** A `$method` result, a `*dyn`, a
child component's fields and a bind this file cannot see are opaque, and an
opaque scope silences every check inside it. A checker that guessed would cost
more in false failures than the real ones are worth.

| atom | type from |
|---|---|
| `.f`, `.f.g`, `.f[k]` | `StateDef::field` / `field_of` / `elem` |
| `on` parameters | the existing call-site inference — `Surface.inputs`, `ArgType`, `join_arg` |
| `receive` / `bubble` / `response` parameters | **`MsgDef.payload`**, which nothing reads today |
| `@value` / `@key` / `@index` | the iterated collection's element type |
| `$name`, `*name` | opaque |

Parameter types are inferred, not annotated. An `on` handler's arguments come
from what the views write at the call site — the table in `skill/tutuca/events.md`
— and two call sites that disagree join to opaque, exactly as `<Comp>Msg`'s
payload inference already does. A `receive` handler's arguments come from the
schema and are therefore exact. That asymmetry is not new; what is new is that
both halves are finally used to check something.

Reported at generation time: unknown field (with `@statedef.nearest`'s
suggestion), type mismatch, assignment to a non-place, an arity that disagrees
with the call sites, an unknown builtin or method, a method applied to the wrong
field kind, a mixed-family operator chain, an effect or an assignment in a value
slot, a body in a path-bearing slot — and the one that matters most, **a name
answered both inline and by an `update` arm**. That is refused rather than
ordered, in the spirit of `Path::update`'s "one lookup, by exact name, with no
fallback sentinel behind it".

## 5. What the generator emits

One backend, and it is the cheap one: **MoonBit source. No new dependency, no
runtime change, nothing new in the browser payload.**

For the dispatch buckets, `viewgen` emits into the existing generated module:

```moonbit
fn counter_inline_update(
  s : CounterState,
  msg : @component.Dispatch,
  ctx : &@tutuca.Ctx,
) -> CounterState? { … }
```

and `emit_comp.mbt`'s wrapper composes it ahead of the author's `update~`, which
stays optional and is consulted only when the inline pass returns `None`. Effects
compile straight through to the `ctx` the function already holds —
`send 'flash' .msg` is `ctx.send("flash", [Str(s.msg)])`, with nothing
abstracted; if an interpreted backend lands it will define its own seam, informed
by what this emitter actually needed.

**A body in a slot desugars to an anonymous bucket entry**, and that is what
keeps the change small: a value-slot body becomes a generated `compute` entry and
the slot is rewritten to a plain `$name`; a handler-slot body becomes an
anonymous `on`. The IR therefore sees only `Method(String)` and `HandlerName`,
which it already emits — **no new `Val` variant, and no arm to add in
`value_eval.mbt`, `value_show.mbt`, `viewgen/ir.mbt`'s `val_expr` or the lint
layer.** The whole feature lives in the generator.

The second half is what makes the noise tier disappear: **a name answered inline
is removed from every bucket enum it would otherwise appear in.** The enums stop
meaning "every name the views use" and start meaning "what this file did not
answer" — which generalizes the rule `wrapper_buckets` already follows, that a
bucket the views never use is not a parameter at all.

The counter demo is the whole argument in one diff. Today
(`demo/counterlib/counterlib.mbt:22-54`):

```moonbit
fn counter_at(s : CounterState, n : Int) -> CounterState {
  { ..s, count: n, history: s.history + [n] }
}

counter_component(
  init=CounterState::fresh(),
  update=(s, msg, _ctx) => {
    match CounterMsg::from_dispatch(msg) {
      Some(Add(d)) => return Some(counter_at(s, s.count + d.to_int()))
      Some(SetLabel(_)) | Some(ResetCount) => return None
      Some(Unknown(_, _)) | None => ()
    }
    match CounterReceive::from_dispatch(msg) {
      Some(ResetTo(n)) => Some(counter_at(s, n))
      Some(Unknown(_, _)) | None => None
    }
  },
)
```

Two nested matches over one dispatch, a `Some(...)` on every arm, an explicit
fall-through arm naming the two mutator-served handlers, two catch-alls, and a
`.to_int()` because the literal `1` at the call site inferred `Double`. With the
block in §2.1 the file becomes:

```moonbit
counter_component(init=CounterState::fresh())
```

## 6. Two backends this design does not build

The AST is designed so both are additive. Neither is in scope, and the reasons
differ.

**A `Value` interpreter.** The same AST walked over `@tutuca.Value`, driving
`schema_mutators(SchemaInfo)` — which is public, is built at runtime from a
schema, and already works for a dyncomp guest through `FieldBox`
(`dyncomp/host/dynobj.mbt:117`). It would buy two things: bodies in views
compiled at runtime rather than ahead of time, and — the real one — a **dynamic
component with behaviour and no compiler at all**. That is the half
[`generative-dyncomps-in-the-browser-design.md`](generative-dyncomps-in-the-browser-design.md)
cannot reach: that design gets `moonc` into the browser, but a component authored
by a model still has to be *compiled*. A total, closed-vocabulary language whose
every failure is a no-op is the thing you can hand to a generator and validate
before running it. It is not first because it is not what the corpus needs; it is
the payoff, not the entry.

**wax → wasm-gc.** `waxmb/wax`'s `InstrDesc` is a ready-made target: `BinOpI`,
`UnOpI`, `Select`, `StructGet` / `StructSet`, `ArrayGet` / `ArraySet`, `Let`,
`If`, `Match`, and `Int(String)` / `Float(String)` keeping literals as raw text
until a type fixes their width — which is precisely the design that lets a
literal stay width-agnostic until a `StateTy` decides.

The blocker is stated plainly: **the MoonBit port of wax has no binary encoder.**
It parses and prints wax text; `wasm_bin/` is types only, and bytes come from the
external OCaml reference back end. Add to that §5's wall in the state design —
MoonBit cannot name an externally-defined wasm-gc type — and the honest position
is that this backend is designed for and not started.

## 7. Costs and risks

**Logic can now hide in a `:title`.** This is the accepted cost of §1, and it is
the one to watch. The mitigations are convention, not grammar: a body is checked
and reported like any other code, anything used twice belongs in the block, and
the block is where a name and a doc comment can live. If review starts finding
whole conditionals inlined across a template, the answer is a lint rule with a
length or nesting threshold — not a retreat to names.

**The CSS collector cannot see through a body.** `gen-margaui-css` and
`gen-tailwind-css` collect only literal class names from the view source, and
they already miss what `$'badge badge-{.kind}'` assembles at runtime — though
that at least contributes the literal prefix `badge-`. A `:class="{ … }"`
contributes nothing at all. Authors relying on the generated stylesheet need
`--classes`, and the diagnostic for a body in `:class` should say so on sight.

**It is a second language in the file.** A view file would carry WIT-ish state,
JSON fixtures, HTML templates and now an expression language. The mitigation is
§2.4: the atoms are the ones the templates already use, so what is genuinely new
is operators and statements. If that stops being true — if the block grows its
own way to name a value — the design has failed and should be reconsidered
rather than patched.

**The escape hatch has to stay obvious.** Roughly 15% of arms are `send_at_path`,
`walk_path`, request options, node-replacing `swap`, dragInfo spelunking and
dyncomp lifecycle. Those must remain in MoonBit, and the diagnostics must say
"this belongs in `update`" rather than inviting the language to grow. The rule
that a name cannot be answered twice (§4) is what keeps the boundary legible.

**The generator still ships to the browser.** `playground/viewgen_js` compiles
viewgen to JS. The new package is a leaf with one dependency (`statedef`) and no
wax, so the payload stays flat — the same argument §6 of the state design makes,
and the same one to re-check if a backend ever needs the lowering.

**Regeneration surface.** Trimming the bucket enums changes generated output for
every component that uses one, so 46 `*_view_gen.mbt` and 42 `*_view_ir_gen.mbt`
move under the existing `git diff --exit-code` drift check. Nothing migrates by
force: a file with no bodies and no block generates exactly what it generates
today.

**`init_block.mbt` is still untested.** `parse_init` / `InitError` have no test
anywhere, and they are the closest existing analogue to what this adds — a typed
literal checker over `StateTy`. Covering them first is cheap and it is the shape
the new checker copies.

## 8. Where this meets dyncomp and the state language

`dyncomp/host/manifest.mbt` carries a guest's types as a flat table because WIT
has no recursion; the state design converges on one declaration language that
serves both. This design converges on the other half: a guest that declares its
state *and* its simple handlers in one file, with the host able to check both
before it runs either.

Nothing here requires that. The MoonBit backend is complete on its own, and the
state language can land before or after. What the two share is the observation
that a component's contract is already in the view file, and that every fact
still living in a `.mbt` file is one the generator cannot check.

## 9. Implementation plan

Staged so each step is independently verifiable and the surface grows last.

### 1. Freeze the analogue

Cover `parse_init` / `InitError` with tests. It is the existing typed literal
checker over `StateTy`, it has none, and the new checker is its bigger sibling.

*Done when:* the init block's type rules are pinned by tests that would catch a
silent widening.

### 2. `handlerdef` — parse, AST, spans

A new package parallel to `statedef`: pure and target-agnostic, text in, typed
AST out, never touching the filesystem. Imports `statedef` for `StateTy` and
nothing else. Tokenizer, parser, spans on every node. No checker, no emitter.

*Done when:* every form in §2.3 round-trips, a syntax error names its column, and
a mixed-family chain reports the parentheses to add.

### 3. The checker

Against a `StateDef` plus a supplied argument-type table, following
`check_state.mbt`'s "unknown is not wrong". This is where `MsgDef.payload` starts
being read.

*Done when:* each error in §4 has a test, including the both-inline-and-`update`
refusal.

### 4. The MoonBit emitter, wired through viewgen

`viewgen/split.mbt` slices the block with a line map; `viewgen/surface.mbt` feeds
it the inferred argument types; a new `viewgen/emit_inline.mbt` emits the inline
update; `emit_msgs.mbt` / `emit.mbt` trim the enums; `emit_comp.mbt` composes the
wrapper.

*Done when:* `demo/counterlib/counter.html` carries the block from §2.1,
`counterlib.mbt` is one line, and the existing harness tests pass unchanged.

### 5. Bodies in slots

`anode/attrs.mbt` treats a `{`-leading value as a body in every slot that takes
one, refuses it in the path-bearing slots, and hands it to the same parser. The
generator desugars each into an anonymous bucket entry and rewrites the slot.
Only after the block form settles — the slot form is a second entry point into
one parser and should not shape it.

*Done when:* `@on.click="{ .count += 1 }"` and `<x text="{ .first + ' ' + .last }">`
both work, regenerating twice produces identical output, and `@each="{ … }"` is
refused with the reason.

### 6. The remaining buckets, then the effects

`compute` / `when` / `enrich` / `enrich-scope`, then `send` / `bubble` /
`request` / `stop`. Each is independent, and each is a reason the block was worth
adding rather than a lateral move.

### 7. Documentation

A self-contained `skill/tutuca/handlers.md`, plus the Notation Reference in
`core.md` — which currently states the rule §1 retires, and needs to state the
new one and both surviving boundaries — and `events.md`, `schema.md`, `cli.md`'s
diagnostics table, the CSS-collector caveat in `cli.md`, and `CHANGELOG.md`. The
lint messages in `lint/parse_issue_rules.mbt` should stop saying "define a method
on the component" and start showing the body.

## 10. Settled

- **`&` is legal only as the first argument of `sendAt`** (§2.6). No `bubbleAt`,
  no `requestAt`, no places stored in fields, no places passed from a template.
- **`equals?` is removed from views**, not deprecated. `is` says it, and one
  meaning keeps one spelling. `@show="equals? .view 'detail'"` becomes
  `@show="{ .view is 'detail' }"` or a named predicate — a mechanical rewrite the
  linter can emit through the `Rephrase` suggestion it already has.
- **`swap` stays in MoonBit.** A swap replaces the node with another component's
  instance, and the value language has no term for a component. Changing a node's
  identity stays a deliberate act written in code.
- **No length limit on a body in a slot.** §7's mitigation stays convention. A
  threshold on statement count or nesting is what a lint is for, and any number
  picked before the corpus has any bodies in it would be a guess.
- **The interpreter (§6) stays after slot bodies.** Bodies are ahead-of-time only
  and that is invisible for generated views. It moves ahead only if
  runtime-parsed views turn out to matter more than the census suggests.

## 11. Open questions

- **Do bodies in value slots want a stricter rule than convention?** §7 says
  anything used twice belongs in the block, and nothing enforces it. The first
  review that finds a three-branch conditional inside a `:title` decides whether
  that stays true.
- **What does a body in a slot do to a macro?** `^param` substitution re-parses a
  macro variable's source text, and a body is source text that reads state. The
  interaction is unexplored and macros are the one part of the view language this
  design has not looked at.
