# Named predicates, invariants, and handler contracts

One construct — a named boolean predicate — for every place tutuca already asks a
yes/no question, and three things to attach it to: a **value** (which is what a
constraint is), a **state** (which is an invariant), and a **transition** (which
is a pre/postcondition in the Eiffel sense).

Extends [`inline-handler-language-design.md`](inline-handler-language-design.md)
(the expression language a predicate is written in) and
[`wax-state-language-design.md`](wax-state-language-design.md) (the declaration
language a predicate can be attached from). It needs both; it is not useful
before either.

## Context

Conditions are already everywhere, in four spellings that do not compose.

**In a template slot**, a closed set of five: `empty? .items`, `truthy? .query`,
`equals? .view 'detail'`. Fixed arity, no nesting — an argument cannot itself be
a predicate, because `Predicate` has no `Kind` and so fails the group check in
`core/value_parse.mbt`. The set cannot grow, and nothing an author writes can
join it.

**In a `compute` bucket**, anything at all, as long as it returns a `Value` that
happens to be a `Bool`. `@show="$canSubmit"` works today and is the escape hatch
the linter points at. Nothing types it as a condition; nothing stops
`@show="$itemCount"`.

**In a `when` bucket**, a filter with its own signature —
`(S, key, value, iterData) -> Bool` — which is the same question asked with a
different shape, so a predicate written for `@show` cannot answer `@when`.

**In `dyncomp/jsonschema/constraint.mbt`**, as *data*: `min`, `max`, `minLen`,
`maxLen`, `pattern`, `format`, `enumJson`. This is the only one of the four that
a form, a JSON Schema and an agent can all read, and its header says exactly why
it exists — "`TyInfo` says a field holds a string. This says it holds an email
between three and 254 characters." It is a predicate language with eight members
and no way to add a ninth.

And there is the thing none of the four can say. `Constraint` describes **one
field at a time**, so a rule relating two fields has no home anywhere in the
system:

> A post may be `published` only if it has a `title`.
> `page` must be within `items`.
> `endsAt` must be after `startsAt`.
> If `kind` is `scheduled`, `dueOn` is required.

Every one of those is written today as a guard inside a handler, in MoonBit,
once per handler that could break it — and forgotten in the handler nobody
thought about. They are properties of the *state*, stated as properties of a
*code path*.

## 1. The one construct

```
/// A post needs a title before it can go out.
pred publishedNeedsTitle { .published implies (nonBlank .title) }

pred nonBlank(s)         { (trim s) is not '' }
pred inRange(n, lo, hi)  { (n >= lo) and (n <= hi) }
pred unfinished(item)    { not item.completed }
```

A `pred` is a name, an optional parameter list, and **one boolean expression** in
the handler language. It is the same body a `when` or a `compute` takes, with one
added rule and one added operator.

**Declaration order is the termination proof.** A predicate may call predicates
declared *above* it and no others. Forward references are refused. That keeps the
handler language's central claim intact — termination is syntactic, there is no
call graph to build and no cycle to detect — while still allowing the composition
that makes named predicates worth having. It is a rule a reader checks by eye.

**`implies` is a fourth operator family.** `a implies b` is `(not a) or b`, and it
is the shape most cross-field rules take. Like comparison it is non-associative:
exactly two operands, so the right-associativity trap never arises, and mixing it
with `and` or `or` needs parentheses like every other family.

### A predicate carries the sentence it fails with

A rule that refuses something has to be able to say what it refused and why, and
the two halves of that are not the same text. The doc comment is the **static**
description — what the rule is, in the schema, in a JSON Schema, in what an agent
is told before it acts. A `format` clause is the **dynamic** message — what went
wrong this time, with the values that made it go wrong:

```
/// A post needs a title before it can go out.
pred publishedNeedsTitle
  format $'Cannot publish "{.slug}": the title is empty.'
{ .published implies (nonBlank .title) }

pred inRange(n, lo, hi)
  format $'{n} is outside {lo}…{hi}.'
{ (n >= lo) and (n <= hi) }
```

