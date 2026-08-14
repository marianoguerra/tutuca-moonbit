# tutucard/wasm

Compile a [tutucard](../) `.html` file into a `tutuca:component@0.7.0` **core
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

The third backend over `tscript`'s one AST. `tscript/interp` runs a card where
it stands; `tscript/emit_mbt` turns one into MoonBit ahead of time; this one
compiles it. All three are held to `tscript/conformance`, because a language
with three implementations and no shared table has three semantics.

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
is where `coerce_root` does it in the interpreter.

Every map is a **`jv_ordered_map`** and every set a `jv_ordered_set`, because
tutuca's `Value::Map` is MoonBit's `Map` and the renderer's `@each` indexes one
directly — see the note at the bottom.

**Declarations.** `on`, `receive`, `bubble`, `response`, `compute`, `pred`,
`invariant`, and the `requires` / `ensures` clauses that attach to a transition.

**Statements.** `.field = e`, `+=`, `-=`, the same through a path
(`.a[k].b = e`), `if … else …`, the collection mutators `push`, `insertAt`,
`setAt`, `deleteAt`, `add`, `remove`, `toggle`, `new T`, and the effects
`send`, `bubble` and `stop`.

**Expressions.** Literals, `$'…'` templates, `.field` and a path into one, a
declaration's parameters, a bare or applied `compute`/`pred`/`invariant`,
`and` / `or` / `implies` / `not`, `is` / `is not` / `<` / `<=` / `>` / `>=`,
`+ - * /` `mod`, `if … else …` in a value position, and **all sixteen** reading
builtins.

### `new`, and the one binding a handler owns

```
on receipt {
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
`Env` and `SNew` writes `env.binds` (`tscript/interp/run.mbt`). Both agree,
which is what the corpus is for.

It is also not observable, because the checker will not let you look. `C::stmts`
merges the target across an `if` and keeps only what both arms agree on
(`tscript/check/check.mbt`): a `new` in one arm leaves it `TUnset`, and reading
`@cur` after that is `NO_TARGET`.

```
on leak {
  if .n > 0 { new L }
  .xs.push @cur          // rejected: NO_TARGET
}
on both {
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
checker `tutucard.load` runs — and a finding is an error:

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
| `request` | **NOT IMPLEMENTED.** A request carries a `request-opts` record and expects a `response` back, so it needs the record lowered into the canonical ABI and the response bucket wired to the reply. Neither is hard; neither is written. This is the one genuine gap the corpus still shows. |
| `sendAt` | carries a relative path, which would have to be reified into `core.Step`s and lowered |
| `@binding`, `enrich`, `enrichScope` | a binding the render stack provides, and a compiled handler runs outside one. `@cur` is the exception — see above |
| `$method`, `*dyn` | answered by the render stack, for the same reason |

Also `clear`, `delete`, `set` and `removeAt`: `tscript` parses them as
collection methods and **the interpreter does not implement them either**, so
there is no behaviour to compile rather than a behaviour left uncompiled.

### The value arena, and why some cards import it

`values.value` carries `%list` and `%map` as u64 handles into a host-side arena,
because WIT has no recursive types. A card that can hold or build a collection
imports `tutuca:component/values`; one whose fields are all scalars does not —
`internal/waxsrc/runtime/lower_scalar.wax` and `lower_values.wax` are the two
halves, and exactly one is compiled in. Same argument `control` already made: a
host reads the import section to know what a guest can do.

## Held to the corpus

`tscript/conformance/corpus.mbt` is the language's semantics as data, and
`test/conformance.test.mjs` is this backend's adapter over it — each case
becomes a card, gets compiled, and is driven through the same `abi.mjs` a
downloaded bundle gets.

**49 pass, 3 are rejected as invalid, 1 is refused, 0 fail.**

The three rejected are cards that do not check — a name that resolves to
nothing, arithmetic on a String, and `@cur` read before any `new`. The one
refusal is `request`.

## Known deviations from the interpreter

- **Number formatting.** `tc_num_text` prints the integer part exactly and up to
  six fractional digits with the trailing zeros trimmed. It is not a
  shortest-round-trip formatter: `0.1 + 0.2` reads as `0.3`. Anything at or
  above 1e15 reads as `Infinity`.
- **`with-field` is stricter.** The schema validates, so a value whose type the
  field cannot hold answers `none` and the host falls back.
- **A declined rule is silent.** A `requires`, `ensures` or `invariant` that
  does not hold makes the transition not happen, and the `format` sentence it
  declares is not reported: there is no channel in the guest world for a
  refusal record yet.
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
rather than joining, which is what `interp/eval.mbt`'s `arith` does; and an
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

`reference/counter.wax` is the canonical ABI hand-written once, in ~180 readable
lines. It is no longer a **diff target** — it holds its state as `values.value`
cells in linear memory, which is what this did before the state became a
`jv_record` — but the export names, the return areas, the joined `with-field`
payload and the three-way `event-result` have not moved.
