# tutucard/wasm

Compile a [tutucard](../) `.html` file into a `tutuca:component@0.11.0` **core
wasm module**, in the browser, with no MoonBit toolchain anywhere on the page.

```
card.html  --viewfile/statedef/tscript-->  declarations
           --tscript/check-------------->  rejected, or
           --tutucard/wasm-------------->  a Wax AST
           --+ internal/waxsrc---------->  ... on top of jv_value
           --marianoguerra/wax---------->  a core wasm module
           --dyncomp/host/wasm/abi.mjs-->  a running guest
           --dyncomp/host-------------->   a component in a page
```

One of TWO backends over `tscript`'s one AST: `tscript/emit_mbt` turns a block
into MoonBit ahead of time, and this one compiles it. Both are held to
`tscript/conformance`, because a language with two implementations and no shared
table has two semantics.

There was a third — an interpreter that ran a card where it stood, and what
`tutucard` mounted. **It is gone, and this is what replaced it.** Mounting a
card means compiling it and instantiating the module, which is why
`web/card-wasm.js` has a `mountCard` and the MoonBit side no longer has a
`load`.

## Three packages

| | |
|---|---|
| `internal/abi/` | the canonical ABI's numbers, the constant pool, and the three Wax types everything here speaks in |
| `internal/waxsrc/` | the Wax sources every module carries: the vendored standard library and the fixed card runtime, parsed once |
| *(this one)* | the card: `dsl.mbt`, `compile.mbt`, `expr.mbt`, `stmt.mbt`, `dispatch.mbt`, `manifest.mbt`, `alloc.mbt`, `spec.mbt` |

Split where the seams are **thin**, not where they are merely nameable. `abi` is
fifty-odd uses, each reading better qualified (`@abi.ret_get_field`); `waxsrc`
is two. The instruction builders stayed in `dsl.mbt` — three hundred uses, and
`@emit.call(@emit.get("s"), …)` would undo the one thing that file exists to
do, which is to let the emitters read as the Wax they stand for.

`internal/`, so none of it is a promise outside this module: MoonBit refuses an
`internal/` import from another module.

## What compiles

**Fields.** Every `StateTy` tutuca has: `Bool`, `Int`, `Double`, `String`,
`Array[T]`, `Map[T]`, `Set`, a declared `record`, `enum`, `flags`, a tuple, an
option, and `Any`.

An instance is a **`jv_record`** — the Wax data stdlib's runtime-declared
record — and a successor is `jv_record_set`, which shares every part of the
predecessor it did not change. That is tutuca's copy-on-write model rather than
a copy of it.

`Int` and `Double` are both `jv_f64`, because tutuca has exactly one number
(`Value::Num(Double)`). An `Int` field truncates at its assignment sites, which
is where the interpreter did it too, and what the corpus pins.

Every map is a **`jv_ordered_map`** and every set a `jv_ordered_set`, because
tutuca's `Value::Map` is MoonBit's `Map` and the renderer's `@each` indexes one
directly — see the note at the bottom.

**Components.** As many as the file declares. `viewfile` has always allowed
several — one `state` each in the one state block, one
`<script type="tutuca/script" for="Comp">` each, `<template id="Comp:main">` —
and this backend turned such a file away whole until it learned to number them.

Inside the module a component IS an index: its slot in `tc_types`, its arm of
the constructor, its fixed message/intent handlers and render operations. The constructor
was always handed the component's NAME and threw it away; it reads it now, with
the `tc_str_in` / `tc_is` pair every dispatch arm already used. An instance says
which component it is through `jv_record_definition` — the record carries its
own type, every successor keeps it, and each `jv_record_type_create` allocates a
fresh one, so identity is a pointer compare rather than a hidden field or a side
table three places would have to keep in step.

`get_field` and `with_field` needed nothing: they are `jv_record_get` and
`jv_record_try_set`, and the record already knows its own schema.