The clause sits where `requires` and `ensures` sit on a handler (§5), and its
value is an ordinary `$'…'` template — the string form the language already has,
so there is no second interpolation grammar. Four rules make it predictable:

- **It is the message for the false case.** A predicate is true when things are
  fine, so the sentence describes the failure. Easy to write backwards, and worth
  a lint that flags a format with no negative wording only if that lint can be
  made not to nag.
- **Its environment is the predicate's**, parameters included — `{n}`, `{lo}` and
  `{hi}` above are the arguments the caller passed.
- **The state it reads is the state that failed.** For a constraint or an
  invariant that is the *rejected* successor, which is the one worth showing
  ("the title is empty" is about the state you tried to reach). For a
  precondition it is the current state, and inside an `ensures` `old` reaches the
  pre-state as usual.
- **A predicate with no format still reports** — the framework falls back to the
  doc comment, then to the predicate's name. Formats are worth writing and never
  required.

An alternative spelling worth keeping in view is a standalone declaration —
`format pred publishedNeedsTitle $'…'` — which separates the message from the
rule. That reads worse next to the predicate and better as a *table*, which is
exactly what you want if messages are ever translated: one block per locale,
swapped wholesale, with the predicates untouched. If localization is on the
horizon, the standalone form is the one to build.

Composition raises one question the design should answer explicitly. When
`publishedNeedsTitle` fails because the `nonBlank` it calls returned false, the
message reported is the **outer** one — the rule that was being enforced, not the
mechanism it happened to use. Recording the innermost false predicate as a
`cause` alongside it is cheap (predicates are total and already being evaluated)
and is left as an option rather than built in: a chain is worth a great deal when
debugging and is noise in a form field.

### The read set is the interesting property

Because the language is total and its vocabulary closed, every predicate's
**read set** — which state fields, which bindings, which parameters it touches —
is computable at generation time. Four things fall out of the same fact:

| the read set decides | how |
|---|---|
| whether a predicate can be an invariant | it may read state fields and nothing else — no bindings, no parameters |
| which writes must re-check it | index invariants by the fields they read; a write touching none of them cannot break it |
| whether a precondition can be shown in the UI | a state-only read set can be evaluated at render time (§5) |
| what projects to JSON Schema | one field projects to a constraint, a two-field implication to `if`/`then`, the rest not at all (§7) |

The criterion for invariant-eligibility is the read set and **not the arity**. A
zero-argument predicate inside a loop can read `@value`, which does not exist at
the moment a state is validated. Arity zero is necessary and not sufficient.

## 2. Where a predicate can be used

**Every condition slot, and it is spelled bare in all of them:**

```html
<div @show="publishedNeedsTitle">…</div>
<li @each=".items" @when="unfinished">…</li>
<a @if.class="isCurrent" @then="'tab tab-active'" @else="'tab'">…</a>
<button @if.disabled="not hasTitle">Publish</button>
```

That is one spelling for one declaration, and the reason it is available is worth
writing down, because the obvious worry — that a bare word already means
something in those slots — turns out to be false.

`in_group` (`core/value_parse.mbt:63-85`) admits `KName` into exactly two groups:
`GValue`, which is the handler-argument position, and `GAll`, which is a macro
attribute. **It is in neither `GBool` nor `GText`.** So `@show="canSubmit"` today
is not a lookup with a different meaning — it is a parse rejection. Adopting the
bare form widens a spelling that is currently refused rather than reinterpreting
one that works, which is the same property that made `{` safe for bodies.

Three consequences, all of them simplifications:

- **No `@when` call site changes.** `@when` is already bare
  (`parse_alter_handler` produces a `HandlerName`), so it is the value-ish
  conditional slots that join *it*, not the other way round. `@when` was right
  all along.
- **The grammar of a condition slot collapses into one rule:** `name arg*`, a
  predicate application. `empty? .items` is the one-argument case, `unfinished`
  is the zero-argument case, and the builtins stop being special — they are
  simply predicates whose names end in `?`. `not hasTitle` fits the same rule as
  a unary application, which is what lets a negation stay unbraced. Anything more
  than an application still needs a body: `@show="{ (.n > 0) and (not .busy) }"`.
