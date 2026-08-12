# In-browser dyncomp compilation

## Context

Today, authoring a tutuca dyncomp requires a developer machine with four native
tools. `dyncomp/DESIGN.md` already names the missing piece under "Still open":
*"Playground emission of dyncomp bundles (needs in-browser componentize)."*

The obvious approach is to port the toolchain into the browser: compile jco,
wit-bindgen, wit-bindgen-moonbit and wasm-tools to wasm (via wasm-pack or
similar) behind an in-memory VFS, and run every build step client-side.

**That work is not necessary.** Measurement in this repo shows the
componentization round-trip contributes nothing to the shipped artifact, and the
host already owns the canonical ABI. The simplest path deletes three of the four
tools from the browser story rather than porting them.

A 100-agent literature review (adversarially verified, 18 claims confirmed of 25)
reached the same verdict independently, and pinned down where the port gets
expensive:

- **jco already ships the toolchain as wasm** — `wasm-tools.core.wasm` (2.37 MB)
  and `js-component-bindgen-component.core.wasm` (3.25 MB), exposed as
  `componentEmbed`/`componentNew`/`transpile`/`metadataShow` from
  `@bytecodealliance/jco-transpile`. So no wasm-pack wrapper needs writing.
- **But the browser path is partial.** Official browser support landed Sept 2023,
  and the browser export condition pre-wires only `transpile`/`generateTypes`.
  `componentNew`/`componentEmbed` sit on the Node-default path and reach WASI
  preview1/preview2 imports that must be resolved through `preview2-shim`'s
  browser build. No verified demonstration of `componentEmbed`/`componentNew`
  executing in a plain browser was found.
- **wit-bindgen in the browser: no evidence at all.** The review found nothing on
  wit-bindgen compiled to wasm or run client-side. It is also the one tool tutuca
  provably does not need at runtime — bindings are checked in and drift-checked.

So the port is *feasible* but buys nothing tutuca ships, at the cost of ~5.6 MB
of toolchain wasm and a WASI shim layer.

## What the measurements show

Run against `guests/counter` (wasm-tools 1.244.0, moonc v0.10.7+bc794d341):

1. **The componentization round-trip is a no-op on shipped bytes.**
   `_build/wasm/release/build/gen/gen.wasm` (40,037 B) vs the packed
   `dist/js/counter.component.core.wasm` (40,059 B) are section-for-section
   identical — same counts, same byte offsets, through `data`. The only
   difference is the `producers` custom section (58 → 80 bytes). `wasm-tools
   component embed` → `component new` → `jco transpile` exists to validate the
   WIT and then *extract the core module back out*.

2. **`moonc` already emits canonical-ABI names directly.** Raw `gen.wasm`
   imports `tutuca:component/control@0.6.0` `emit`,
   `[export]tutuca:component/guest@0.6.0` `[resource-new]instance`, etc., and
   exports the mangled `tutuca:component/guest@0.6.0#[method]instance.get-field`,
   `cabi_post_*`, `cabi_realloc`, `memory`. Those export names are hand-written
   in `guests/counter/gen/moon.pkg` under `link.wasm.exports` — exactly the
   shape `moonc.linkCore({ exportedFunctions })` takes.

3. **The host never wants a component.** `dyncomp/host/wasm/abi.mjs`
   `instantiate(getCoreModule, imports, descriptor)` implements the whole
   canonical ABI host-side and binds imports **by name** against a closed
   `IMPORTS` table. The shipped `counter.tutuca.tar.gz` contains exactly
   `tutuca.json`, `counter.component.core.wasm`, `Counter.main.html`,
   `Pair.main.html` — no JavaScript, no component wrapper, and jco's
   `core2.wasm`/`core3.wasm` shims are never shipped.

4. **Half the pipeline already runs in the browser.** `moonc-web.cjs` (a
   js_of_ocaml build of moonc, pure JS) compiles and links in a Web Worker
   today, and its `Target` type already includes `"wasm"`
   (`playground/vendor/moonc-web.d.ts`).

5. **`$MOON_HOME/lib/core/_build/wasm/release/bundle/` already exists**, with the
   same 59 packages as the `wasm-gc` bundle the playground already bakes.

### The one real gap, isolated

`moon build --target wasm --release --dry-run` in `guests/counter` shows
`moonc link-core` receives five wasm-specific flags:

| flag | exposed by `moonc-web` `linkCore`? |
|---|---|
| `-exported_functions=…` | yes — `exportedFunctions` |
| `-export-memory-name memory` | **no** |
| `-heap-start-address 16` | **no** |
| `-wasm-module-name …` | no (cosmetic — `name` custom section only) |
| `-pkg-config-path ./gen/moon.pkg` | no (redundant; moon passes the flags explicitly) |

