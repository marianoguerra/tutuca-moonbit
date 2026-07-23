# Playground wasm-gc target — status & blocker report

_Investigated 2026-07-16._

## TL;DR

- `js` is the only backend that **runs**; the playground defaults its toggle to it.
- A **target toggle** (`js` / `wasm-gc`) is wired into the standalone
  playground shell, and `assemble.mjs` emits **both** payloads by default
  (`JS_ONLY=1 node playground/build/assemble.mjs` assembles js alone).
- **wasm-gc does not yet run.** Compilation and linking of user code succeed, but
  the linked module fails to instantiate with a `WebAssembly.CompileError`. The
  cause is in the **vendored in-browser compiler** (`@moonbit/moonc-worker`), not
  in tutuca's code or cores. See _Root cause_. The toggle ships anyway so the
  error surfaces in the diagnostics pane instead of hiding the backend.

## Why js is the working backend

- `playground/site/embed.js` (landing-page `<mb-playground>`) calls
  `compiler.init("js")` and `mount(previewEl, js, {})` — the embeds are js-only.
- The worker's `linkCore` used `exportedFunctions: []` — fine for js (the user's
  `main` self-mounts) but wrong for wasm-gc (JS must call exported wrappers).

wasm-gc scaffolding (`playground/host_wasm/`, `demo/counter_wasm`) is complete
and assembled; only the link-time string ABI below blocks it.

## What the wasm-gc backend needs (and why it differs from js)

| Concern | js backend | wasm-gc backend |
|---|---|---|
| linkCore output | JS module text, mounted as an iframe blob module | wasm binary, `WebAssembly.instantiate` |
| entry | user's `fn main { @host.mount(build(), "app") }` runs itself | no JS-callable `main`; JS calls exported `mount()` |
| events | MoonBit closures cross freely into JS | closures can't cross; JS installs a delegated listener that calls exported `on_event(ev)` |
| inspector | closures published on `globalThis.__tutuca` | read back through exported `state_json()` / `classes_json()` |
| host facade | `@host` (`playground/host`) | `@host_wasm` (`playground/host_wasm`) |
| imports the user must name | `@component`, `@tutuca`, `@host` | `@component`, `@tutuca`, `@host_wasm`, **and `@core`** (to name `@core.Any` in the `on_event` signature) |
| string ABI | n/a | JS-String-Builtins (`use-js-builtin-string`), instantiated with `{ builtins: ["js-string"], importedStringConstants: "_" }` |

The reference for a working wasm-gc mount is the shipped demo
`demo/counter_wasm/` (`loader.mjs` + `main.mbt`). The new `mountWasm()` in
`playground/web/runtime.js` mirrors it.

## The chain of failures found (and what was fixed)

1. **assemble.mjs copied the js host core for every target.** It hardcoded
   `playground/host/host.core`, so wasm-gc assembly crashed with `ENOENT …
   _build/wasm-gc/…/playground/host/host.core`.
   **Fixed:** host core + host `.mi` are now target-aware
   (`playground/host_wasm/host_wasm.*` for wasm-gc).

2. **The wasm user module needs `@core` as a direct import**, but it was only in
   the indirect (`lib`) set, so `@core.Any` failed to resolve (`E4020 Package
   "core" not found`). moonc-web derives aliases from the last path segment, so
   `mizchi/js/core` → `@core`.
   **Fixed:** assemble adds `mizchi/js/core` to the manifest `direct` set for
   wasm-gc.

3. **linkCore exported nothing.** `exportedFunctions: []` would leave the wasm
   module with no `mount`/`on_event` to call.
   **Fixed:** the worker now passes
   `["mount","on_event","state_json","classes_json"]` for wasm-gc.

After 1–3, the pipeline gets all the way through compile + link:

```
== buildPackage (target wasm-gc) ==
diagnostics: []            # user module compiles clean
== linkCore ==
linked bytes: 474166       # link succeeds, produces a wasm binary
```

4. **The linked wasm module is invalid.** `WebAssembly.instantiate` (and the raw
   `new WebAssembly.Module`) reject it:

   ```
   CompileError: WebAssembly.Module(): Compiling function #53 failed:
   array.new_fixed[0] expected type externref, found local.get of type (ref 1)
   ```

   This fails **with and without** `{ builtins: ["js-string"], … }`, so it is not
   an instantiation-option problem — the byte stream itself mixes two string
   ABIs (js-string `externref` in one place, MoonBit-native `(ref 1)` array in
   another). **This is the remaining blocker.**

## Root cause

`array.new_fixed … expected externref, found (ref 1)` is a **string-ABI
mismatch** inside the linked module. On wasm-gc, a MoonBit `String` can be
lowered either as the JS-String-Builtins `externref` or as MoonBit's native
`(ref 1)` char array. The representation is chosen at **link time** by the
`-use-js-builtin-string` flag, and it must be applied uniformly across every
`.core` in the link set.

