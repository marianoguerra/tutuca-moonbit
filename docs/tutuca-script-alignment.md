# Aligning the implementation with tutuca script

What in the tree today should change, be deleted, or deliberately stay, once the
view file carries a real expression language. Nothing is announced, so breaking
changes are ordinary changes and the only question is whether each one pays.

Reads with [`inline-handler-language-design.md`](inline-handler-language-design.md),
[`predicates-and-invariants-design.md`](predicates-and-invariants-design.md) and
[`refusals-and-diagnostics-design.md`](refusals-and-diagnostics-design.md). Each
item below names its evidence; the counts are from the current tree.

## A. Required — the design contradicts what is there

### A1 · `func` declarations move out of the state block

`storybook/examples/render_child.html:20` declares:

```
contains-text: func(q: string) -> bool;
```

implemented as a `compute` entry (`EntryMethod::ContainsText`) and called from a
`@when` filter by hand:

```moonbit
Fn(_) => item.call_field("containsText", [Str(query)]).is_truthy()
```

That is a **parameterized predicate**, declared in WIT, implemented in a bucket,
invoked through a dynamic field lookup, and coerced with `.is_truthy()` because
nothing knows it answers yes or no. It is the whole predicates design, hand-built,
in one line of an example.

`schema.md` states the principle the block is supposed to keep — "State is still
data — this puts no behavior in the block" — and then immediately breaks it,
because before the handler block there was nowhere else to declare a callable no
view happens to name.

**Change:** `func` leaves the state block. A callable MoonBit answers is declared
in the handler block without a body (`compute summary -> string;`,
`pred containsText(q);`), which is where every other callable is declared.
`MethodDef`, its parsing, and `declared_methods` leave `statedef`.

**Cost:** three call sites in the corpus (`render_child.html`,
`inspector/module.html` ×2).

### A2 · Responses stop having two shapes

`transactor/transactor.mbt:288-310` dispatches `Ok`/`Err` two different ways: to
two names with one argument each when `RequestOpts` carries them, or to one name
with `[v, Null]` / `[Null, e]` when it does not. The schema can only describe the
second, so the first is reachable only by passing options by hand.

The split is already the norm where it matters: `dyncomp/host/wasm/glue.mbt:260-262`
passes `on_ok_name`, `on_error_name` **and** `on_res_name` unconditionally for
every guest request. Guests have always had split responses; host components have
had a two-slot tuple and a convention.

**Change:** a `response` case typed `result<T, E>` declares both arms, the
generator emits the routing, and **the merged two-slot dispatch is deleted** along
with `on_res_name`. One shape, declared in the schema, checked on both sides.

**Cost:** `storybook/examples/request.mbt` is the only hand-written user of the
option names.

### A3 · `Pred` stops being a closed enum

`core/spec.mbt` defines `Pred { IsEmpty; IsTruthy; IsFalsy; IsNull; Equals }`,
with `parse_predicate` special-casing arity ("2 for `equals?`, else 1") and
`kind_of` returning `None` for a `Predicate` because "predicates have no kind:
they never pass through a group check". Twenty-six sites across `core`, `lint`
and `viewgen` know the five names.

Once an author can declare a predicate, the five stop being a language feature
and become a **standard library**: `Predicate(pred~, args~)` becomes an
application of a name to arguments, resolved like any other, and the arity comes
from the declaration instead of a match arm.

**Change:** delete the `Pred` enum. Delete `equals?` outright — `is` says it.

**Cost:** 94 `equals?` call sites in the corpus, mechanically rewritable, and the
linter already has the `Rephrase(from~, text~)` suggestion machinery to propose
each one.

### A4 · `ObserveMatch` becomes an outcome

`ObserveMatch { Exact; NoHandler }` is already a refusal reason with exactly one
reason in it, and its own comment records that a third case was *removed* when
dispatch stopped probing a catch-all. The refusals design needs a dozen. Same
field, same record, same `to_json` — a wider enum.

### A5 · Bucket enums list what the file did **not** answer

`emit_msgs.mbt` / `emit_comp.mbt` build the bucket enums from every name the views
reference. With inline handlers a name answered in the block must not appear,
or the author is forced to write an arm for something they already wrote. This is
the change that makes the 40% noise tier disappear rather than move.

### A6 · One `warn` call site is a refusal

`core/value_eval.mbt:207` — `warn("handler not found …")`. Every other `warn` in
the tree is host bootstrap ("no `#app` element", "margaui compile failed"), which
is what `warn` is for. This one is `NO_HANDLER` and belongs on the refusal
channel.

## B. Simplifications the design makes available

### B1 · Delete `updateX` and `updateInXAt`

`component/component.mbt:514` generates a mutator that takes a `Fn` — "the update
fn is a plain lambda: it receives ONLY the current value". **A view cannot write a
function value, so no template can ever call it**, and outside `component_test.mbt`
there is not one call site in the tree.

It is worse than dead: its uselessness is *why* `inc` and `dec` are hand-written
in every counter in the corpus. There is a mutator that sets a field and a mutator
that transforms it with a lambda nobody can supply, and nothing in between. The
handler language supplies the in-between (`.count += 1`), which retires the lambda
form rather than fixing it.