Grepping the vendored `moonc-web.cjs` confirms this is a real gap, not a
spelling difference: it reads exactly `target`, `useJsBuiltinString`,
`importedStringConstants`, `exportedFunctions`, `outputFormat`, `testMode`,
`debug`, `stopOnMain`, `noOpt` — zero occurrences of any memory/heap flag.

Linking with **only** what `moonc-web` can express today produces all 14
canonical exports but **no `memory` export**, which `abi.mjs` requires to lift
and lower strings. Adding just `-export-memory-name memory` and
`-heap-start-address 16` yields a module structurally identical to the real
`gen.wasm` (differing only in the `name` custom section, from omitting
`-wasm-module-name`) — and it passes `wasm-tools component embed` +
`component new`, confirming it is a valid `tutuca:component` core module.

**So the entire browser gap is two `linkCore` parameters in
`@moonbit/moonc-worker`.** Not jco, not wit-bindgen, not wasm-tools.

## Approach

Extend the existing playground compiler to a third target, `wasm`, and hand the
linked core module straight to the `abi.mjs` the host already has.

### 1. Unblock `linkCore` (prerequisite)

Ask upstream `@moonbit/moonc-worker` to expose `exportMemoryName`,
`heapStartAddress` and `wasmModuleName` on `linkCoreParams`. This is a
three-field passthrough to flags `moonc` already accepts, and the pin in
`playground/build/toolchain.json` moves to the release that carries them.

Everything downstream can be built and tested against the *native* `moonc` in
the meantime, since it accepts the flags today — the parity test in Verification
is exactly that harness. Only the final in-browser wiring is gated on the
upstream release.

### 2. Bake a `wasm` payload

`playground/build/assemble.mjs` currently loops
`TARGETS = [["js", …], ["wasm-gc", …]]`. Add a `wasm` entry. Two differences
from the existing two, both handled inside `assembleTarget`:

- The link closure comes from a **separate moon module** — `guests/counter`
  (`moon.mod` name `tutuca/component`), so the existing
  `moon build --target wasm --release --dry-run` scrape must run with that cwd.
- Guests build `--release`, whereas the current payload reads
  `_build/<t>/debug/build/**.mi`.

The closure is small: std bundle + `abort.core`, `core.core`, and five
guest-module cores (`values`, `control`, `tables`, `guest`, `gen`). Every
package in the guest module is **fixed and identical for every guest** except
one file — `gen/interface/tutuca/component/guest/<name>.mbt`, which is the
user's component. So `values`, `control` and `tables` can be prebuilt and baked
outright; only `guest` and `gen` are recompiled per edit.

### 3. Compile the guest in the worker

`playground/web/compiler.worker.js` already keys payloads by target, injects
per-target boot glue as an extra package file, and picks `exportedFunctions`
per target. Extend it:

- Add a `wasm` branch with the fixed 14-entry `exportedFunctions` list from
  `guests/counter/gen/moon.pkg`, and `useJsBuiltinString: false` (the wasm
  target uses linear-memory strings, not the wasm-gc JS-string builtins).
- Two `buildPackage` calls instead of one: the `guest` package (user's `.mbt` +
  the fixed `ffi.mbt`/`sdk.mbt`/`tables.mbt`/`top.mbt` from the payload), then
  the fixed `gen` package, which imports it. The worker already accumulates
  diagnostics across calls.

### 4. Mount without packing

For live preview, skip the archive entirely. `dyncomp/host/wasm/loader.mjs`
already separates unpacking from loading — `requireDescriptor` and the
`createTcompImports` load path sit downstream of `gunzip`/`untar`. Add an
in-memory entry point beside `load_url`/`load_dropped` that takes
`{ descriptor, coreBytes, views }` directly and joins at the same point, so the
preview path and the archive path converge on one code path.

### 5. Export a downloadable bundle

`scripts/pack-bundle.mjs` is already dependency-free — a hand-rolled 512-byte
ustar writer plus `gzipSync`. Porting it to the browser is swapping `node:zlib`
for `CompressionStream("gzip")` and `Buffer` for `Uint8Array`. The result is a
`.tutuca.tar.gz` the user can download, byte-compatible with the CI-built ones.

The packer needs two inputs the compiler does not produce, so both need an
authoring surface in the playground:

- **`manifest.json`** — hand-authored today (see `guests/bluesky/manifest.json`).
  Simplest is a JSON tab alongside the source and view tabs, validated against
  the same rules `register_bundle` enforces so errors surface before load rather
  than at mount. Deriving it from the component's declared state shape is a
  larger design question — out of scope here.