The ROOT — what a host mounts when told no other name — is the first component
in the file, or the one whose `<template>` carries `data-root`. The manifest
lists it first, because every mount site takes the head of `components`. It also
names `moduleName` and the descriptor's `core`.

**A child instance crosses the boundary.** `values.value`'s seventh case is
`%instance(u64)` — a same-bundle child, as the token `guest.instance` hands out
— and a compiled card could neither read one nor write one: the lowering knew
four tags and the lifting knew the same four, so a token handed in came back as
nil.

It is carried as `jv_i64`, and that is free rather than clever: this runtime
builds `jv_f64` and nothing else, because tutuca has exactly one number, so an
i64 inside a card's value tree can only be a child token. It is a SCALAR on the
wire rather than a handle into the value arena, so a card holding children and
no collections still imports no arena. A declared `Component[Row]` slot — or a
bare sibling name, which `statedef` resolves to one — holds it, `with-field`
puts one there, `get-field` reads it back, and a successor keeps it because
`jv_record_set` shares every part it did not change.

**And a card builds one.** `new <Component>` names a SIBLING — `new Todo` beside
`state Todo` — and the child is made by the host through
`control.make-instance`, which only such a card imports. A card that composes
children something else created names nothing on that interface, and the import
section is what a host reads to know which it has.

Nothing is built at the `new`. It opens an argument map for the component and
remembers which one; `@cur.text = .draft` accumulates into it, unchanged from
the read-modify-write it already was; and the child is made at the first READ of
`@cur` — the last moment the arguments can still change and the first moment
they are all in. Materializing rebinds the target to the token, so pushing
`@cur` twice pushes one child rather than making two. A `new` of a declared
record clears the marker, so a record can never materialize as a component.

The token is reserved during the guest call and the instance constructed after
it returns, because the Component Model forbids re-entering a component while a
call into it is active. So a guest cannot look INTO a child it just made — and
that is why reading or writing THROUGH a child slot is refused when the card
compiles rather than failing silently when it runs:

```
receive peek { .note = .rows[0].text }
// refused receive peek: `.rows` holds a child component, and a card cannot
// read or write through one — the instance belongs to the host and a guest
// holds only a token. Send it a message instead
```

The walk stops at the first type it cannot follow, so a `record` member is not
refused for being unrecognized: "this backend does not know" and "you may not"
are different answers.

**Declarations.** `receive`, `intent`, `compute`, `pred`,
`invariant`, `enrich`, `enrichScope`, property `get` / `set`, and the `requires` / `ensures` clauses
that attach to a transition.

The last two were the worst gap this backend had, and the only one that was
INVISIBLE: `DEnrich` and `DEnrichScope` appeared nowhere in this package at all,
so a card using `@enrich-with` compiled with no refusal to show for it and
quietly lost its bindings. Both compile now, and both are in the manifest under
keys that did not exist — a host cannot route to a name it was never told about,
which was the other half of the same hole.

**The render stack's row.** `@key`, `@value` and `@iter` arrive at a compiled
declaration as ARGUMENTS: `component/instance.mbt` passes them positionally
through the fixed `when` / `enrich` operations. A filter is written
`pred matches { … @value … }` with no parameter list at all, and every `@name` in
one used to be a refusal — so a compiled filter kept every row. The offsets
differ by shape, which is what `bind_index` is for:

| | handed | answers |
|---|---|---|
| `pred` through `@when` | `(key, value, iter)` | a yes or a no |
| `enrich` | `(binds, key, value, iter)` | the whole binding map |
| `enrichScope` | `()` | the whole binding map |

An enricher answers the map rather than writing into one, and that is the one
place the compiled shape had to differ from the interpreted one. The renderer
reads the map it PASSED IN — `render/render.mbt` discards an enricher's return
value, which is why `TypedInstance`'s adapter mutates its argument — and a guest
cannot mutate a host's map. So the guest returns one and
`dyncomp/host/dynobj.mbt` merges it back, minus `key` / `value` / `iter`, which
belong to the loop. Same contract, written on the side of the boundary that can
keep it.

