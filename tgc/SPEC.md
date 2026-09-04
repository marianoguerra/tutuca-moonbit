# `tgc/1` — a WebAssembly component format on core wasm + GC

Everything below is implemented and tested (`tgc/abi`, `tgc/emit`,
`tgc/test/`). It is core wasm plus the GC proposal and nothing else — no
Component Model, no WIT, no archive, no linear memory. See
[`../docs/dynamic-components.md`](../docs/dynamic-components.md) for the
practical route in, and [`SECURITY.md`](SECURITY.md) for what a loaded module
can and cannot do.

## 1. What this is, in one paragraph

A component is **one core WebAssembly module** using the GC proposal and
nothing else: no component model, no WIT, no archive, no linear memory, no
table. Modules built at different times by
different people with different toolchains instantiate together and compose
into one tree. They agree because they carry the same **type preamble** —
and wasm GC canonicalizes a recursion group *structurally*, so carrying it is
the whole of the agreement.

## 2. The mechanism

Two modules that declare the same rec group — same order, same field types,
same subtyping — receive the **same runtime types**. A reference built in one is
readable in the other with no conversion. An import whose signature mentions
those types type-checks at link.

There is therefore no registry, no linker, no shared instance type and no
negotiated ABI. There is a text file.

**The rule that makes this survivable:** a rec group's identity depends on the
*whole group*. Add a type, reorder, or change one field, and every type in it
becomes a different type — in every module, retroactively. So:

- The core group is **frozen**. Forever.
- Anything not mutually recursive with `tg_val` gets its **own** singleton
  group, so a later addition cannot perturb the core.
- Extension goes through `tg_ext`, never through a new arm.

`tgc/test/compose.test.mjs` tests both directions: a module with a
differently-spelled preamble composes, and a module with one extra type inside
the group is refused **at link**, with a message about the import — not by a
cast that traps three calls later.

## 3. The types

The canonical text lives in [`abi/preamble.mbt`](abi/preamble.mbt) and is
printed by `tgc preamble --wax` / `--wat`. Never copy it by hand; ask for it.

```
tg_bytes                      [mut i8]        UTF-8 text AND binary
tg_val      kind:i32          the open base; kind 0 is Null
  tg_bool     value:i32
  tg_num      value:f64
  tg_int      value:i64
  tg_str      value:&tg_bytes
  tg_bin      value:&tg_bytes
  tg_instant  secs:i64  nanos:i32
  tg_list     items:&tg_vals   count:i32
  tg_map      entries:&tg_entries  count:i32     insertion-ordered
  tg_func     call:&tg_fn  env:&?eq
  tg_comp     value:&tg_inst
  tg_ext      ext_kind:i32  payload:&?eq
tg_vt       get:&tg_get  call:&tg_call
tg_inst     vt:&tg_vt  desc:&tg_val  state:&?eq  id:i64
```

Decisions worth naming:

- **`ref.null` is absence; `kind 0` is the null value.** "There is no such
  field" and "the field is null" are different answers, and a format with one
  null needs an `option<value>` wrapper at every field to keep them apart.
- **`tg_bytes` is UTF-8** and carries binary too. The wire, the GC type and the
  JSON encoding all agree; a UTF-16 host transcodes at its own boundary
  rather than at every field. There is no per-module encoding choice, because
  the encoding is part of the type. In Wax it costs nothing extra: a string
  literal is already `[mut i8]`.
- **Two numbers.** `tg_num` is tutuca's double; `tg_int` is the 64-bit integer
  the GC types have natively and a double cannot hold past 2^53.
- **List and map carry capacity plus count**, because a wasm-GC array is
  fixed-length. The map is an entry array and stays in **insertion order** —
  `core.Value::Map` is MoonBit's `Map` and `@each` renders in that order, so an
  encoding that sorted keys would silently re-order a page.
- **The vtable has two slots and cannot grow.** `get` is separate only because
  it runs once per `.name` per render. Everything else is one op-coded `call`,
  and the op space is an `i32` — extensible forever without touching the group.
- **`state` is `&?eq`.** Each module casts it back to a type only it can name;
  anyone else **traps**. Opacity is enforced by the engine rather than by a
  handle table nobody may forge, which is both stronger and cheaper.

