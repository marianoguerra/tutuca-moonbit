# `tgc/` — the wasm-GC component format

The one-line version: a component is **one core wasm module** using the GC
proposal, and components written by strangers compose at runtime because wasm
GC canonicalizes a type group *structurally*, so carrying the same text is the
whole of the agreement.

Read [`SPEC.md`](SPEC.md) for the format. This page is the tree.

| | |
|---|---|
| `abi/` | the FROZEN preamble, op codes, tag numbers and export names. One table, two renderings (Wax and WAT). Nothing else may spell these. |
| `rt/` | `tutuca-rt` — the shared function vocabulary, as a module |
| `emit/` | card → `tgc` module. The third backend over `tscript`'s one AST. |
| `host/` | the host side: the `&Obj` wrapper, the manifest, `register_module`, and `values.mjs` — `core.Value` JSON ↔ `tg_val`, the one copy |
| `policy/` | what a host will accept from a module it did not write |
| `persist/` | a component that has to outlive the page |
| `proto/` | three components, produced three different ways |
| `test/` | the proofs |

## The proof

```sh
node --test tgc/test/compose.test.mjs
```

Sixteen assertions, each with the reason named in the comment beside it. The
four that matter most:

- a component **holds another module's instance in its own state** and reads a
  field **through** it — one `call_ref`, no host hop and no token table;
- a module is **re-entered while a call into it is active**, and copy on write
  keeps that from becoming a cycle: writing into A answers a NEW A, so the
  write that would close the ring is the write that leaves it open;
- a module whose preamble was **spelled differently by a different toolchain**
  composes, and one with **one extra type inside the frozen group** is refused
  at link rather than by a cast that traps three calls later;
- a **mutable array handed IN** stays a channel into the module's state — the
  one ordinary way to build a real cycle, and the engine's stack ends it with a
  trap. See [`SECURITY.md`](SECURITY.md) §3a.

## The corpus

```sh
node --test tgc/test/conformance.test.mjs
```

`tscript/conformance` is the language's semantics as data, and `tgc/emit` is the
third implementation of them. **48 of 48**, both tables — the thirty
transitions, and the seventeen rows about what a block *said* rather than what
the state became. That second table is the one worth having: a generator can
drop a declaration like `enrich` or `bindWith` entirely and still pass every
transition case, compiling with no refusal to show for it and quietly losing the
bindings, because no transition case is asking.

A backend not driven by the corpus is a backend with its own semantics.

## In the card playground

The playground checks, compiles, mounts and downloads a module, in the page,
with no toolchain.

Mounting reuses the whole existing host. `tutucard/web/card.js` installs the
`__cardguest[key]` surface, `cardguest.mbt` implements `&Guest` over it, and the
views, renderer, dispatch and transactor above that are ordinary. **That reuse
is the claim, not a shortcut**: the format is the guest boundary and nothing
above it.

Two things the boundary does not need, and both are the format:

- **there is no arena** — a value is a reference, so nothing has to be copied
  into a host-side table for the duration of a call;
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