**Statements.** `.field = e`, `+=`, `-=`, the same through a path
(`.a[k].b = e`), `if … else …`, the collection mutators `push`, `insertAt`,
`setAt`, `deleteAt`, `add`, `remove`, `toggle`, `new T`, and the effects
`send`, `sendAt`, `intent`, `forward`, `reply`, `fail` and `stop`.

`sendAt` addresses a PLACE — `&.rows[k].label` — and a place is reified rather
than read, because a position survives the root being rebuilt and that is what
makes an answer land on the row that asked for it. The generator does the same
walk at compile time that the corpus pins the meaning of, and the result is a
`list<control.path-step>` the flush lowers into linear memory. Which wire case a
keyed step becomes is decided at RUN time, because `.rows[k]` and `.panes[k]`
are the same syntax: a text key is an `item`, a whole non-negative number is an
`at`, and anything else is not a key at all and abandons the transition. One
form is refused — see below.

**Expressions.** Literals, `$'…'` templates, `.field` and a path into one, a
declaration's parameters, a bare or applied `compute`/`pred`/`invariant`,
`and` / `or` / `implies` / `not`, `is` / `is not` / `<` / `<=` / `>` / `>=`,
`+ - * /` `mod`, `if … else …` in a value position, and **all sixteen** reading
builtins — which this said before it was true of `num`, and now is.

A call takes as many arguments as it is written with, and so does a `send`.
Both used to stop at four, because the argument list was built by a
`tc_args1..4` family; it is a `pv_push` fold now and has no arity to run out of.

`num` and `int` read a **string** as well as a number, which is what
the corpus says — and they have no answer at all
for a value that is neither, so `num true` abandons the transition rather than
writing a null into the field. The decimal parser that makes this possible is
`runtime/parse_num.wax`, and it is carried only by a card that says one of the
two names: Wax's emitter does no dead-code elimination, so ~950 bytes for two
builtins most cards never write has to be made optional by the generator or not
at all. It is not correctly rounded — see the deviations below.

### `new`, and the one binding a handler owns

```
receive receipt {
  new Line
  @cur.what = .item
  @cur.qty  = .qty
  .receipt.push @cur
}
```

The zero is resolved and **built at compile time** — it is a property of the
declared type, and the type is written in the source — so a `new` naming a type
the card does not declare is rejected when it compiles rather than abandoned
when it runs. `@cur` is a single function-level local of type `&?jv_value`, so
"no `new` has run yet" is the null it starts at, and reading it before one has
fails the transition the way `read_place` says it must. A second `new` starts
over.

**A quirk, and why it needs no fix.** `@cur` is a function-level local, so a
`new` inside an `if` branch survives the branch. That is not this backend being
loose: the INTERPRETER does the same, because `exec` hands both arms the same
`Env` and `SNew` writes `env.binds` (`tscript/conformance`). Both agree,
which is what the corpus is for.

It is also not observable, because the checker will not let you look. `C::stmts`
merges the target across an `if` and keeps only what both arms agree on
(`tscript/check/check.mbt`): a `new` in one arm leaves it `TUnset`, and reading
`@cur` after that is `NO_TARGET`.

```
receive leak {
  if .n > 0 { new L }
  .xs.push @cur          // rejected: NO_TARGET
}
receive both {
  if .n > 0 { new L } else { new L }
  .xs.push @cur          // fine, and both arms built the same type
}
```

Scoping the local to the block would be the tidier language, but it would be a
change to the LANGUAGE — both backends and the checker together — rather than
to this one, and the checker already makes the difference unobservable.

## Rejected, and refused

Two different answers, and the difference is the whole of what a host does next.

**Rejected** is the card being turned away whole, because it does not check.
`compile` runs `tscript/check` before it builds a single instruction — the same
checker `check_card` runs — and a finding is an error:

```
rejected: this card does not check: line 5 [NO_NAME]: nothing here is called
`nope`; a bare name is a parameter, a builtin, or a `pred` or `compute` this
block declares
```

