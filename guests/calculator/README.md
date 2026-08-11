# calculator — a `tutuca:component` guest

A four-function calculator as a WebAssembly component: digits, the four
operators, and an answer. It is the guest that shows the *split* the contract
keeps asking about — which half of a component's state is declared and which
half is its own.

`display` is declared, because it is the answer: a host can project it, compare
it, put it in a generated form and hand it back after a reload. The pending
operand and the operator waiting on it are not. They are how the answer is
being arrived at, they mean nothing outside this component, and a host that
could write them could not reason about what it wrote — so they go in
`persist`, and come back through `restore`.

Everything structural — layout, build, binding regeneration, the WIT source,
the toolchain pins and the Component Model gotchas — is identical to the
counter guest and documented once, in
[`../counter/README.md`](../counter/README.md). Only the component source
differs:

- `gen/interface/tutuca/component/guest/calculator.mbt` — `Calc` behavior,
  persistence and factory; `manifest.json` + `views/` hold its declaration

```sh
node guests/build-guest.mjs calculator   # dist/calculator.component.wasm + dist/js/
```