- **The views** — ordinary `.html` files shipped as-is, which the playground
  already has tabs for.

## Files

| file | change |
|---|---|
| `playground/build/assemble.mjs` | third `TARGETS` entry; release-mode + foreign-module closure in `assembleTarget` |
| `playground/web/compiler.worker.js` | `wasm` branch: fixed `exportedFunctions`, two-stage `buildPackage` |
| `playground/web/runtime.js`, `driver.js` | target selection + mount path for a dyncomp |
| `dyncomp/host/wasm/loader.mjs` | in-memory load entry point beside `load_url`/`load_dropped` |
| `scripts/pack-bundle.mjs` | factor the tar writer so a browser copy shares it |
| `playground/build/toolchain.json` | pin moves to the moonc-worker release carrying the new fields |

Reused as-is, unmodified: `dyncomp/host/wasm/abi.mjs` (the whole canonical ABI),
`guests/sdk.mbt` + `guests/tables.mbt` (baked into the payload),
`dyncomp/wit/tutuca-component.wit` (still the one contract, still the source for
the checked-in bindings).

## What is given up, and why it is acceptable

The review isolated exactly what skipping `embed`/`new` costs: **four things the
host must own out-of-band — string-encoding choice, memory/realloc binding,
post-return calls, and the resource handle table with own/borrow discipline.**
`dyncomp/host/wasm/abi.mjs` already implements all four, and its header comment
documents each one. On encoding specifically: string encoding is a per-function
canonical option with no runtime negotiation, so a hand-written host ABI *must*
hardcode the encoding the guest was compiled with. tutuca does this correctly —
`--encoding utf16` in the build, `"encoding": "utf16"` in `tutuca.json`, and
`stringEncoding: "utf16"` in each manifest.

Beyond those four, what is given up is **build-time WIT conformance
validation**. In exchange:

- The world is fixed and known (`tutuca:component@0.6.0`), and the export list
  is generated, not hand-authored per guest.
- `abi.mjs` binds imports by name against a closed table, so an out-of-contract
  import is refused **at load time, host-side** — which `dyncomp/SECURITY.md`
  already treats as the security-relevant check.
- The native `guests/build-guest.mjs` path keeps the full validation, so CI
  still proves the bindings and the world agree.

The browser path is a *faster* path to the same artifact, not a replacement for
the validated one.

### If a real `.component.wasm` is ever needed in-browser

Should genuine component-model interop be wanted later (publishing a dyncomp to
a non-tutuca host, say), there is a cheap escalation before reaching for jco:

- **`component embed` is reducible to a constant.** It is a pure append of one
  wasm custom section named `component-type`, and for a fixed world it is
  byte-identical every time — a deterministic function of (WIT text,
  `--encoding`, wit-component version), verified byte-identical across five
  independently compiled guests. It can be precomputed once, checked in, and
  appended by ~30 lines of JS. Internally it is one component type export plus a
  2-byte `wit-component-encoding` section, which is the only place `utf16` is
  recorded.
- **`component new` is not.** It derives canonopts from the world's signatures,
  binds `memory`/`cabi_realloc` by name, and can link adapter modules. That one
  genuinely needs jco's wasm-tools component, with the WASI browser shim.

So the escalation ladder is: ship the core module (this plan) → append a
constant `component-type` blob → wire jco's wasm-tools in-browser. Only the last
step requires new infrastructure.

## Verification

1. **Parity test (the key one).** For each of `counter`, `todo`, `calculator`:
   compile in-browser and assert the resulting core module is structurally
   identical to `guests/<n>/dist/js/<n>.component.core.wasm` — compare
   `wasm-tools objdump` section counts/sizes, ignoring `producers`/`name`.
2. **Contract test.** Point an existing harness at the browser-produced core.
   `dyncomp/test/abi.test.mjs` already loads a core module through `abi.mjs`
   *bypassing jco entirely* — it is the right harness, and it should pass
   unchanged on the new artifact.
3. **Round-trip validation.** In CI (which has wasm-tools), feed the
   browser-produced module through `wasm-tools component embed` +
   `component new` and assert success — this recovers the validation step 4
   skips, without putting wasm-tools in the browser.
4. **End-to-end in a browser.** Serve `dist/`, open the playground, edit a
   counter component, confirm it mounts and responds to events in the universal
   host page. Chrome/Edge only, as today.
5. **Existing suites unchanged:** `moon run --target native cmd/dev -- ci`, and
   `node --test 'dyncomp/test/*.test.mjs'`.