**Change:** delete both. Two mutators fewer per field, and `Value::Fn` loses one
of its few structural users.

### B2 · The init block becomes the same language

`tutuca/init` is JSON, checked by a second typed-literal checker
(`statedef/init_block.mbt`, 258 lines, **no tests anywhere**). It is the third
language in a view file, after the schema and the templates.

```html
<script type="tutuca/init">
{ "fresh": { "label": "Counter" } }
</script>
```

becomes statements over the zero state, in the language the file already carries:

```
init fresh { .label = 'Counter' }
init withHistory { .label = 'Demo'; .count = 3; .history = [1, 2, 3] }
```

Three things fall out. The checker is the one that already exists rather than a
second one nobody tested. A fixture can *derive* a value instead of restating it.
And "every fixture satisfies every invariant" becomes a natural check rather than
a bolted-on one, because a fixture is now a sequence of transitions from `zero`
and transitions are what invariants already guard.

**Cost: one file.** `demo/counterlib/counter.html` is the only `tutuca/init` block
in the tree.

Keep the JSON form for **dyncomp manifests**, which are machine-written and read
by a host that may not evaluate expressions. Authoring and interchange are
different jobs.

### B3 · Retire `@if.<attr>` / `@then` / `@else`

Forty implementation sites across `anode`, `viewgen`, `render` and `core`,
carrying a node type (`IfAttr`), a disambiguation rule (`@then.<x>` when there are
several, because HTML forbids duplicate attribute names), and its own arms in
`check_state`, `surface` and `ir`. All of it expresses one conditional value:

```html
<a @if.class="isCurrent" @then="'tab tab-active'" @else="'tab'">
<a :class="{ if isCurrent { 'tab tab-active' } else { 'tab' } }">
```

The body form needs no directive family, no attribute-name inference, and no rule
about duplicates. The boolean-attribute case still works, because the attribute
layer already folds a `Bool` value into presence: `:disabled="{ not hasTitle }"`.

**Cost:** ~60 corpus sites, mechanical. **Recommend**, but land it *after* bodies
in slots have been used for a while — this is the one item where the replacement
is longer to type than what it replaces, and that judgement is better made with
the feature in hand than from a design document.

### B4 · The `Group` masks shrink

`in_group` (`core/value_parse.mbt:63-85`) answers "which `Val` kinds may appear in
this slot" for eight groups. Two of them exist to keep names out of value
positions, and the predicates design changes the question a condition slot asks:
it takes an **application**, not a value.

After that the masks separate two things rather than eight: slots that must yield
a `Step` for dispatch and write-back (`@each`, `<x render>`, `provide`) and slots
that read. That is the distinction that actually matters, and the one the
docs already explain to authors.

## C. Considered, and deliberately unchanged

**`@hide` stays.** 58 uses against 228 `@show`, and the arithmetic favours it:
under the condition-slot grammar `not hasTitle` is a legal unary application, but
`not (empty? .items)` is not — a parenthesized application is not an atom. Deleting
`@hide` would turn its most common form into a body. It earns its keep as the
negation that needs no braces.

**`swap` stays, and stays out of the language.** Three real call sites
(`storybook/examples/json.mbt`, `playground/site/examples/json.mbt`,
`storybook/examples/visual_wasm.mbt`) for a whole tier of dispatch precedence,
which looks like a deletion candidate until you ask what replaces it: nothing
else can change a node's *identity*. Keep it, do not grow it, and leave it in
MoonBit where the component reference lives.

**`warn` stays.** After A6 its remaining callers are host bootstrap failures,
which are warnings and not refusals. Two channels, two questions.

**`PathChanges` / `ctx.at()` stay.** `&` gives the *view* a way to name a
position; MoonBit still needs a builder, and `core/path_path.mbt:23` already
records that the two spellings delegate to the same place.

**The `Alter` namespace stays.** `when` leaving it does not empty it — `enrich`,
`enrich_scope` and `loop_with` are still resolved through `obj_callable` rather
than as fields, and they are still not value reads.

## D. Sequencing

The dependencies are shallow and only two items block others.

1. **A3** (`Pred` → application) and **A5** (bucket enums) are prerequisites for
   the handler language landing at all.
2. **A1** (`func` moves) and **B2** (init block) are independent of everything and
   can land with the handler block itself; both shrink `statedef` rather than
   growing it, which is worth doing while it is being rewritten anyway for the
   state language.
3. **B1** (`updateX`) can land **today**, before any of this. It has no users, and
   deleting it makes the case for the handler language concrete: the reason to
   want `.count += 1` is that the alternative was a lambda no view could write.
4. **A2** (responses) waits on `result` in the state language.
5. **A4** and **A6** are the refusals design's first two commits.
6. **B3** (`@if`) and **B4** (groups) come last, when bodies in slots have proven
   themselves.

The one item worth doing out of order is B1, because it is a deletion with no
migration and it removes the strongest piece of evidence that the current mutator
set has a hole in it.