That is not a gap in this backend. `.count = nope` does not typecheck against
any backend, and a hand-written module could not compile it either — so
emitting a module with a hole where the handler should be, and letting the host
silently fall back, would turn a mistake into behaviour.

**Refused** is per-declaration: this backend cannot compile THAT yet, the rest
of the card still runs, and the host hears `unhandled` and falls back to the
mutator the declared field implies — exactly as it would for a handler nobody
wrote. The manifest leaves the name out too, so a host is never told a
component answers something it does not.

### What is still refused

| | why |
|---|---|
| `sendAt` **with a key read from live state** | `&.panes[.sel]` means "re-read `.sel` on every dispatch", which is what makes it follow a moving selection — `tscript/conformance` reifies it as a `SeqAccessStep` for exactly that. `control.path-step` has no case that says so, so there is nothing to lower it AS. Freezing the key would be a different path that looks like this one, so it is refused rather than approximated. A literal or a parameter key compiles |
| `@binding` **in a transition** | a handler is handed no row, so there is nothing for `@value` to mean there. In a `pred`, an `enrich` or an `enrichScope` it now compiles — see above. `@cur` is the other exception, and the only binding a handler owns |
| `$method`, `*dyn` | answered by the render stack, and a compiled handler runs after one |

Also `clear`, `delete`, `set` and `removeAt`: `tscript` parses them as
collection methods and **no backend has ever implemented them**, so there is no
behaviour to compile rather than a behaviour left uncompiled.

## The escape hatch: `<script type="tutuca/wax">`

**Rejected** is the card being turned away. **Refused** is one declaration this
backend cannot compile. There used to be no third answer, and there should have
been: tutuca's ahead-of-time path refuses a handler by name and hands it back as
an `update~` argument you write in MoonBit, and this path refused by name and
handed back *nothing*. A refused handler was simply absent, and the host fell
back to whatever mutator the declared field implied — a reasonable answer for a
handler nobody wrote, and a bad one for a handler somebody wrote and this
generator turned away.

So a card may carry a fourth block, and what you write in it is the language the
module is built out of anyway:

```html
<script type="tutuca/script">
  /// Checks, and REFUSED: a `sendAt` whose key is read from live state.
  receive ping { sendAt &.rows[.sel] 'ping' }
</script>

<script type="tutuca/wax">
  fn card_receive_ping(s: &jv_record_value, args: &?pv_vector) -> &?jv_record_value {
      tcx_send(utf8_from_bytes("ping"), tc_args1(get_sel(s)));
      null
  }
</script>
```

**A name, not an attribute.** `card_<role>_<name>` binds a function to a
declaration — `receive`, `intent`, `compute`, `pred`,
`invariant`. Anything else is a helper the escapes may call. Wax's attributes
are Wax's, and inventing a `#[card.on]` would mean teaching its front end about
cards.

| | signature | answers |
|---|---|---|
| a transition | `(s: &jv_record_value, args: &?pv_vector) -> &?jv_record_value` | the successor, or `null` for unchanged |
| a callable | `(s: &jv_record_value, args: &?pv_vector) -> &jv_value` | the value |

The script block need not declare the name at all — that is the second thing an
escape is for. A handler tutuca cannot express does not have to be written in
tutuca to be answered.

**You write the body and nothing else.** An escaped transition gets the same
wrapper a compiled one gets: the `requires` still guards, the `ensures` and the
invariants still hold, `tc_fail` is still read where the language answers
nothing, and the effects it buffers are still flushed only once every rule has
held. Those are the language's guarantees and none of them are yours to
reimplement.

### What you have to write with

The generator emits **per declared field**, and only for a card with an escape
block:

```wax
get_count(s)          -> &jv_value            // the field
set_count(s, v)       -> &jv_record_value     // the successor, schema-checked
num_count(s)          -> f64                  // Int and Double fields only
```

