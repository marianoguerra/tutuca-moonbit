# @marianoguerra/tutuca-playground

An embeddable MoonBit playground: an editor, a live preview, and a MoonBit
compiler that runs **in the visitor's browser** — no server, no build step for
the code your readers write. It is the playground behind
[tutuca-mb](https://marianoguerra.github.io/tutuca-moonbit/).

```html
<script type="module" src="/site/embed.js"></script>

<mb-playground
  src="./examples/counter.mbt"
  view="./examples/counter.html"
></mb-playground>
```

## Three pieces

A working playground is this package plus two things it deliberately does not
ship:

| piece | package | why separate |
| --- | --- | --- |
| shell — element, worker, editor, view generator | this one | versioned with tutuca |
| payload — the prebuilt `.mi`/`.core` bundles user code compiles against | [`@marianoguerra/tutuca-playground-payload`](https://www.npmjs.com/package/@marianoguerra/tutuca-playground-payload) | 22 MB, and rebuilt whenever the MoonBit toolchain moves |
| the compiler itself, `moonc-web.cjs` | [`@moonbit/moonc-worker`](https://www.npmjs.com/package/@moonbit/moonc-worker) | upstream's 5.5 MB build, ours to point at rather than to redistribute |

The payload and the compiler are a **pair**: both come out of one `moonc` build,
and a compiler from another build misreads the baked interfaces and reports it
as errors in your reader's code. The payload's `manifest.json` records the
version it was built against and the worker checks it before loading anything,
so a mismatch says so instead of lying. Install the version the payload's
`peerDependencies` names.

## Install

```sh
npm install @marianoguerra/tutuca-playground \
            @marianoguerra/tutuca-playground-payload \
            @moonbit/moonc-worker
```

The worker, the `.mi`/`.core` bundles and the compiler are **fetched at
runtime**, not imported, so they have to be reachable over HTTP. Both packages
unpack into the same layout, so copying them into your static directory is
enough:

```sh
cp -r node_modules/@marianoguerra/tutuca-playground/{playground,site} public/
cp -r node_modules/@marianoguerra/tutuca-playground-payload/playground public/
cp node_modules/@moonbit/moonc-worker/moonc-web.cjs public/playground/
```

That gives you `public/site/embed.js` next to `public/playground/`, which is the
layout everything resolves against by default — nothing to configure.

## Serving the parts from elsewhere

Every URL is resolved from the module's own location, so the folders can live
anywhere as long as they keep their names. To split them up — payload on a CDN,
compiler served straight out of `node_modules` — set them before the first
playground compiles:

```html
<script>
  globalThis.MB_PLAYGROUND = {
    payloadBase: "https://cdn.example.com/tutuca-payload/",
    compilerUrl: "/vendor/moonc-web.cjs",
    workerUrl: "/playground/compiler.worker.js",
  };
</script>
```

All three are optional. A cross-origin worker is handled for you (a `Worker`
script has to be same-origin, so it gets wrapped in a same-origin shim), but the
other origin must send CORS headers.

## The element

| attribute | meaning |
| --- | --- |
| `src` | URL of the `.mbt` component the editor opens with |
| `view` | URL of the `.html` view file; adds the View and Generated tabs |
| `target` | `wasm-gc` (default) or `js` |

With no `view`, the element is a single editor and compiles its source alone.
One compiler worker is shared by every element on the page, and each element
compiles lazily the first time it scrolls into view — a page full of
playgrounds pays for one compiler load, not one per element.

A standalone, full-window playground ships too: serve
`playground/index.html`, which takes `?target=js|wasm-gc`.

## Browser support

The `wasm-gc` target needs the [JS String
Builtins](https://github.com/WebAssembly/js-string-builtins) proposal
(Chrome-class engines). Where it is missing the element falls back to `js` on
its own, so the playground still works.

MIT © the tutuca contributors.