- **`Predicate` already has no `Kind`** — the file says so: predicates "never
  pass through a group check (`parse_bool` builds them directly)". A bare
  zero-argument application is the same code path with the argument count at
  zero.

**Value slots keep `$`.** `@text="$fullName"` stays, and `@text="fullName"` stays
refused, because there a bare word is far more likely to be a forgotten quote
than a call — turning `@text="hello"` from "bare text must be quoted" into
"undeclared predicate `hello`" would be a worse message for a more common
mistake. The rule that makes this principled rather than arbitrary: **a condition
slot takes an application, a value slot takes a value, and a call in a value
position needs its sigil.**

`$name` remains legal in a condition slot — it is the same node — so nothing
breaks on the day this lands; a hint suggests the bare form.

A predicate used in a condition slot is also the thing that finally makes
`@show="$itemCount"` an error: the generator knows a `pred` answers yes or no,
and an untyped `compute` never did.

`@when` is where the unification bites, and it goes further than "one declaration
answers both slots": **`when` stops being a declaration kind at all.**

A `when` and a boolean `compute` are the same construct — a name, one expression,
no statements — and the three things that look like differences are not. What is
in scope belongs to the *slot*: `@show` inside a loop already sees `@value`, and a
predicate in a `@when` slot sees it for the same reason. The routing differs
(`@when` resolves through the `Alter` namespace, `$name` through `compute`) and
the generator picks it, so the author never writes it. And the signature
difference — `(S, key, value, iterData) -> Bool` — is a MoonBit calling
convention, not something a body says.

One genuine thing is left, and absorbing it is what makes the collapse honest.
`@when` is invoked as `call_handler(f, it, [key, value, iter_data])`
(`render/render.mbt:233`, and again from the `@loop-with` filter in
`render/loop.mbt:27`), and that third argument is a `Map` a **sibling
`@loop-with` handler produced** — `{ "seq": seq }` by default. It is not a state
field and not a loop binding, so nothing else in the language can reach it.

**Give it a binding.** `@iter` falls straight out of the existing `@name.member`
form, and then a predicate can say everything a `when` could:

```
pred unfinished { not @value.completed }
pred bigEnough  { @value.n >= @iter.min }          -- min came from @loop-with
pred notLast    { @index < ((len @iter.seq) - 1) }
```

So the kind list loses a member: `pred` and `compute` are the one-expression
kinds, `on` / `receive` / `bubble` / `response` are the statement kinds over
state, and `enrich` / `enrich-scope` are the statement kinds over binds — those
two stay because they produce bindings rather than a boolean. `when` joins
`@show`, `@hide` and `@if` as a *use*.

The relationship to `compute` is worth stating in the same breath, because it is
the other half of the question: **`pred` is a subset of `compute`** — one whose
return type is declared boolean — and declaring that subset is precisely what
unlocks everything downstream. An untyped `compute` cannot be an invariant, a
`requires`, or a `@show` the generator will type-check, because nothing knows it
answers yes or no.

**Inside the language**, as prefix application, alongside the builtins:

```
on publish        { if publishedNeedsTitle { .published = true } }
compute rowClass  { if unfinishedItem { 'row' } else { 'row done' } }
```

**And attached to state or to a handler**, which is the rest of this document.

## 3. Three strengths, and they are different in kind

The obvious design says: a predicate over state is a rule, and breaking it is
refused. That is right for `page` within `items` and wrong for every form in
existence — an email is invalid for as long as it takes to type one, and a rule
that refuses the keystroke makes the field unusable.

So a predicate carries one of three strengths, and the differences are not
degrees of severity but different questions:

**`constraint` — is this value acceptable?** Reported, never enforced. The state
may hold a value that violates it, and the violation is readable: that is what
draws the error under the field, disables Apply, tells an agent why its arguments
were rejected, and appears in a JSON Schema. This is exactly what
`dyncomp/jsonschema/constraint.mbt` already is; the eight keys become sugar for
builtin predicates over one field, and the eight stop being the ceiling.

