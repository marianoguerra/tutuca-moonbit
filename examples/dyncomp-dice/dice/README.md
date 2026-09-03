# dice — a `tutuca:component` guest

A WebAssembly component that a **running** tutuca app can fetch, instantiate and
mount — no rebuild of the host, no shared language, no trust required. Scaffolded
by `tutuca new-guest dice`.

## The three files you write

Behavior is MoonBit, the declaration is JSON, and the views are HTML. Nothing
else is yours:

| path | what it is |
| --- | --- |
| `wit/tutuca-component.wit` | the contract, `tutuca:component@0.12.0`. The host generates its side from this same file. |
| `gen/`, `interface/`, `world/` | `wit-bindgen moonbit` output, checked in — so building needs no wit-bindgen |
| `gen/interface/tutuca/component/guest/sdk.mbt` | the guest SDK: implements every generated `declare` over the `DynComponent` trait |
| `gen/interface/tutuca/component/guest/dice.mbt` | **yours**: the behavior |
| `manifest.json` | **yours**: the schema, the docs, the message buckets |
| `views/Dice.main.html` | **yours**: the view, as a file an editor understands |

The last two used to be a `dice_def()` inside `dice.mbt`, exported through a
`get-manifest` the guest implemented. The contract moved them out:
a host can now read what a bundle IS without instantiating it, and a view is
HTML rather than a string inside source.

## Build

```sh
npm install        # @bytecodealliance/jco
node build.mjs     # -> dist/dice.component.wasm + dist/js/
node pack.mjs      # -> dice.tutuca.tar.gz
```

Then drop `dice.tutuca.tar.gz` on a universal host page. Every component your
`manifest.json` declares joins its catalog. The archive carries no executable
JavaScript — `tutuca.json`, one core wasm and the view HTML — because the host
owns the canonical ABI.

Needs `moon` v0.10.x, `wasm-tools` 1.244.x and Node. These are version-coupled —
bumping one without the others produces a component the host rejects.

## The four rules the contract turns on

1. **The host is the framework.** You never render, never touch the DOM, never
   install a listener. You are called at defined points and you answer.
2. **Views are data.** Your views are tutuca template strings in your manifest;
   the host compiles them with its own parser, so its renderer, event
   delegation, morphing and linter apply to you unchanged.
3. **State is opaque, its shape is declared.** The host never sees inside your
   struct. It reads one field at a time through `get_field`, and it knows what
   fields exist because `manifest.json` says so. That split is what lets a
   catalog rank you, a form configure you and an inspector show you — with
   nobody trusting your code.
4. **Ambient authority is absent, never assumed.** The world imports no WASI:
   no filesystem, no network, no clock, no entropy. A fact you cannot compute
   for yourself — the time, a random number — you ask the host for over an
   intent: the host registers an `IntentFn`, you raise the intent through
   `control.intent`, and the answer arrives as an ordinary message. This die
   is the worked example — it cannot roll itself, so it raises `roll` and the
   host answers with `rollOk` or `rollFailed`.

   What a host CAN hand you up front is configuration: variables
   your manifest declares with defaults and a host binds at load, read back
   through `config.get`. This die declares none — it needs a number, not a
   setting — but `guests/mastodon` upstairs is the worked example, and it is
   how one build of a reader serves any server there is.

## Two things that will bite

- **Handle asymmetry.** An `Instance` you RETURN to the host (from the
  constructor, or as a handler's successor) must be a handle made with
  `Instance::new(rep)`. The `self` and params you RECEIVE carry the rep
  directly — never call `.rep()` on those. `sdk.mbt` hides this everywhere it
  can; the comment at the top of it says where it cannot.
- **`get_field` runs a lot.** Once per `.name` a rendering view reaches for, on
  every render. Roughly 5 µs a call across the boundary. Compute in `handle`
  and store; do not compute in `get_field`.

## Changing the contract

Don't. `wit/tutuca-component.wit` is the agreement with every host, and a guest
that implements a different one is a guest no host can load. If you are
developing against a newer tutuca, regenerate with the pinned wit-bindgen
(0.59.0) rather than hand-editing either the WIT or the files under `gen/`.
