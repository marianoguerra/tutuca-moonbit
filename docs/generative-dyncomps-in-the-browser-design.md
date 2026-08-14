# Generative dyncomps in the browser

> **Status: a design, not a description.** This is a PLAN — what it would take
> to produce a bundle client-side, written before the work. Read it for the
> reasoning and the constraints; do not read it as a description of what the
> code does today. Everything else in `docs/` documents shipped behaviour.
>
> **A different route to the same place exists and works:**
> [`cardwasm/`](../cardwasm/README.md) compiles a **tutucard** — the state and
> script blocks, not MoonBit — straight to a `tutuca:component@0.7.0` core
> module, by building a [Wax](https://github.com/marianoguerra/wax-mb) AST and
> letting `marianoguerra/wax` emit the bytes. That needs no `moonc`, no
> prebuilt payload, and none of the upstream change step 0 below waits on,
> because the compiler is an ordinary MoonBit library in the same bundle as the
> runtime. What it gives up is the language: a card says less than MoonBit
> does, and says so by name when you leave the subset. The two designs meet at
> the mount seam described below, and `cardwasm` implements it.

Producing a `tutuca:component@0.7.0` bundle entirely client-side, with no server
and no native toolchain.

[`dyncomp/DESIGN.md`](../dyncomp/DESIGN.md) is the contract.
[`dyncomp/SECURITY.md`](../dyncomp/SECURITY.md) is what a bundle can and cannot
do. [`dyncomp/ARCHITECTURE.md`](../dyncomp/ARCHITECTURE.md) is the shape above
them. This is how a bundle comes into existence without a build machine.

## The claim

**A dyncomp can be compiled in the browser today with no new toolchain
infrastructure.** The pipeline needs `moonc` — which already runs client-side —
and nothing else. jco, wit-bindgen and wasm-tools do not need to reach the
browser, because none of them contribute bytes to what a dyncomp ships.

## Why this matters

`ARCHITECTURE.md` opens by saying the universal UI and the agent runtime "are the
same system; only the driver differs." It then quotes A2UI's stated limitation as
the interesting part:

> **No Runtime Fetching:** the catalog definition must be known to the agent and
> client beforehand (at compile/deploy time).

tutuca already breaks half of that — `dyncomp` fetches and mounts a bundle into a
running component tree with no rebuild of the host page. But the *bundle itself*
still has to be produced somewhere with `moon`, `wasm-tools` and `node`
installed. The catalog can grow at runtime; its contents still can't be authored
at runtime.

In-browser compilation removes the other half. A component can be written — by a
person in a playground, or by a model driving the agent runtime — and enter the
catalog in the same session, without a deploy step. That is what makes dyncomps
*generative* rather than merely dynamic.

This design is worth doing for the human playground alone. The agent-runtime
consequence is what makes it strategic.

## The pipeline today, and what is actually load-bearing

A guest bundle is built by four native steps:

```
moon build --target wasm --release          ->  gen.wasm         (core module)
wasm-tools component embed <wit> --encoding utf16
                                            ->  embedded.wasm    (+ custom section)
wasm-tools component new                    ->  component.wasm   (a real component)
jco transpile --instantiation async         ->  dist/js/*.core.wasm + JS glue
```

and then `scripts/pack-bundle.mjs` writes `tutuca.json` + **one core wasm** +
HTML views into a `.tutuca.tar.gz`.

Measured against `guests/counter` (wasm-tools 1.244.0, moonc v0.10.7+bc794d341):

- `gen.wasm` (40,037 B) and the packed `counter.component.core.wasm` (40,059 B)
  are **section-for-section identical** — same section counts, same byte offsets,
  through `data`. The only difference is the `producers` custom section
  (58 → 80 bytes).
- The component wrapper produced by `component new` is **discarded**. jco's
  `core2.wasm` / `core3.wasm` shim modules are never shipped. The JS glue is
  never shipped.

So steps 2–4 exist to *validate the WIT and extract the core module back out*.
They are a detour, not a transformation.

Two further facts make the browser path short:

- **`moonc` already emits canonical-ABI names.** Raw `gen.wasm` imports
  `tutuca:component/control@0.7.0` `emit` and
  `[export]tutuca:component/guest@0.7.0` `[resource-new]instance`; it exports
  `tutuca:component/guest@0.7.0#[method]instance.get-field`, `cabi_post_*`,
  `cabi_realloc` and `memory`. Those names are listed in `gen/moon.pkg` under
  `link.wasm.exports` — the same shape `moonc.linkCore({ exportedFunctions })`
  already takes.
- **The host never wanted a component.** `dyncomp/host/wasm/abi.mjs` is the sole
  canonical-ABI implementation; it instantiates the raw core module and binds
  imports **by name** against a closed table derived from the WIT.

## The design

```
   editor (source .mbt, views .html, manifest .json)
        |
        |  moonc-web.cjs in a Worker  — already shipping
        v
   buildPackage(guest)  ->  buildPackage(gen)  ->  linkCore(target: "wasm")
        |
        v
   core wasm module  ——————————————+——————————————
        |                          |
        | in-memory                | pack (ustar + CompressionStream)
        v                          v
   loader.mjs load path       name.tutuca.tar.gz
        |                          |
        v                          v
   abi.mjs instantiate  <——————————+  (drag onto any host page)
        |
        v
   register_bundle -> catalog -> DynObj in the component tree
```

Four seams, three of which already exist.

### The payload seam

The playground bakes prebuilt `.mi`/`.core` payloads per target, keyed in
`dist/playground/manifest.json`, for `js` and `wasm-gc`. A dyncomp needs a third:
`wasm` (linear memory). `$MOON_HOME/lib/core/_build/wasm/release/bundle/` already
exists with the same 59 packages as the `wasm-gc` bundle.

The guest module's closure is small — the std bundle plus `abort.core`,
`core.core`, and five guest-module cores (`values`, `control`, `tables`, `guest`,
`gen`). **Every package in a guest module is fixed and identical across guests
except one file**: `gen/interface/tutuca/component/guest/<name>.mbt`, the user's
component. `values`, `control` and `tables` bake outright; only `guest` and `gen`
recompile per edit.

This is the design's main asymmetry and the reason it is cheap: the generated
bindings, the SDK and the table codec are *payload*, not *output*. wit-bindgen
runs once, at repo build time, exactly as it does today.

### The compile seam

Two `buildPackage` calls (the `guest` package, then the `gen` package that
imports it) and one `linkCore` with the fixed 14-entry `exportedFunctions` list.
The wasm target uses linear-memory strings, so `useJsBuiltinString` is false —
unlike the wasm-gc host path, which depends on JS String Builtins.

**One upstream gap.** `moon build --target wasm --release --dry-run` in
`guests/counter` shows `moonc link-core` receiving five wasm-specific flags:

| flag | exposed by `moonc-web` `linkCore`? |
|---|---|
| `-exported_functions=…` | yes — `exportedFunctions` |
| `-export-memory-name memory` | **no** |
| `-heap-start-address 16` | **no** |
| `-wasm-module-name …` | no (cosmetic — `name` custom section only) |
| `-pkg-config-path ./gen/moon.pkg` | no (redundant; moon passes the flags explicitly) |

Grepping the vendored `moonc-web.cjs` confirms this is a real gap and not a
spelling difference: it reads exactly `target`, `useJsBuiltinString`,
`importedStringConstants`, `exportedFunctions`, `outputFormat`, `testMode`,
`debug`, `stopOnMain`, `noOpt` — zero occurrences of any memory or heap flag.

Linking with **only** what `moonc-web` can express today produces all 14
canonical exports but **no `memory` export**, which `abi.mjs` requires to lift
and lower strings. Adding `-export-memory-name memory` and
`-heap-start-address 16` yields a module structurally identical to the native one
(differing only in the `name` custom section, from omitting `-wasm-module-name`)
that passes `wasm-tools component embed` + `component new` — confirming it is a
valid `tutuca:component` core module.

So the gap is two parameters in `@moonbit/moonc-worker`, and nothing else. Not
jco, not wit-bindgen, not wasm-tools.

### The mount seam

`loader.mjs` already separates unpacking from loading: `requireDescriptor` and
the `createTcompImports` load path sit downstream of `gunzip`/`untar`. A locally
compiled component joins **at that point**, via an in-memory entry beside
`load_url`/`load_dropped` taking `{ descriptor, coreBytes, views }`.

Converging both paths there is deliberate. It means a component compiled in the
page and a component downloaded from a stranger traverse the same registration,
policy and view-authority code. There is no "local build" fast path that could
drift into being a more trusting one.

### The packaging seam

`scripts/pack-bundle.mjs` is already dependency-free — a hand-rolled 512-byte
ustar writer plus gzip. The browser port swaps `node:zlib` for
`CompressionStream("gzip")` and `Buffer` for `Uint8Array`, and emits a
`.tutuca.tar.gz` byte-compatible with the CI-built ones.

## Invariants this design must not break

1. **One contract.** `dyncomp/wit/tutuca-component.wit` stays the single source.
   Bindings remain generated at repo build time and drift-checked in CI. The
   browser never re-derives the world; it *consumes* a payload built from it.
2. **The host owns the ABI.** Skipping `embed`/`new` means the host owns four
   things out-of-band: string-encoding choice, memory/realloc binding,
   post-return calls, and the resource handle table with own/borrow discipline.
   `abi.mjs` already implements all four. Encoding in particular is a
   per-function canonical option with **no runtime negotiation** — the host must
   hardcode what the guest was compiled with. tutuca is consistent here:
   `--encoding utf16` in the build, `"encoding": "utf16"` in `tutuca.json`,
   `stringEncoding: "utf16"` in each manifest.
3. **The guest sandbox is unchanged.** Compiling in the page does not widen what
   the compiled thing can do. The output is still a core module with no WASI
   imports, bound by name against `abi.mjs`'s closed table, refused before
   instantiation if it imports anything outside the contract.
4. **No page-authority code in a bundle.** v0.6 removed jco's `*.component.js`
   from archives precisely because "warning before importing page-authority code
   is not a sandbox" (SECURITY.md §2). A browser-built bundle must contain the
   same three things and no more: `tutuca.json`, one core wasm, HTML views.

### What validation is given up

Beyond the four things above, which `abi.mjs` already owns, skipping
`embed`/`new` gives up exactly one thing: **build-time WIT conformance
validation**. The trade:

- The world is fixed and known (`tutuca:component@0.7.0`), and the export list is
  generated, not hand-authored per guest.
- `abi.mjs` binds imports by name against a closed table, so an out-of-contract
  import is refused **at load time, host-side** — which SECURITY.md already
  treats as the security-relevant check. A build-time tool noticing later is
  weaker, not stronger.
- The native `guests/build-guest.mjs` path keeps the full validation, so CI still
  proves the bindings and the world agree.

The browser path is a *faster* path to the same artifact, not a replacement for
the validated one. Verification step 3 below closes the loop by running the
round-trip in CI, where wasm-tools already exists.

## Security consequences

The compiled artifact is no more dangerous than a downloaded one — invariant 3
holds by construction, since it is the identical byte shape entering the
identical loader. Two things genuinely change, and both should be decided
deliberately rather than inherited.

**The compiler runs at page authority.** `moonc-web.cjs` is ~5.5 MB of
JavaScript executing in the playground's realm today. That is an accepted cost
*for the playground*. Putting a compiler into the universal host page is a
different decision, because that page's job is to load untrusted strangers. The
conservative shape is to keep compilation in the playground/storybook origin and
let it hand a finished archive to the host page, rather than fusing the two.

**Provenance loses its anchor.** SECURITY.md §8 says a bundle's identity should
be "the hash of the archive it arrived in, not anything it says about itself." A
component the page just compiled did not arrive in an archive. The fix is
available and cheap: the packing seam is deterministic, so hash the archive it
*would* ship as, and use that as the id. Locally compiled and downloaded bundles
then share one identity scheme.

**Agent-generated components are Untrusted, like everything else.** Nothing about
a model having written a component argues for a higher policy tier. If anything
the opposite: generated code is exactly the case the `Untrusted` tier and the
view-authority walk exist for. This design adds no trust tier and no capability.

## Alternatives considered

| option | verdict |
|---|---|
| **Ship the core module; skip `embed`/`new`/`transpile`** | **Chosen.** No new infrastructure. The shipped bytes are already identical. |
| Port jco + wasm-tools to the browser | Feasible, unnecessary. jco already ships them as wasm components (`wasm-tools.core.wasm` 2.37 MB, `js-component-bindgen-component.core.wasm` 3.25 MB) with a JS API — so no wasm-pack wrapper is needed — but the browser export condition pre-wires only `transpile`/`generateTypes`; `componentNew`/`componentEmbed` reach WASI imports needing `preview2-shim`. ~5.6 MB for output tutuca discards. |
| Port wit-bindgen to the browser | Rejected. No evidence found of wit-bindgen compiled to wasm or run client-side, and tutuca provably does not need it at runtime — bindings are checked in and drift-checked. |
| Precompute the `component-type` custom section | **Held in reserve.** `component embed` is a pure append of one custom section, byte-identical for a fixed world (a deterministic function of WIT text, `--encoding` and wit-component version). ~30 lines of JS if a real `.component.wasm` is ever needed. `component new` is *not* reducible this way. |
| WebContainers / container2wasm / v86 | Rejected. Runs the whole native toolchain in a VM to produce bytes we already have. Heaviest option by a wide margin. |
| Keep componentization behind a small HTTP endpoint | Rejected. Reintroduces the server this design exists to remove, for a step that changes nothing. |

The escalation ladder, if requirements grow: ship the core module → append a
constant `component-type` blob → wire jco's wasm-tools in-browser. Only the last
rung needs new infrastructure.

## Open questions

- **Manifest authoring.** `manifest.json` is hand-written today. A JSON tab with
  validation against the rules `register_bundle` already enforces is the cheap
  answer. Deriving it from the component's declared state shape — which is what
  an agent would need — is unsolved and larger than this design.
- **Where compilation lives.** Playground origin vs. universal host page (see
  Security consequences). Affects nothing structural, but it is a real choice.
- **Agent tool surface.** There isn't one yet: the design that existed was
  specified over `SurfaceOp`s that no longer exist, and was deleted rather than
  redesigned in place. "Compile and register a component" is a natural tool once
  that design happens; it should not be bolted onto anything before then.

## Cost

The `wasm` payload is a third `fs/` tree in `dist/playground`, comparable to the
existing two (~12–13 MB each, fetched per target on first use), on top of the
5.5 MB compiler the playground already loads. No new native dependency in CI;
`.github/workflows/pages.yml` keeps installing wasm-tools for the native guest
build, which remains the validated path.

## Implementation plan

Ordered so that each step is verifiable on its own, and so that the only
upstream-gated step comes last.

### 0. Upstream ask (start first, blocks only step 5)

Ask `@moonbit/moonc-worker` to expose `exportMemoryName`, `heapStartAddress` and
`wasmModuleName` on `linkCoreParams` — a three-field passthrough to flags
`moonc` already accepts. When it lands, move the pin in
`playground/build/toolchain.json` to that release.

Steps 1–4 are built and tested against the **native** `moonc`, which accepts the
flags today, so nothing waits on this.

### 1. Parity harness

Before changing any product code, pin down the target. A script that drives
native `moonc build-package`/`link-core` directly — bypassing `moon` — and
compares its output to `guests/<n>/dist/js/<n>.component.core.wasm`.

This is the contract the browser path must meet, and it is already known to be
meetable: the minimal invocation
(`-exported_functions=… -export-memory-name memory -heap-start-address 16`)
produces a module structurally identical to the native one.

*Done when:* the harness reproduces `counter` from `.core` files, and
`dyncomp/test/abi.test.mjs` passes against its output.

### 2. Bake the `wasm` payload

`playground/build/assemble.mjs` loops
`TARGETS = [["js", …], ["wasm-gc", …]]`; add a `wasm` entry. Two differences
from the existing two, both inside `assembleTarget`:

- the link closure comes from a **separate moon module**, so the
  `moon build --target wasm --release --dry-run` scrape runs with `guests/counter`
  as cwd;
- guests build `--release`, whereas the current payload reads
  `_build/<t>/debug/build/**.mi`.

Bake `values`, `control` and `tables` as prebuilt cores; leave `guest` and `gen`
to be compiled per edit.

*Done when:* `dist/playground/manifest.json` carries a third target and
`fs/wasm/` is populated.

### 3. Compile in the worker

Extend `playground/web/compiler.worker.js`, which already keys payloads by
target and picks `exportedFunctions` per target:

- a `wasm` branch with the fixed 14-entry list from `guests/counter/gen/moon.pkg`
  and `useJsBuiltinString: false`;
- two `buildPackage` calls (`guest`, then `gen`) instead of one — the worker
  already accumulates diagnostics across calls.

*Done when:* the worker returns bytes that pass the step-1 parity harness.

### 4. Mount in memory

Add an entry point to `dyncomp/host/wasm/loader.mjs` beside
`load_url`/`load_dropped` taking `{ descriptor, coreBytes, views }` and joining
the existing path at `requireDescriptor`, so preview and archive converge on one
code path.

Wire target selection and the dyncomp mount path through
`playground/web/runtime.js` and `driver.js`.

*Done when:* a component edited in the playground mounts and handles events.

### 5. Pack and download

Factor the ustar writer out of `scripts/pack-bundle.mjs` so a browser copy shares
it; swap `node:zlib` for `CompressionStream("gzip")` and `Buffer` for
`Uint8Array`. Add a manifest tab, validated against the rules `register_bundle`
enforces. Use the archive hash as the bundle id, per Security consequences.

*Done when:* a downloaded `.tutuca.tar.gz` loads on the universal host page
unchanged.

### Files

| file | change |
|---|---|
| `playground/build/assemble.mjs` | third `TARGETS` entry; release-mode + foreign-module closure in `assembleTarget` |
| `playground/web/compiler.worker.js` | `wasm` branch: fixed `exportedFunctions`, two-stage `buildPackage` |
| `playground/web/runtime.js`, `driver.js` | target selection, manifest tab, dyncomp mount path |
| `dyncomp/host/wasm/loader.mjs` | in-memory load entry beside `load_url`/`load_dropped` |
| `scripts/pack-bundle.mjs` | factor the tar writer so a browser copy shares it |
| `playground/build/toolchain.json` | pin moves to the moonc-worker release carrying the new fields |

Unmodified and reused: `dyncomp/host/wasm/abi.mjs` (the whole canonical ABI),
`guests/sdk.mbt` + `guests/tables.mbt` (baked into the payload),
`dyncomp/wit/tutuca-component.wit` (still the one contract).

### Verification

1. **Parity.** For `counter`, `todo` and `calculator`: assert the
   browser-produced core module is structurally identical to
   `guests/<n>/dist/js/<n>.component.core.wasm` — compare `wasm-tools objdump`
   section counts and sizes, ignoring `producers` and `name`.
2. **Contract.** `dyncomp/test/abi.test.mjs` already loads a core module through
   `abi.mjs` bypassing jco entirely. It should pass unchanged on the new
   artifact — it is the right harness, not a new one.
3. **Round-trip.** In CI (which has wasm-tools), feed the browser-produced module
   through `wasm-tools component embed` + `component new` and assert success.
   This recovers the validation the design skips, without putting wasm-tools in
   the browser.
4. **End-to-end.** Serve `dist/`, edit a counter component in the playground,
   confirm it mounts and responds to events. Chrome/Edge only, as today.
5. **No regressions.** `moon run --target native cmd/dev -- ci` and
   `node --test 'dyncomp/test/*.test.mjs'`.
