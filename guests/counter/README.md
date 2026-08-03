# counter — a `tutuca:component` guest

The reference guest for the dynamic-wasm-component design
([`../../dyncomp/DESIGN.md`](../../dyncomp/DESIGN.md)): a counter with
opaque native state and tutuca view strings, compiled to a WebAssembly
component any `tutuca:component` host can load. This README is the shared
reference for every MoonBit guest — [`../table`](../table/README.md),
[`../todo`](../todo/README.md), [`../todomvc`](../todomvc/),
[`../calculator`](../calculator/README.md) and
[`../tictactoe`](../tictactoe/README.md) have the same shape and differ only in
what they compute.

## Layout

- `moon.mod`, `gen/`, `interface/`, `world/` — `wit-bindgen moonbit`
  output (committed; regenerate with the task below)
- `gen/interface/tutuca/component/guest/sdk.mbt` — a copy of
  [`../sdk.mbt`](../sdk.mbt), the canonical guest SDK: it implements every
  generated `declare` over the `DynComponent` trait. **Edit the canonical, not
  this copy** — `gen-bindings.mjs` overwrites it and the drift check fails the
  commit. It is a copy rather than a dependency because a `declare` must be
  implemented in its own package and `Instance`'s methods must be defined where
  `Instance` is, and both of those are here.
- `gen/interface/tutuca/component/guest/counter.mbt` — **the only file a
  component author writes**: a `Counter` struct implementing
  `DynComponent`, its `ComponentDef` (views, the declared state schema, the
  message buckets, style) and `dyn_module()` (the components, their factories,
  and the bundle's own request handlers)

There is no `wit/` here. The one WIT in the repo is
[`dyncomp/wit/tutuca-component.wit`](../../dyncomp/wit/tutuca-component.wit):
the builder embeds that directory directly, `wit-bindgen` generates from
it, and the Rust guest's `generate!` macro points at it — so a guest
cannot silently implement a different contract than the host expects.

## Build & test

Both MoonBit guests share one parameterized builder
([`../build-guest.mjs`](../build-guest.mjs)): moon build → wasm-tools
embed/new → jco transpile, into `dist/` (gitignored).

```sh
node guests/build-guest.mjs counter     # dist/counter.component.wasm + dist/js/
node --test dyncomp/test/harness.test.mjs
```

## Regenerating the bindings

After a change to the WIT or a toolchain bump:

```sh
moon run --target native cmd/dev -- gen-guest-bindings
```

That regenerates BOTH guest trees from the canonical WIT and then runs
`git diff --exit-code -- guests` — the trees are checked in, so a clean
diff is the whole check. [`../gen-bindings.mjs`](../gen-bindings.mjs) does
the work, and documents the two normalizations that make the output
reproducible at all: dropping the `moon.pkg.json` / `moon.mod.json` twins
of the hand-maintained extensionless package files, and sorting the
`ffi.mbt` export shims, which wit-bindgen emits in hash order (its output
genuinely differs between two runs on the same input).

`sdk.mbt` and the component source (`counter.mbt` / `todo.mbt`) have names
wit-bindgen never emits, so regeneration leaves their contents alone;
`moon fmt` formats them like any other source.

## Toolchain (version-coupled — pin together)

moon v0.10.x · wit-bindgen-cli 0.59.0 · wasm-tools 1.244.x ·
`@bytecodealliance/jco` 1.25.x (repo devDependency; the bare `jco` npm name
is a dependency-confusion placeholder — never install it).

## Gotchas (learned in the Phase 0 spike)

- **Canonical-ABI rep/handle asymmetry**: `Instance` values *returned* to
  the host (constructor result, handler successors) must be handles made
  with `Instance::new(rep)`; `self`/params *received* in methods and the
  dtor carry the rep directly — never call `.rep()` on those. `sdk.mbt`
  hides this.
- **Non-reentrance**: the Component Model forbids re-entering a component
  while a call into it is active. `control.make-instance` therefore only
  *reserves* a token; the host bridge constructs the child after the
  current guest call returns. Never assume a child is constructed within
  the same call that requested it (its token is immediately valid to
  store and return, though).
- The generated guest package's `moon.pkg` must import the `control`
  interface package for `@control.*` calls, and `gen/moon.pkg` lists the
  export names the canonical ABI expects (`…#[method]instance.get-field`,
  …) — including the WIT PACKAGE VERSION, so a version bump is edited
  there too. That is why the regeneration task drops the `moon.pkg.json`
  files wit-bindgen recreates: the extensionless ones are hand-maintained.
- A component declares its FIELDS, and gets the host's per-field mutators
  (`setCount`, `pushInHistory`, …) for free — through `with-field`, which
  is therefore worth implementing even for a component with no children.
  A name the schema generates that the guest wants for logic of its own
  has to appear in the def's `handlers`.
- jco (1.25) emits **unversioned** import keys at runtime
  (`'tutuca:component/values'`) even though its `.d.ts` says versioned;
  hosts should provide both.
- Imports the guest never calls are dead-code-eliminated from the
  component (this counter only imports `values`; `control` disappears).
- Measured on node: ~5.4µs per `get-field` round trip steady-state
  (~0.3ms for a 50-field render), ~40 KB component.
