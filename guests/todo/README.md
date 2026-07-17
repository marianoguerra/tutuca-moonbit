# counter — a `tutuca:component` guest

The reference guest for the dynamic-wasm-component design
([`../../dyncomp/DESIGN.md`](../../dyncomp/DESIGN.md)): a counter with
opaque native state and tutuca view strings, compiled to a WebAssembly
component any `tutuca:component` host can load.

## Layout

- `wit/` — copy of [`dyncomp/wit/tutuca-component.wit`](../../dyncomp/wit/tutuca-component.wit)
- `moon.mod.json`, `gen/`, `interface/`, `world/` — `wit-bindgen moonbit`
  output (committed; regenerate only when bumping the toolchain)
- `gen/interface/tutuca/component/guest/sdk.mbt` — the guest SDK template:
  implements every generated `declare` over the `DynComponent` trait
- `gen/interface/tutuca/component/guest/counter.mbt` — **the only file a
  component author writes**: a `Counter` struct implementing
  `DynComponent`, its `ComponentDef` (views/handlers/style), and
  `dyn_module()`
- `build.mjs` — moon build → wasm-tools embed/new → jco transpile, into
  `dist/` (gitignored)

## Build & test

```sh
node guests/counter/build.mjs          # dist/counter.component.wasm + dist/js/
node --test dyncomp/test/harness.test.mjs
```

## Toolchain (version-coupled — pin together)

moon v0.10.x · wit-bindgen-cli 0.59.0 · wasm-tools 1.244.x ·
`@bytecodealliance/jco` 1.25.x (repo devDependency; the bare `jco` npm name
is a dependency-confusion placeholder — never install it).

Regenerate bindings after a WIT or toolchain change with:

```sh
cd guests/counter && wit-bindgen moonbit wit/ --out-dir . --derive-eq --derive-show
```

`sdk.mbt` / `counter.mbt` are not wit-bindgen-managed files, so
regeneration leaves them alone (it does rewrite `top.mbt`/`ffi.mbt`).
Note `moon fmt` migrates the generated `moon.mod.json`/`moon.pkg.json` to
the extensionless `moon.mod`/`moon.pkg` format; regeneration recreates the
`.json` variants and the next `moon fmt` re-migrates — both states build.

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
  interface package for `@control.*` calls; wit-bindgen regeneration
  recreates `moon.pkg.json` files — delete them where an extensionless
  `moon.pkg` exists (the extensionless ones are hand-maintained).
- jco (1.25) emits **unversioned** import keys at runtime
  (`'tutuca:component/values'`) even though its `.d.ts` says versioned;
  hosts should provide both.
- Imports the guest never calls are dead-code-eliminated from the
  component (this counter only imports `values`; `control` disappears).
- Measured on node: ~5.4µs per `get-field` round trip steady-state
  (~0.3ms for a 50-field render), 38 KB component.