## 4. The instance is the composition story

`tg_inst` is an ordinary GC struct, so any module may hold one in its own state,
put it in a list, pass it on, and call it.

| the current format | `tgc` |
| --- | --- |
| a child is an opaque host token | a child is a `&tg_inst` in your own state |
| `.rows[0].text` is refused when the card compiles | a `call_ref` through the child's PROPERTY door |
| a foreign component cannot live in card state at all | any instance can, whoever built it |
| compounds are arena handles valid for one call | a value is a reference, and it lives |
| instances leak in a growing table | the engine's GC collects them |
| re-entering a component during a call is forbidden | core wasm has no such rule |

### Reading and writing THROUGH a held instance

`.child.body` is `member`, and `.child.body = x` is `with_member`, and when the
value is a `tg_comp` both go through the property door: **op 8 to read, op 9 to
write**, never the `get` slot.

`get` is the private field slot, and a holder is precisely the thing that holds
components it did not write — so reading through `get` would make every field of
every component legible to whoever happened to hold it. The declaration is the
whole permission: a field with no `property` beside it is private, and stays
private however it is held.

The write answers a SUCCESSOR instance, like every other transition here, so a
holder that writes through its child ends up holding a different child than it
started with. A property the component did not declare writable answers
`ref.null`, and `ref.null` is no successor rather than a successor that quietly
kept the old value.

## 5. Ops

`call(self, op, name, args, v) -> &?tg_val`. A module that does not know an op
answers `ref.null` — the same answer an older module gives for an op invented
after it was built, which is what makes the space extensible rather than merely
large.

| op | | op | |
| --- | --- | --- | --- |
| 1 | withField | 9 | setProperty |
| 2 | handleMessage | 10 | seqEntries |
| 3 | handleIntent | 11 | implements |
| 4 | compute | 12 | persist |
| 5 | when | 13 | restore |
| 6 | enrich | 14 | identity |
| 7 | enrichScope | 15 | debug |
| 8 | getProperty | | |

A transition (`handleMessage`, `handleIntent`, `withField`, `setProperty`)
answers `tg_comp(successor)` or `ref.null` for "nothing changed". Copy on
write, which is the language's model rather than an imitation of it.

## 6. Exports and imports

| export | shape |
| --- | --- |
| `tgc.abi` | the ABI version — a mismatch is refused, never adapted |
| `tgc.describe` | `() -> &tg_val` — the manifest, as a value |
| `tgc.make` | `(&tg_bytes, &?tg_val) -> &?tg_inst` |
| `tgc.serve` | `(&tg_bytes, &tg_vals) -> &?tg_val` — module-scoped `lex`-leg intents |

The manifest is an ordinary value, so **a module is the whole distribution**.
No tar, no `tutuca.json` beside it, no packer — which is what lets a toolchain
that has never heard of this repository produce one.

Everything a module may reach comes from the namespace **`tut`**. A module
declares no memory and no table, so its import section is its *complete*
authority list — the property `tgc/SECURITY.md` relies on today, made
total. `tgc/test` asserts it for every prototype module.

And it DISCRIMINATES: `tgc/emit` writes the body first and then imports what the
body turned out to call, so a card that performs no effect imports none of the
machinery for one. A section written before the body would be a statement about
what a card COULD do, which is a different and much less useful claim.

## 7. Matching is by protocol

`desc` is that component's slice of `tgc.describe` — its name is under `name`. A slot declares a protocol
id (`statedef` already has them: `ProtocolDef.id`, `core.Ty::TyCompProtocols`)
and any module declaring the same id can fill it. Asked of the instance through
op 11, so there is no catalog in the path at all.

This replaces a flat `by_name` whose last registration silently wins, and a
registry that breaks a tie by "most recently loaded".

## 8. Encoding

One, `$`-tagged JSON, because a value crosses this boundary in a browser and a
browser parses JSON without a library. It is written and read by
`tgc/host/values.mjs` on the page side and `core`'s `Value::to_json` /
`Value::from_json` on the MoonBit side.

### JSON

```json
{"$": "int",     "v": "9007199254740993"}
{"$": "bin",     "v": "SGVsbG8="}
{"$": "instant", "v": "2025-09-03T16:00:00.123Z"}
{"$": "comp",    "v": {"module": "…", "component": "…", "state": "Bw=="}}
{"$": "ext",     "tag": 99, "v": …}
{"$": "map",     "v": { … }}
```