**`invariant` — is this a state the program may be in?** Enforced, never
violated. A transition producing a state that breaks it does not happen: the
state is unchanged, which is precisely the handler language's existing contract
("if a handler cannot finish, nothing changes") and precisely what every
generated mutator already does when handed something it cannot use.

**`requires` / `ensures` — may this handler run, and did it do its job?** Per
transition, in the Eiffel sense: a precondition is the *caller's* obligation and
a postcondition is the *handler's*. §5.

The rule of thumb: a **constraint** is about the value a person is entering, an
**invariant** is about a state the program must never be in, and a **contract** is
about one particular change. A draft holding a malformed email is a real state a
form must be able to hold. A `page` of 7 in a 3-item list is not a state, it is a
bug. "You cannot publish without a title" is neither — it is a rule about the act
of publishing, and it wants to be visible on the button.

## 4. Where an invariant lives — two designs

They differ on one axis: what the invariant is attached to.

### Design 1 — On the type

The state block names it; the handler block defines it. This is the pattern
`schema.md` already documents for `$`-callables: a freestanding `func` names a
method the `compute` bucket has to answer, and "State is still data — this puts
no behavior in the block." A predicate name is the same kind of reference: the
block says *which* rule holds, not what the rule computes.

```html
<script type="tutuca/state">
  state Post { title: StringConstraintNonBlankTitle, slug: StringConstraintSlugFormat, page: Int, published: Bool }
</script>

<script type="tutuca/handlers">
  pred nonBlankTitle       { (trim .title) is not '' }
  pred slugFormat          { matches .slug '^[a-z0-9-]+$' }
  pred publishedNeedsTitle { .published implies nonBlankTitle }
  pred pageInRange         { inRange .page 0 ((len .items) - 1) }
</script>
```

The attribute syntax is the one the state design already plans for constraints
(`#[min = 0] count: s32`); this generalizes it from eight fixed keys to any
predicate, and keeps the eight as sugar.

