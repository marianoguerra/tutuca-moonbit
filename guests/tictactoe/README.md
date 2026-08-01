# tictactoe — a `tutuca:component` guest

Noughts and crosses as a WebAssembly component. It is the guest that shows a
host iterating a guest's COLLECTION: the board is a declared list, the view
walks it with `@each`, and each square dispatches back carrying its own index.

The interesting decision is what it does *not* store. Whose turn it is, whether
somebody has won, and which line they won on are all functions of the board, so
none of them is a field — state that can be computed is state that can be
wrong, and a stored turn is a second answer to a question the board already
answers. It has no `persist` for the same reason: the board *is* the declared
field, so the host projects and rebuilds it, and a `persist` here would be that
one list written twice.

Everything structural — layout, build, binding regeneration, the WIT source,
the toolchain pins and the Component Model gotchas — is identical to the
counter guest and documented once, in
[`../counter/README.md`](../counter/README.md). Only the component source
differs:

- `gen/interface/tutuca/component/guest/tictactoe.mbt` — the `Game` struct, its
  `ComponentDef`, and `dyn_module()`

```sh
node guests/build-guest.mjs tictactoe   # dist/tictactoe.component.wasm + dist/js/
```