A card declaring SEVERAL components qualifies these — `get_Row_label`,
`set_Row_done` — because one module cannot hold two `get_label`. A card
declaring one does not, and that is deliberate: these names are documented as
what an escape author writes with, and a card that has not changed must not lose
its escape block to a feature it does not use. The binding name takes the same
optional segment: `card_Row_receive_toggle` as well as `card_receive_toggle`.

Two escape blocks defining the same helper is a `BadEscape` naming both
components. It has to be caught here — every block is spliced into one module,
so Wax would see a duplicate definition and this would report `BadModule`, whose
message says "this is a cardwasm bug". It is not; the card's author typed both.

These are the difference between an escape being writable and being a research
project: the generator reaches a field through `tc_get(s, tc_const_str(7))`, and
`7` is a constant-pool index only the generator knows.

`runtime/escape_help.wax` adds the short list of things that were awkward —
`tcx_fail()`, `tcx_send` / `tcx_stop`,
`tcx_str("literal")`, `tcx_int`, `tcx_failed()`. Everything else is already the
right shape and needs no wrapper: `tc_num` / `tc_bool` / `tc_text` / `tc_null`
for values, `tc_add`…`tc_mod` for arithmetic **with tutuca's semantics** (a
mixed `+` *fails* the transition, where an `f64` add written by hand would
silently join), `tc_eq` / `tc_cmp` / `tc_truthy` for tests, `tc_arg_at` and
`tc_args1..4` for arguments, `tc_step_field` / `tc_step_index` for paths,
`tc_method` and the `tc_m_*` constants for the collection mutators, and
`tc_display` for text.

The WAX panel beside the card is the discovery path. Read what the generator
emitted for the handlers that *did* compile, and write the missing one in the
same idiom.

### What it costs, and what it cannot do

**`allow_wax` is off by default**, and that is a trust decision rather than a
feature flag: a card is untrusted content in the `<mb-card>` story, so whether
one may carry hand-written code belongs to the host that mounts it. With it off
a block is a `Refusal` naming the block — refused, not ignored, because a card
whose escape silently did nothing is a card whose author cannot tell "the host
said no" from "I spelled the function wrong".

**The screen takes functions and refuses everything a guest's authority is made
of**: no `import`, no `memory`, no `data`, no `#[export]`, no `#[start]`, no
globals, and no name in a prefix the runtime has claimed. A guest's authority is
its import section — that is what `abi.mjs` inspects — so an escape that could
add an import could widen what the card may do. It cannot, whatever `allow_wax`
is set to. A block that breaks the screen is `BadEscape`, never `BadModule`:
that error's message says "this is a cardwasm bug", and the card's author typed
this.

**A card with an escape block widens its import section anyway.** Every other
conditional half is inferred from what a compiled body actually said; a
hand-written function is opaque to all of it, so the whole documented vocabulary
is made available and `control` and the value arena are imported whether or not
they are used. That is the real cost of the hatch and the second reason
`allow_wax` belongs to the host.

**One thing an escape cannot do**: a *compiled* callable cannot call an escaped
one. Wax resolves in one pass, and the compiled `cm_*` functions are emitted
before the escape block so that the escape can call them — the reuse direction,
which is the one worth having. The other way round reads as an ordinary refusal
(`callable_fields` refuses a callable whose dependency was refused), and the
answer is to escape both.

### The value arena, and why some cards import it

`values.value` carries `%list` and `%map` as u64 handles into a host-side arena,
because WIT has no recursive types. A card that can hold or build a collection
imports `tutuca:component/values`; one whose fields are all scalars does not —
`internal/waxsrc/runtime/lower_scalar.wax` and `lower_values.wax` are the two
halves, and exactly one is compiled in. Same argument `control` already made: a
host reads the import section to know what a guest can do.

Four more halves are cut the same way, and mostly for a *different* reason. The
lowering halves decide what the module IMPORTS, which is a statement about the
card; these mostly decide only what it WEIGHS:

