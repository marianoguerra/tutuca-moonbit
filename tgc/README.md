# `tgc/` — the wasm-GC component format

The one-line version: a component is **one core wasm module** using the GC
proposal, and components written by strangers compose at runtime because wasm
GC canonicalizes a type group *structurally*, so carrying the same text is the
whole of the agreement.

Read [`SPEC.md`](SPEC.md) for the format. This page is the tree.

| | |
|---|---|
| `abi/` | the FROZEN preamble, op codes, tag numbers and export names. One table, two renderings (Wax and WAT). Nothing else may spell these. |
| `value/` | the canonical value host-side, plus CBOR and JSON both ways |
| `rt/` | `tutuca-rt` — the shared function vocabulary, as a module |
| `emit/` | card → `tgc` module. The third backend over `tscript`'s one AST. |
| `host/` | `values.mjs` — `core.Value` JSON ↔ `tg_val`, the one copy |
| `proto/` | three components, produced three different ways |
| `test/` | the proofs |

## The proof

```sh
node --test tgc/test/compose.test.mjs
```

Fourteen assertions, each one a thing `tutuca:component@0.12.0` cannot do, with
the reason named in the comment beside it. The three that matter most:

- a component **holds another module's instance in its own state** and reads a
  field **through** it — the current format refuses this when the card compiles,
  because "a guest holds bridge handles, not pointers";
- a module is **re-entered while a call into it is active** — the Component
  Model forbids exactly this;
- a module whose preamble was **spelled differently by a different toolchain**
  composes, and one with **one extra type inside the frozen group** is refused
  at link rather than by a cast that traps three calls later.

## The corpus

```sh
node --test tgc/test/conformance.test.mjs
```

`tscript/conformance` is the language's semantics as data, and `tgc/emit` is the
third implementation of them. **48 of 48**, both tables — the thirty
transitions, and the seventeen rows about what a block *said* rather than what
the state became. That second table is where `tutucard/wasm`'s worst gap lived
and it was invisible: `enrich` and `bindWith` appeared nowhere in its generator,
so a card using them compiled with no refusal to show for it and quietly lost
its bindings. No transition case was asking.

A backend not driven by the corpus is a backend with its own semantics.

## In the card playground

The playground compiles, mounts and downloads a `tgc` module beside the one the
old backend makes. Pick the backend in the header; the source does not change,
only what compiles it.

Mounting reuses the whole existing host. `tutucard/web/card-tgc.js` installs the
same `__cardguest[key]` surface `card-wasm.js` does, so `cardguest.mbt` mounts a
`tgc` module unchanged and the views, renderer, dispatch and transactor above it
are the ones that were already there. **That reuse is the claim, not a
shortcut**: what the format replaced is the guest boundary and nothing above it.

Two things are simpler on that boundary, and both are the format:

- **there is no arena** — a compound value crossed the old one as a `u64` handle
  into a host table valid for one call, because WIT has no recursive types.
  Here a value is a reference;
- **there is nothing to sweep** — an instance is a GC struct and the engine
  collects it. The handle map exists only because MoonBit's js target passes
  integers across the seam.

The download is **one file**. There is no archive to build and no manifest to
ship beside it, which is what lets a toolchain that has never heard of this page
produce one. The runtime downloads separately, because `tut` is shared — one per
page, not one per card.

`node --test tgc/test/guest.test.mjs` drives that bridge with no browser. A
bridge only a page can exercise is a bridge nobody exercises.

## Three routes, on purpose

`proto/` has one component per production route, because "different toolchains
compose" is the claim and three copies of one route would not test it.

| | route |
|---|---|
| `dashboard.body.wat` | hand-written WAT. The builder prepends the canonical preamble; the author never types the types. |
| `counter.wax` | Wax, compiled by `marianoguerra/wax` through `cmd/tgc`. A **compiler** emitted this preamble, from `abi/`. |
| `clock.whole.wat` | a COMPLETE module carrying its own preamble, spelled its own way — different type names, different field names, an unrelated group declared first, functions in a different order. Nothing shared but the shape. |

## The toolchain

```sh
moon run --target native cmd/tgc -- preamble --wax   # or --wat
moon run --target native cmd/tgc -- build in.wax out.wasm
node tgc/test/build.mjs                              # build everything
```

`tgc preamble` exists so a hand-writer never copies the types out of a file that
might have moved on. Ask for them.

## Writing a module in Wax: five things that will bite

All five cost time once. None of them are in Wax's own README.

- **`tag` is a reserved word** (wasm's exception-tag section), so the
  discriminator field is spelled `kind`. That is why the frozen group says
  `kind` and not `tag`.
- **A function used as a vtable value must be declared with the named type**:
  `fn counter_get: tg_get(self: &tg_inst, …)`. An inline signature is an
  identical-LOOKING type in a new singleton group, and a reference to it is not
  a `&tg_get`. The same trap exists in WAT — `(func $get (type $tg.get) …)` —
  and it is the freeze rule biting at the smallest possible scale.
- **There is no `&&`.** Nest the `if`s.
- **A mutable local is `let x: i32 = 0;`** — the type annotation is what makes
  it a local rather than a binding. A mutable global is the same, at the top
  level.
- **A string literal is already `[mut i8]`**, which IS `tg_bytes`. So
  `str_eq(name, "count")` needs no conversion, no interning table and no
  constant pool. That is luck rather than design, and it is one reason the
  format's text type is a byte array.

## The one thing to know

**The core rec group is frozen.** A rec group's identity depends on the whole
group, so adding a type to it, reordering it, or changing one field breaks the
identity of *every* type in it, in every module ever built, retroactively.

Extend through `tg_ext` and through the op space. Both are designed for it; the
group is not.
