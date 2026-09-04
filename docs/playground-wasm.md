# Playground wasm-gc target — how it works

How the in-browser playground compiles and runs on both backends: the string
ABI both halves must agree on, the worker-per-target rule, the realm the linked
module lives in, and how to verify a change to any of it.

## TL;DR

- **Both backends run.** The target toggle (`js` / `wasm-gc`) compiles, links,
  instantiates and mounts; events, the state panel and the activity panel all
  work on wasm-gc.
- **The landing-page embeds default to wasm-gc** (`playground/site/embed.js`) —
  a linked module is ~0.26 MB against ~1.1 MB of JS, which is the better trade
  on a page that mounts ten of them. They fall back to `js` when the payload
  has no wasm-gc (a `JS_ONLY=1` build) or when the mount throws, which is what
  an engine without JS-String-Builtins looks like. The standalone playground
  still opens on `js`.
- `assemble.mjs` emits both payloads by default; `JS_ONLY=1 node
  playground/build/assemble.mjs` assembles js alone.
- The two things that make wasm-gc work — and that a compiler bump can silently
  break — are the **link-time string ABI** and the **realm the wasm host sees**.
  Both are described below.

## How the backends differ

| Concern | js backend | wasm-gc backend |
|---|---|---|
| linkCore output | JS module text, mounted as an iframe blob module | wasm binary, `WebAssembly.instantiate` |
| entry | user's `fn main { @host.mount(build(), "app") }` runs itself | no JS-callable `main`; JS calls exported `mount()` |
| events | MoonBit closures cross freely into JS | closures can't cross; JS installs a delegated listener that calls exported `on_event(ev)` |
| inspector | closures published on `globalThis.__tutuca` | read back through exported `state_json()` / `classes_json()` / `activity_json()` |
| host facade | `@host` (`playground/host`) | `@host_wasm` (`playground/host_wasm`) |
| imports the user must name | `@component`, `@tutuca`, `@host` | `@component`, `@tutuca`, `@host_wasm`, **and `@core`** (to name `@core.Any` in the `on_event` signature) |
| string ABI | n/a | JS-String-Builtins, chosen at link time and matched at instantiate |

The reference for a working wasm-gc mount is the shipped demo
`demo/counter_wasm/` (`loader.mjs` + `main.mbt`); `mountWasm()` in
`playground/web/runtime.js` mirrors it.

## The string ABI must be chosen at link time

On wasm-gc a MoonBit `String` lowers either as the JS-String-Builtins
`externref` or as MoonBit's native `(ref 1)` char array. The choice is made **at
link time**, for every `.core` in the link set at once, and the baked cores are
built for the js-string ABI (as are the shipped wasm demos).

`compiler.worker.js` therefore passes, for `wasm-gc` only:

```js
useJsBuiltinString: true,
importedStringConstants: "_",
```

and `runtime.js` instantiates with the matching
`{ builtins: ["js-string"], importedStringConstants: "_" }`. Under those options
the module's imports collapse to `jscore` / `tdom` / `console` — exactly the
demo's surface. Chrome-class engines only.

Link **without** `useJsBuiltinString` and the byte stream mixes the two
representations, so the module fails to validate before it can be instantiated:

```
CompileError: WebAssembly.Module(): Compiling function #67 failed:
array.new_fixed[0] expected type externref, found local.get of type (ref 1)
```

The `@moonbit/moonc-worker`'s `linkCore` exposes a string-ABI knob, which the
playground asks for a consistent link with. The compiler pinned in
`playground/build/toolchain.json` — the
ONE toolchain pin, which is where to look for the current version rather than
here — does expose it (`playground/vendor/moonc-web.d.ts`).

## One worker, many callers: the target travels with each compile

A whole page of `<mb-playground>` elements shares ONE compiler worker, and they
need not agree on a backend. So the worker keeps every payload it has loaded in
a map and picks one **per compile** from the target on the request
(`compiler.worker.js`), rather than holding the last `init()`'s payload as
worker state. Get this wrong and the symptom is not an error message: it is a
wasm binary handed to the JS mount (`Invalid or unexpected token`) or JS text
handed to `WebAssembly.instantiate` (`expected magic word 00 61 73 6d, found
66 75 6e 63`).

## The wasm host mounts into whatever realm `global_this()` names

The wasm host reaches the DOM as `@core.global_this()._get("document")`
(`app/wasm/glue.mbt`). The preview lives in an **iframe**, so `jsCoreImports()`
in `runtime.js` takes the realm to hand back and `mountWasm()` passes
`iframe.contentWindow`. Pass the shell's `globalThis` instead and the app looks
for `#app` in the shell page, finds nothing, and logs
`playground(wasm): no #app element` — it links and instantiates fine and simply
renders nothing.

## Toolchain coupling

The payload bakes the **installed** moon toolchain's core `.mi`/`.core` bundles
and hands them to a `js_of_ocaml` moonc built elsewhere, so the two must come
from the same moonc. Both are pinned in one place,
`playground/build/toolchain.json`; bump the fields together, re-fetch with
`node playground/build/fetch-compiler.mjs --force`, and re-run
`cmd/dev -- playground`.

## How to verify after a bump

```sh
node playground/build/assemble.mjs      # builds what each target needs, emits both
node playground/build/check-viewgen-tab.mjs   # every example, BOTH backends
python3 -m http.server -d dist/playground 8231
```

`check-viewgen-tab.mjs` is the gate on the string ABI: it links each example for
wasm-gc and validates the bytes with `new WebAssembly.Module`, so a link that
loses `useJsBuiltinString` fails there rather than in a visitor's browser. It
cannot reach the realm or the shared-worker paths, which is what the manual pass
below is for.

Flip the **target** dropdown to `wasm-gc` and run each picker example: the
preview should render, the buttons should drive it (that exercises the delegated
`on_event` bridge), and the State/Activity panels should track it (that
exercises the exported getters). A string-ABI regression shows up as the
`CompileError` above in the diagnostics pane, reported by the driver as
`wasm instantiate failed`.

Then flip it **back and forth** — js → wasm-gc → js → wasm-gc — on one embed and
on the standalone playground. That is the shared-worker path, and it fails only
on the second switch, so a single toggle proves nothing. Serve `dist/` (not
`dist/playground/`) for the landing page: the embeds should come up on wasm-gc
with their margaui styling, which is read back through the exported
`classes_json` and is a separate path from the js mount's.

Note that moonc-web accumulates state across compiles in one worker instance:
several back-to-back compiles can end in an OCaml `Stack_overflow` that has
nothing to do with the example being compiled. Reload between runs when a
failure looks implausible (`compiler.worker.js`'s `compilerDirty` handling
covers the error path, not this).