| | carried by | |
|---|---|---|
| `runtime/parse_num.wax` | a card saying `num` or `int` | the decimal parser |
| `runtime/send_at.wax` | a card saying `sendAt` | reifies and lowers a `&.place` |
| `runtime/contract_log.wax` | a card declaring a rule | the line a declined rule says — and this one DOES reach the import section, through `control.log` |
| `runtime/escape_help.wax` | a card with a `tutuca/wax` block | the `tcx_*` vocabulary a hand-writer reaches for |

All of them exist because Wax's emitter does no dead-code elimination, so a
piece only some cards can reach has to be left out by the generator or carried
by everyone.

## Held to the corpus

`tscript/conformance/corpus.mbt` is the language's semantics as data, and
`test/conformance.test.mjs` is this backend's adapter over BOTH its tables —
each case becomes a card, gets compiled, and is driven through the same
`abi.mjs` a downloaded bundle gets.

`cmd/card-corpus` writes the table out as JSON, because a compiled card can only
be run from node. It is a PROJECTION and nothing else: both tables state their
answers as data. That used to be false of the transitions — an effect was stored
as a printed line, so the values had to be recovered by RUNNING the interpreter,
which made this backend's conformance harness depend on the interpreter
existing. `CaseEffect` is what fixed it, and removing the interpreter is what
made fixing it necessary.

**50 pass, 3 are rejected as invalid, 0 are refused, 0 fail.**

And `corpus.mbt`'s OTHER table — `value_cases()`, seventeen rows about what a
block SAID rather than what the state became — is now driven too. It was not
before, and that is where this backend's worst gap lived: `enrich` and
`enrichScope` were absent from the generator entirely, which no table was asking
about. **17 pass, 0 fail.**

The first run of it found a family of real divergences, all the same mistake:
`lower`, `upper`, `trim`, `contains`, `has`, `len`, `min`, `max` and `clamp`
answered something PLAUSIBLE for an argument of the wrong shape — the value
unchanged, or `false`, or zero, or a comparison that read two strings as numbers
— where `tscript/conformance` answers `None` and abandons the transition. All nine
now fail where the language answers nothing. A plausible answer is the worse one
here:
"the transition did not happen" is something a card author can see, and `false`
is not.

The three rejected are cards that do not check — a name that resolves to
nothing, arithmetic on a String, and `@cur` read before any `new`. Nothing is
refused any more, and the adapter asserts that: the refusal count used to be a
number allowed only to shrink, and a number with nothing left in it is better
spelled as the empty list.

## A bug this turned up

`with-field` receives a value JOINED — every case of `values.value` widened to
one `(i64, i32)` pair — and the lift that read that pair knew the four scalar
cases and answered nil for the rest. So a host handing a card a LIST got null,
null is not a vector however the field is declared, and the write was refused.
Every card, every list, since the arena landed; `Cart`'s `history` could be
built by the card and never handed back to it.

It surfaced here because a child inside a list is written back as the parent's
WHOLE list, so a row that toggles is a list handed in. The fix is not a fifth
arm: the joined triple is written into a cell and handed to `tc_lift_cell`,
which is defined by whichever lowering half the build got — so there is one lift
again, and a card without an arena still carries no code that mentions one.

## Known deviations

- **Number formatting.** `tc_num_text` prints the integer part exactly and up to
  six fractional digits with the trailing zeros trimmed. It is not a
  shortest-round-trip formatter: `0.1 + 0.2` reads as `0.3`. Anything at or
  above 1e15 reads as `Infinity`.
- **Number *parsing* is the same trade in reverse.** `tc_parse_f64` reads an
  optional sign, digits with an optional fraction and an optional exponent, and
  nothing else — no hex float, no `inf`, no `nan`, none of which a card has a
  way to write. It accumulates the mantissa by multiplication rather than
  correctly rounding, so a long decimal can land an ulp from what
  `@string.from_str` reads. The spellings a card writes by hand are exact.
- **`with-field` is stricter.** The schema validates, so a value whose type the
  field cannot hold answers `none` and the host falls back.