- The vendored in-browser linker, `@moonbit/moonc-worker`'s `linkCore`, exposes
  **no** string-ABI / `use-js-builtin-string` / `builtins` parameter. Its
  `linkCoreParams` (see `playground/vendor/moonc-web.d.ts`) only has
  `exportedFunctions` and `outputFormat: "wasm" | "wat"`. Grep of
  `moonc-web.cjs` finds no `use-js-builtin-string` / `builtins` /
  `importedStringConstants` knob. It therefore links tutuca's cores with a
  default ABI that is **inconsistent** with the pinned core release bundle,
  producing an invalid module.

- **Proof the cores are fine, the linker is the fault:** the *same* library
  cores linked by the real `moonc link-core` with `use-js-builtin-string: true`
  — i.e. the shipped `demo/counter_wasm/counter_wasm.wasm` — validate cleanly
  (`new WebAssembly.Module(bytes)` succeeds; imports are `jscore`/`tdom`/
  `console` only). Only the moonc-web-linked module is invalid.

## What must change in deps to fix it

The fix is **upstream in the vendored compiler**, not in tutuca:

1. **Preferred — `@moonbit/moonc-worker` must expose the wasm-gc string-ABI flag
   on `linkCore`.** It needs a `useJsBuiltinString: boolean` (and, ideally,
   `importedStringConstants` / `exportMemory`) parameter that maps to the native
   `moonc link-core -use-js-builtin-string` option, so the worker can link the
   whole set with a single, consistent ABI. Track/file this against the
   `@moonbit/moonc-worker` package (the `js_of_ocaml` build of `moonc`). Then in
   `playground/web/compiler.worker.js`, pass `useJsBuiltinString: true` for the
   `wasm-gc` target and instantiate (already done in `runtime.js`) with
   `{ builtins: ["js-string"], importedStringConstants: "_" }`.

2. **Alternative — pin a `moonc-worker` whose `linkCore` already defaults wasm-gc
   to a consistent js-string ABI**, if a later nightly does so. This must be done
   in lockstep with the installed `moon` toolchain and the baked core bundle:
   - `MOONC_WORKER_VERSION` in `playground/build/fetch-compiler.mjs`
   - `TOOLCHAIN` in `playground/build/assemble.mjs`
   - the pin note in `playground/vendor/README.md`
   (Current pin: `@moonbit/moonc-worker@0.1.202607161`, nightly 2026-07-16;
   `TOOLCHAIN` reads `v0.10.3+16975d007`. Confirm those two name the same moonc
   before bumping — they are written in different formats.) Verify with the
   probe below before shipping.

3. **Fallback — link wasm-gc with the native (non-js-string) ABI on both sides.**
   If moonc-worker can be made to link with MoonBit-native strings consistently
   (no `externref`), the module would validate without js-string builtins; the
   `runtime.js`/loader instantiation options and the `jscore` string helpers
   (`from_string`, `to_string`, `json_*`) would then need to match that ABI.
   This is more code churn and loses the js-string interop the demos use, so (1)
   is preferred.

Until one of these lands, the toggle correctly surfaces the `CompileError` in the
diagnostics pane rather than silently failing.

## How to reproduce / verify a fix

```sh
# assemble.mjs builds the moon artifacts each target needs and emits both
node playground/build/assemble.mjs

# drive the worker pipeline headless and inspect the linked module
#   (buildPackage -> linkCore -> WebAssembly.Module)
# a fix makes `new WebAssembly.Module(linkedBytes, {builtins:["js-string"],
# importedStringConstants:"_"})` succeed instead of throwing the ABI CompileError.
```

Serve `dist/playground/` and flip the **target** dropdown to `wasm-gc`: today it
compiles + links, then reports `wasm instantiate failed` with the `CompileError`
in the diagnostics pane.

## Files touched by this investigation

- `playground/build/assemble.mjs` — target-aware host core + `.mi`; `@core`
  direct import for wasm-gc.
- `playground/web/compiler.worker.js` — `exportedFunctions` + `target` for
  wasm-gc.
- `playground/web/runtime.js` — per-target `init` memo; new `mountWasm()`
  (instantiate + jscore/tdom/console imports + event bridge + exported-getter
  inspector).
- `playground/web/driver.js` — target dropdown handling; dispatch to
  `mount` (js) vs `mountWasm` (wasm-gc); manifest-driven target availability.
- `playground/web/index.html` — the `#target` `<select>`.
- `playground/web/starter.js` — `EXAMPLES_WASM` (wasm-shaped Counter that exports
  the host wrappers).