The last line is the **escape**, and it is not optional: a map whose own keys
include `"$"` is written tagged too. Without it, `{"$":"bin"}` as data and the
same six bytes as a tag are indistinguishable and a decoder has to guess.

Sub-second digits go in groups of three — milliseconds, microseconds,
nanoseconds — with trailing all-zero groups dropped, so a whole second has no
fraction. That is a spelling rule; the value round-trips exactly either way.

**The asymmetry, stated rather than hidden:** a plain JSON number decodes to
`tg_num`, because a JSON number *is* a double and pretending otherwise past
2^53 would invent precision the input never had. A producer that needs a
`tg_int` back writes the tagged form, which the encoder always does — which is
why the tagged form is not an option a producer may skip.

## 9. Two nulls, and the rule that falls out of them

`ref.null` means **no answer**; `kind 0` is the **null value**. Keeping them
apart is not fussiness — it is what lets a runtime operation with no answer for
its arguments return null and have that null propagate through everything above
it, so a compiled body checks once instead of threading a failure flag through
every operand. `len true` is not zero. `min` of a string and a number is not the
string. `.note is null` is still a real question.

The two part at exactly one boundary, and that is the rule:

> A **transition** with no answer **does not happen**.
> A **callable** with no answer **answers Null**.

Both are the same `ref.null` on the way up. A transition's is the successor that
was not built — the state does not change, and a scene asserts that. A
callable's is a value, because a `compute` was asked for one and Null is what it
has. `tscript/conformance` pins both.

## 10. What the card compiler compiles

`tgc/emit` is one of two backends over `tscript`'s one AST, beside
`tscript/emit_mbt`, and it is held to
`tscript/conformance` — **48 of 48**, both tables (`tgc/test/conformance.test.mjs`).

### A protocol operation has ONE dispatch name

A handler answers the SCHEMA's runtime name, never the declaration's own
spelling. `receive Holder::hold` names the protocol by the alias this file
imported it under; the schema resolved that to `x/Holder@1::hold` before the
script was read, and that resolved name is the only one a host has ever heard
of. Both the module's `call` and the manifest's `receives` use it.

That is the same rule `tscript/emit_mbt` follows, and it has to be: a host
holding one compiled-in component and one card, both implementing the same
protocol, names a message once and reaches both. A backend answering its own
local spelling makes the two uninterchangeable, which is the claim the whole
format rests on.

The outbound direction resolves the same way — `ask Holder::addRequested` raises
`x/Holder@1::addRequested` — so one protocol crosses in one vocabulary whichever
way a message is going.

### What implementing a protocol is checked to mean

`check_card` holds a component to the protocols it CLAIMS, and there are two
questions behind that:

- the SCHEMA's — does the spec block declare the protocol's operations at all?
  `statedef.validate_protocols` answers it, and its findings arrive as ordinary
  issues.
- the SCRIPT's — is there a handler that ANSWERS each declared operation, under
  the name a host dispatches? A card can declare
  `handle Hole { message { Holder::hold(Any) } }` and write `receive hold`, and
  then it answers `hold` while its manifest claims a protocol whose operation is
  `x/Holder@1::hold`.

Both are ERRORS. `SchemaInfo::conforms` refuses such a component when a host
fills a slot with it, so the card is already broken — it just says nothing until
something tries to use it, and by then the failure is a long way from the line
that is wrong.

The express side is the schema's question alone: nothing in a script declares an
outbound name.

Every declared field is one slot in a `tg_vals`, whatever its type. A
specialising backend would unbox an `Int` field and save a `struct.new` per
assignment; this one gets `get_field` and `with_field` for two lines each and no
per-type path to get subtly wrong. The declared type still decides the zero and
still truncates an `Int` at its assignment sites, which is where the semantics
live.

The render row — `@key`, `@value`, `@iter` — arrives **positionally**, because
a compiled declaration runs after the render stack rather than inside it:

| | handed | answers |
|---|---|---|
| `pred` through `@when` | `(key, value, iter)` | that value's truthiness |
| `pred` read as a method | its own parameters | its own expression |
| `enrich` | `(binds, key, value, iter)` | the whole binding map |
| `bindWith` | `()` | the whole binding map |