- **A declined rule reports a LINE, not a record.** A `requires`, `ensures` or
  `invariant` that does not hold makes the transition not happen, and the card
  now says so through `control.log` — the same sentence `core/warn.mbt` prints,
  including the rule's own `format` clause evaluated over the state that was
  rejected. What does not cross is the structured `Refusal` a host component
  raises, with the state inside it: the guest world has no shape for that, and
  `log` is the simplest thing on `control`. A card that
  declares a rule therefore imports `control.log`, which is a true statement
  about the card.
- **`tutuca/init` fixtures are dropped** from the manifest. Their field values
  are MoonBit source and a manifest wants JSON.
- **utf8, not utf16.** The shipped MoonBit guests are built `--encoding utf16`;
  these declare `utf8`, which `abi.mjs` implements just as well.
- **Nothing is freed.** Instances live in a growing table because the ABI's
  `resource_new` takes an i32 rep and a GC reference is not one; linear memory
  is still a bump allocator with no free. Both are the lifetime of one
  edit-and-mount, which is what `cabi_post_*` being a no-op means.

Three things that used to be on this list and are not any more.

Two were found by the corpus: `+` on a mixed pair now FAILS the transition
rather than joining, which is what the corpus says; and an
effect performed before a failing statement no longer escapes, because effects
are buffered in the guest and flushed only once every rule has held.

The third was **map insertion order**, and it was fixed upstream. tutuca's
`Value::Map` is MoonBit's `Map`, which is insertion ordered — re-assigning a
key keeps its place, removing drops it, re-adding appends — and the renderer's
`@each` indexes a map directly (`core/value_dyn.mbt`), so a view looping over a
map field renders in that order. A HAMT rendered it in the trie's. The Wax
standard library grew `jv_ordered_map` and `jv_ordered_set` with exactly that
contract; every map this compiler builds is one, and the test that used to pin
the divergence now asserts the order.

## Building and testing

```sh
moon check                                        # every target
moon test                                         # the vendored sources compile
node tutucard/wasm/internal/waxsrc/build/check-runtime.mjs   # ... and faster
node --test 'tutucard/wasm/test/*.test.mjs'       # the ABI suite AND the corpus
node tutucard/wasm/internal/waxsrc/build/vendor-embed.mjs    # stdlib_src_gen.mbt
```

`internal/waxsrc/stdlib_src_gen.mbt` is GENERATED from `internal/waxsrc/vendor/`
and `internal/waxsrc/runtime/`, and checked in. Do not hand-edit it: re-vendor
upstream, rerun `vendor-embed.mjs`, and commit both halves.

## Why half the runtime is Wax source

`internal/waxsrc/runtime/` is `.wax` rather than a tree the generator builds.
Everything in there is identical in every card — there is nothing for a
generator to decide — so building it as an AST meant five hundred lines of
MoonBit spelling out `call(...)` and `if_(...)` to say what a hundred lines of
Wax say directly. The per-card half is still an AST, because that is where the
decisions are.

The cost is that the Wax **front end** is in the bundle, where the generator is
otherwise AST-first through `marianoguerra/wax/compile` and never links the
lexer, the token table or the generated LR parser. That cost was going to be
paid anyway: the stdlib is distributed as source, and using it means parsing it.

## The one thing to know about Wax's AST

Every identifier a generator builds needs a **distinct source location**. A
`let` binding's local slot is recorded against the binding's source offset, so a
whole function's identifiers built at one location collapse its locals onto one
slot. Wax refuses that outright (`AmbiguousBinding`), and `@build.Spans` is
upstream's answer to it; `dsl.mbt`'s `id` is a thin wrapper over one.

There used to be a `reference/counter.wax` beside this — the canonical ABI
hand-written once, in ~180 readable lines. It went with the contract it was
written against: it held its state as `values.value` cells in linear memory,
which is what this did before the state became a `jv_record`, and it exported
the five-case `bucket` enum. What it demonstrated — the export names, the return
areas, the joined `with-field` payload and the three-way `event-result` — is
unchanged, and `dispatch.mbt` is where those are now read off.
