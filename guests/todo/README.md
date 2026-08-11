# todo — a `tutuca:component` guest

A to-do list as a WebAssembly component: a list of items in opaque guest
state, static tutuca views, and handlers that add / toggle / remove. It is
the second guest bundle the universal demo loads, and the one that shows a
guest owning a *collection* rather than a scalar.

Everything structural — layout, build, binding regeneration, the WIT
source, the toolchain pins and the Component Model gotchas — is identical
to the counter guest and documented once, in
[`../counter/README.md`](../counter/README.md). Only the component source
differs:

- `gen/interface/tutuca/component/guest/todo.mbt` — the `Todo` behavior and factory
- `manifest.json` + `views/` — its declaration and host-compiled template

```sh
node guests/build-guest.mjs todo        # dist/todo.component.wasm + dist/js/
```