An enricher **answers** the map rather than writing into one. That is the single
place the compiled shape has to differ from the interpreted one: the renderer
reads the map it passed in, and a guest cannot mutate a host's map.

Effects are `tut` imports and the **host** buffers them, because the host
brackets the call and therefore knows when it ended — an effect performed before
a statement that abandons is discarded with the transition.

### Held to the playground too

`tutuca/build/assemble.mjs` puts this backend beside the other one in the card
playground, and every starter card is driven through both. **26 of 26 compile, and every card's scenes pass.** One card,
`raw-html`, is refused before it mounts — by the SANITIZER, identically under
both backends, because `@dangerouslysetinnerhtml` cannot be checked before it
renders.

Eight things that only running it in a browser found, each now fixed and each
worth naming because none of them showed up in the corpus:

- **Fixtures were dropped**, so a card mounted at its declared zero and every
  string field rendered empty. The `args` half of an `InitState` is perfectly
  JSON-able; only the `fields` half is MoonBit source.
- **The checker was handed one component's `StateDef` alone**, so `new TodoItem`
  — a SIBLING in the same spec block — was `NO_TYPE` and the whole card was
  rejected. A `Surface` naming the siblings is the fix.
- **Invariants were only checked when a handler named one.** An invariant is
  the rule nothing has to mention, checked after every transition; without that,
  `overbook` seated seven people in a room with six chairs.
- **A declined rule said nothing.** A transition that stops silently is
  indistinguishable from a click that missed — the state is the same either way
  and the DOM cannot tell them apart. The sentence is `core/warn.mbt`'s, word
  for word, with the rule's own `format` clause after it.
- **A view set was matched by its raw name**, so a card with a bare
  `<template>` — which names no component and therefore takes the card's own
  name — mounted with no view at all. `ViewSet::component_name` is what answers
  that question.
- **Every instance carried the MODULE's descriptor**, so a card declaring
  several components drew the root's view for every child. A descriptor is per
  component; `desc` is how an instance says what it is.
- **`setAt` always indexed**, so writing a keyed row into a `Map` field
  abandoned the transition. Which kind of position a key names is decided by the
  COLLECTION at run time — `.rows[k]` and `.panes[k]` are the same syntax.
- **`provide` and `lookup` were absent from the manifest**, so a `*name` in a
  child's view answered nothing and the child drew, correctly, with every
  provided value blank.

### Still refused

| | why |
|---|---|
| `sendAt` with a key read from live state | `&.panes[.sel]` means "re-read `.sel` on every dispatch", which is what makes it follow a moving selection. The host's path has no step that says so, and freezing the key would be a different path that looks like this one. A literal or a parameter key compiles. |
| `$method`, `*dyn`, `e.` paths, `^macro`, `host.config` | answered by the render stack or by the view parser, and a compiled handler runs after both |
| `clear`, `delete`, `set`, `removeAt` | parsed as collection methods that no backend has ever implemented, so there is no behaviour to compile |

### Known deviations

- **Number formatting.** The integer part is exact and up to six fractional
  digits are written with trailing zeros trimmed, so `0.1 + 0.2` reads as `0.3`.
  At or beyond 2^63 a number reads as `Infinity`.
- **Number parsing** is the same trade in reverse: sign, digits, fraction,
  exponent, and nothing else. The mantissa accumulates by multiplication rather
  than rounding correctly, so a long decimal can land an ulp out. The spellings
  a card writes by hand are exact.
- **`lower` / `upper` are ASCII.** A case fold that claimed to know Turkish
  would be a bigger promise than this makes.

## 11. What is not here yet

- **A `tgc`-native `&Obj`.** The host mounts a module through `tgc/host`, which
  wraps it as an ordinary `&Obj` over the `__cardguest` JSON surface. Nothing
  downstream can tell that from a compiled-in component, which is why it works
  — but it means a value crossing into the host is re-spelled as JSON rather
  than handed over as the `tg_val` it already is. A wrapper written directly
  against `tg_inst` is the next thing.
- **Worker isolation.** `tgc/SECURITY.md` §7 leaves a runaway call open, and
  nothing here closes it.