**What this buys, and it is the whole argument:** the rule is part of the schema,
so it travels everywhere the schema goes — `SchemaInfo`, the descriptor, the JSON
Schema projection, the generated form, the inspector, a dyncomp's manifest, and
the tool parameters an agent generates against (`agent-runtime.md`: "the type says
a field holds a string; the constraint says it holds an email under 254
characters. A model needs the second half as much as a form does"). A cross-field
rule is the half neither `TyInfo` nor `Constraint` can carry, and it is the half a
model most needs, because it is the one it will otherwise violate.

Two consequences, both good:

- **`zero()` must satisfy every invariant**, and so must every `tutuca/init`
  fixture. Both are checkable at generation time — the init block already
  type-checks fixtures against the schema, so this is the same walk with a
  predicate evaluated at the end. An invariant the zero state cannot satisfy is a
  generation error naming the fixture the component needs instead.
- **A dyncomp gets validation with no guest code**, the same way it already gets
  `setX` from `schema_mutators`.

Costs: the state block gains a name reference into the handler block, so a file
with invariants needs both. And a predicate reaching for something the schema
cannot describe is a rule the description silently lacks (§7).

### Design 2 — On the component

The handler block declares the invariant outright; the state block never learns
about it.

```
invariant publishedNeedsTitle { .published implies (nonBlank .title) }
```

Simpler — one block, one grammar, no attribute vocabulary, no coupling between
the two languages. And weaker in one specific way: the descriptor, the generated
form, the inspector, the JSON Schema and an agent never learn the rule exists. A
host editing a dyncomp's field through `with_field` gets a refusal it cannot
explain and could not have predicted, and a model generating arguments is told the
shape and not the rule — so it produces an invalid combination, is rejected, and
has nothing to correct against.

This is right if invariants are a property of *this component's implementation*.
It is wrong if they are part of what the component *is*, which is what
"declarative" implies and what the whole `SchemaInfo` layer is arranged around.

**Design 1 is the recommendation**, on that argument alone.

> **Why a per-transition guard cannot substitute for either.** It is tempting to
> say invariants are unnecessary if every write is guarded. They are not: a
> hand-written MoonBit arm returns a struct literal — `Some({ ..s, published:
> true })` — which is neither a mutator call nor a body assignment, so no write
> guard fires and the excluded state exists. Validating the *successor* catches
> it; guarding the *write* cannot. Contracts (§5) are worth having for their own
> reasons, not as a cheaper invariant.

## 5. Handler contracts

Eiffel's three-part contract maps onto a tutuca handler almost without
translation, because a handler already is a routine with one receiver and one
result: old state in, new state out.

```
on publish
  requires hasTitle
  ensures  .published
{
  .published = true
}

on add(d)
  requires (d is not 0)
  ensures  (.count is (old .count) + d)
{
  .count += d
}

on removeRow(i)
  requires inRange i 0 ((len .rows) - 1)
  ensures  ((len .rows) is (old (len .rows)) - 1)
{
  .rows.deleteAt i
}
```

Each clause is a predicate application or a boolean expression; several of either
kind are conjoined. A clause may carry a tag for the message —
`requires hasTitle: (trim .title) is not ''` — following Eiffel, because a
violation report that names the clause is worth more than one that quotes it.

**`old` reads the pre-state.** Only inside `ensures`, only over state, and it is
free to implement: `Path::update` is holding both the old leaf and the new one at
the moment the postcondition runs. It is what lets a postcondition say something
about the *change* rather than the result, which is most of what postconditions
are for.

### What a violation does

**A failed precondition means the handler does not run**, and the transition is a
no-op. It specifically does **not** fall through to the next thing in the dispatch
chain, and that is worth being explicit about: `on setPage(n) requires …` shares a
name with the generated `setPage` mutator, and falling through would run the
unguarded mutator instead — turning a guard into a no-op with extra steps. A
precondition that fails ends the dispatch.

**A failed postcondition is a bug in the handler**, not a condition to recover
from. It refuses the transition, for the same reason everything else does, and it
reports loudly: through `core/warn.mbt`'s redirectable `warn_hook` in development
and in the browser console, and — because the harness installs its own hook — as a
**test failure** in `moon test`. A postcondition is the cheapest possible test,
written next to the thing it tests and run by every existing test that happens to
reach it.

**The invariant is conjoined to both.** This is Eiffel's class-invariant rule and
it is what makes §4 and §5 one system rather than two features: an invariant holds
on entry and on exit of every handler, so it is the postcondition every handler
shares and nobody has to write. A handler's own `ensures` says what is true of
*this* change; the invariant says what is true always.

### Preconditions are readable, and the author does the reading

A `requires` clause whose read set is state-only can be evaluated **at render
time** — the framework could know before the click whether the handler would
decline, and disable the control that would trigger it.

**That is not built.** The precondition refuses the dispatch; showing it stays the
author's job, with the tools that already exist:

```html
<button @on.click="publish" @if.disabled="not hasTitle">Publish</button>
```

Automatic gating would be the stronger version — the fact declared once, unable to
drift — and it is also the one where a button greys out because of a rule two
files away, in a render path that would then depend on the contract layer. The
information is available if it is ever wanted; the connection stays visible in the
markup instead.

Note what the condition-slot spelling buys here: the same predicate the contract
names is the one the attribute reads, so the two cannot disagree about *which*
rule they mean even though the author writes both.

## 6. Split responses: success and failure are two handlers

`response loadRows(rows) { .rows = rows; .isLoading = false }` has a hole in it —
what runs when the request fails — and the runtime has been able to answer it all
along. `transactor/transactor.mbt:288-310` dispatches a response one of two ways:

- with `on_ok_name` / `on_error_name` set on the request, `Ok(v)` dispatches
  `Response(on_ok_name, [v])` and `Err(e)` dispatches `Response(on_error_name, [e])`
  — **two names, one argument each**;
- with neither set, both outcomes dispatch the *same* name with a two-slot
  argument list: `[v, Null]` on success and `[Null, e]` on failure.

So the split exists in the transport and is unexpressed in the declaration. The
schema types one merged case, and the author who wants the split has to pass
`RequestOpts` by hand and keep the two names in sync with two arms.

**Declare the outcome in the type, and the pairing follows.** The state language
is being replaced anyway, and `result` — which `from_wit.mbt` refuses today as out
of the subset — is exactly the shape `respond` already takes
(`Result[Value, Value]`):

```html
<script type="tutuca/state">
  response C { LoadRows(ResultValuesString) }
</script>

<script type="tutuca/handlers">
  response loadRows(rows)    { .rows = rows;   .isLoading = false }
  response loadRows error(e) { .error = e;     .isLoading = false }
</script>
```

The type says there are two outcomes and gives each a payload type — so `rows` is
a list and `e` is a string, both checked. The two arms name one request between
them, so **the generator wires `RequestOpts` itself**: `request 'loadRows'` in a
body emits `on_ok_name` and `on_error_name` pointing at the two dispatch names it
derived, and the author never sees them. A `response` whose payload is not a
`result` keeps today's single arm and today's merged dispatch, so nothing existing
has to move.

Two rules fall out, and both should be diagnostics rather than conventions:

- **An error arm with no ok arm is fine** — you may only care about failure. An ok
  arm with no error arm is also fine, and it is where the hole was: the generator
  emits `on_ok_name` only, so a failure can no longer arrive at the success
  handler with `Null` where its rows should be. Instead it arrives nowhere, and
  "nowhere" must be a `warn`, not a silence.
- **`ensures` composes with this well.** `response loadRows(rows) ensures (not .isLoading)`
  says the thing you actually meant, on both arms independently.

On the spelling, two candidates, and the second is the recommendation:

```
response error loadRows(e) { … }     -- the kind reads as one compound
response loadRows error(e) { … }     -- the names line up in a column
```

The second keeps `loadRows` in the same character position as its ok arm, which is
what a reader scanning for a name is doing, and it puts the modifier next to the
parameter list it changes.

## 7. How enforcement runs

**One choke point.** `Path::update` (`core/path_spec.mbt:299-312`) resolves the
leaf, calls exactly one handler, and "rebuilds the spine only when the handler
produced a new leaf". Preconditions run before that call, postconditions and
invariants after it and before the rebuild. It covers every bucket, every
generated mutator, every inline body and every MoonBit `update` arm, because all
of them arrive there as a successor value, and a refusal returns the same `root`
object — a path the function already has.

**A second entry, for the host.** The inspector edits a component by calling its
setter directly (`inspector/state_editor.mbt:136-152`), and a dyncomp host writes
through `obj_with_field`. Neither passes through `Path::update`, so validation has
to be reachable as a function of the value — an `obj_valid` beside `obj_schema`,
answering which invariants a state breaks. `dyncomp/jsonschema/coerce.mbt` is
where it lands for the host: `coerce` already validates a whole
`Map[String, Value]` against the schema and per-field constraints and returns
`Result[_, Array[SchemaError]]`, so a record-level rule is one more check in a
function that already sees every field at once.

**Footprint indexing.** Invariants are indexed by their read set, so a write
re-checks only the rules that read a field it touched.

**Generation time.** `zero()` and every `tutuca/init` fixture are evaluated against
every invariant during `gen-views`. This is the check most likely to catch real
bugs, because it costs nothing and runs before anything is deployed.

### What reaches a JSON Schema, and what does not

| predicate | projects to |
|---|---|
| `(len .title) > 0` | `title: { minLength: 1 }` |
| `inRange .count 0 100` | `count: { minimum: 0, maximum: 100 }` |
| `matches .slug '…'` | `slug: { pattern: "…" }` |
| `.published implies (nonBlank .title)` | `if: { properties: { published: { const: true } } }, then: { properties: { title: { minLength: 1 } } }` |
| `.endsAt > .startsAt` | nothing JSON Schema can say |

The precedent for the last row is already in the tree. A bound the type cannot
carry is reported at load as `INERT_CONSTRAINT` and "never reaches the emitted
JSON Schema — so an agent generating arguments is not told a timestamp has a
maximum of zero". The same rule one level up: **a predicate that cannot be
projected is still enforced, and its absence from the schema is reported**, so
nobody reads the projection as complete. Where the projection fails, the
description still carries the rule's **name and doc comment** — an agent told
"publishedNeedsTitle: a post needs a title before it can go out" and handed a
rejection naming that rule has something to correct against, which is the
difference between a retryable failure and a loop.

## 8. Costs and risks

**A refused transition looks like a click that did nothing.** The handler language
already has this property for a bad index; invariants and preconditions make it
reachable from a rule the author wrote deliberately. Three mitigations, in order
of how much they help: preconditions as affordances (§5) means the button was
disabled and the click never happened; `warn` means development is loud; and
`constraint` exists so that a rule about what a person is entering is never an
`invariant` in the first place. The docs need to say that last one louder than
this document does.

**Postconditions run in production too, and that is decided.** `ensures` is
emitted unconditionally and enforced everywhere: a contract is a contract, and the
alternative — compiling them out of release builds — means production behaviour is
not the behaviour anyone tested, which is precisely the situation the bug a
postcondition catches lives in. The cost is paid on every dispatch and is bounded
by the same read-set index invariants use. Keep them cheap; do not make them
conditional.

**Two blocks, one dependency.** With Design 1 a state block names a predicate the
handler block defines, so neither is readable alone. That is already true of
`func` declarations and `compute`, so the machinery exists — but it is one more
way a file can be half-written.

**`implies` is the operator most likely to be misread.** `a implies b` is true
whenever `a` is false, which surprises people who read it as "a causes b". Since
mixing families already needs parentheses, the parser can afford to be generous
with the error text here.

**Scope creep toward a solver.** The moment invariants exist, somebody will want
the framework to *repair* a violating state rather than refuse it, or to derive
which fields are safe to change. Neither is in this design and both should stay
out: the language is total precisely because it does not reason, and a rule that
quietly rewrites your state is worse than one that refuses it.

## 9. Settled

- **Condition slots take a bare predicate application** (§2); value slots keep
  `$`. `@when` does not change, and `$name` stays legal in a condition slot with
  a hint toward the bare form.
- **`ensures` is always emitted and always enforced** (§8), in every build.
- **Gating a control on its handler's precondition is not built** (§5). The
  author writes `@if.disabled="not hasTitle"`.
- **An invariant may call predicates, not computes.** A `pred` is transparent, so
  its read set composes; a `compute` is opaque under "unknown is not wrong", and a
  rule with an unknown footprint can be neither indexed nor projected. `$name`
  inside an `invariant` or a `constraint` is refused, and the message says to name
  a predicate instead.
- **Invariants belong to the type, so a shared state struct shares them.** That
  follows from Design 1 and from the existing rule that "a schema belongs to a
  TYPE, so two components sharing a state struct share its description". A rule
  only one component wants is a `requires` on that component's handler.
- **A MoonBit `update` arm cannot declare a contract**, because contracts attach
  to declarations the block owns. Invariants still reach it — enforcement is at
  the choke point, not at the declaration.
- **A predicate that fails records the innermost false sub-predicate as `cause`**
  (§1). It is cheap, since the sub-predicate was evaluated anyway, and the
  reported *message* remains the outer rule's.
- **The `format` clause is what ships**; the standalone `format pred name '…'`
  table stays the path to take if messages are ever localized.
- **Child-component invariants are out.** A slot holds an `Obj` and `obj_field`
  would reach into it, but a parent whose validity depends on a child's — and is
  re-checked on every child transition — is a far larger contract than this design
  costs out.

## 10. Open questions

- **Does `constraint` subsume `Constraint`, or sit beside it?** The eight keys are
  data a host reads without running anything. Making them sugar for predicates is
  cleaner and means a host must be able to *evaluate* a predicate; keeping both
  means two spellings for `maxLen`. This is the one question the dyncomp host's
  shape decides rather than the language's.
- **May a user predicate be named like a builtin?** `is_valid_val_id` already
  admits a trailing `?`, so `pred ready?` parses. Reserving the five builtin names
  is one line; whether user predicates should be *encouraged* to end in `?` is a
  style call that affects every example in the docs.
- **What is the read set of a predicate that reads `@iter`?** `iterData` is
  produced by a sibling `@loop-with` handler, which is opaque. A predicate reading
  `@iter` is fine as a filter and can never be an invariant — but the rule should
  be stated as a footprint consequence rather than a special case.
