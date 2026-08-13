# Dynamic components: hosting them, and writing them

Everything else in tutuca is decided before the program runs. This is the part
that is not: a WebAssembly component fetched at runtime, from someone you have
no reason to trust, mounted into a page that is already running and rendered by
the same machinery as the components you compiled in.

Two roles, one contract. **Hosting** is `dyncomp/`. **Writing** a component is
`tutuca new-guest`. The contract between them is one file,
[`../dyncomp/wit/tutuca-component.wit`](../dyncomp/wit/tutuca-component.wit) —
`tutuca:component@0.6.0`.

The full design is in [`../dyncomp/DESIGN.md`](../dyncomp/DESIGN.md); what a
loaded bundle can and cannot do is in
[`../dyncomp/SECURITY.md`](../dyncomp/SECURITY.md), checked against the code.
This page is the practical route into both.

## Why this is possible at all

A guest declares its **shape** without revealing its **state**.

The static manifest says what components exist, what fields each holds and of
what type, and which non-input messages it accepts; ordinary HTML files hold
the views. The state itself never
crosses the boundary: the host reads one field at a time through `get-field`
while rendering, and a handler takes the guest's own instance and returns its
successor. That is the same copy-on-write model a compiled-in tutuca component
has, which is why nothing downstream can tell them apart.

That split is what makes everything else work. Because the shape is declared,
the host can rank a component in a search, generate a form for it, diff two of
them, and show it in an inspector — with nobody trusting a line of its code.
Because the state is opaque, the guest owes the host no serialization, no
comparison, no schema implementation.

And because a guest's views are **data** — HTML templates the host
compiles with its own parser — the guest never touches the DOM. The renderer,
event delegation, morphing, the modifiers and the linter all apply to it
unchanged, and none of them had to learn what a bundle is.

## Writing a component

```sh
tutuca new-guest clock
cd clock
npm install        # @bytecodealliance/jco
node build.mjs     # moon build → wasm-tools embed/new → jco transpile
node pack.mjs      # clock.tutuca.tar.gz
```

You need `moon`, `wasm-tools` and `node`. You do **not** need `wit-bindgen`:
the bindings ship generated and drift-checked, and the WIT in `wit/` is the
contract to implement rather than a source to regenerate against.

The scaffold is a complete MoonBit module. Three places are yours:
`gen/interface/tutuca/component/guest/clock.mbt` holds behavior and factories,
`manifest.json` holds the schema/catalog/capability declaration, and `views/`
holds normal HTML templates. Everything else is generated bindings plus
`sdk.mbt`, which implements every generated `declare` over the trait.

`.tutuca.tar.gz` is the whole distribution format: a gzipped tar containing
`tutuca.json`, one core wasm module and the HTML views, unpacked in the browser
with `DecompressionStream`. It contains no executable JavaScript.

### Why the SDK is copied rather than depended on

`sdk.mbt` arrives as source, and there is no package to `moon add` instead.
That is forced rather than chosen: it implements the `declare`s in the
generated `top.mbt`, and it defines methods on `Instance`, a type that
`top.mbt` declares. MoonBit requires both to live in the package that declares
them, and `top.mbt` is generated per guest. No import edge can carry them.

So the repo keeps exactly one copy — [`../guests/sdk.mbt`](../guests/sdk.mbt) —
and copies it: into every sample guest during `gen-guest-bindings`, whose drift
check then covers it, and into a new guest from the tree embedded in the CLI.

### Two things that will bite

**Handle asymmetry.** An `Instance` you *return* to the host — from the
constructor, or as a handler's successor — must be a handle built with
`Instance::new(rep)`. The `self` and parameters you *receive* carry the rep
directly, and calling `.rep()` on those is wrong. `sdk.mbt` hides this
everywhere it can, and says so where it cannot.

**`get_field` runs constantly.** Once per `.name` a rendering view reaches for,
on every render, at roughly 5 µs across the boundary. Compute in `handle` and
store the answer; do not compute in `get_field`.

## Hosting them

The host is assembled from published packages:

| package | what it does |
| --- | --- |
| `dyncomp/host` | wraps a guest instance as an ordinary `&Obj`, and synthesizes real components from its manifest. Backend-agnostic — `&Guest` is the seam, and tests implement it with an in-process fake. |
| `dyncomp/host/wasm` | that seam over the `tcomp` FFI, for wasm-gc |
| `dyncomp/policy` | what this host will *accept*. Three tiers, and an ungranted capability refuses the bundle rather than degrading it. |
| `dyncomp/registry` | the catalog of everything every loaded bundle declares, and ranked search over it |
| `dyncomp/jsonschema` | the declared schema as JSON Schema and back, collecting every validation error with a JSON Pointer rather than stopping at the first |
| `dyncomp/persist` | a component that has to outlive the page (`dyncomp/persist/wasm` stores it in `localStorage`) |
| `dyncomp/ui` + `dyncomp/ui/std` | the universal UI: a person searches the catalog, fills in a generated form, and arranges what they placed. Backend-agnostic, so `moon test` drives the whole editor on the in-memory DOM. |
| `dyncomp/ui/wasm` | the wasm-gc half the above cannot have: the bridge that turns an archive into registered components and the store that keeps what was built. `mount()` is the whole host. |
| `dyncomp/shell` | the floor under any wasm-gc page that hosts bundles, whatever it does with them: the loader bar a bundle arrives through, `make_instance`, and the margaui refresh. Both pages below stand on it, so there is one loader rather than two that can answer differently. |
| `dyncomp/storybook` + `dyncomp/storybook/wasm` | the OTHER thing to do with a catalog: show all of it. One card per component per named `init`, live, filterable, in any theme — and no story list anywhere, because a manifest already declares both halves. `cmd/dev -- dyncomp-storybook`. |

Three JavaScript files come with them, because a wasm-gc module cannot reach the
DOM by itself:

- **`app/wasm/loader.mjs`** — `jscore` and `tdom` (the import namespaces
  `app/wasm` and `vdom/wasm` declare), plus `instantiate`. Every wasm-gc tutuca
  page needs this one.
- **`dyncomp/host/wasm/loader.mjs`** — `tcomp` (the guest bridge, the value
  arena, the bundle unpacker) and `tkv` (`localStorage`). Linked through
  `instantiate`'s `makeExtra` hook, so a page that loads no bundles carries
  none of it.
- **`dyncomp/host/wasm/abi.mjs`** — the canonical ABI for the world, written
  once host-side (it is what an archive used to ship a copy of). The file above
  `import()`s it lazily, only while an archive is actually being unpacked, so a
  page that forgets to serve it beside the other two MOUNTS AND DRAWS and then
  fails on the first bundle with a message about a module nobody mentioned. If
  bundles load nowhere and everything else works, check for this one first.

```js
import { instantiate } from "marianoguerra/tutuca/app/wasm/loader.mjs";
import {
  createTcompImports,
  createTkvImports,
} from "marianoguerra/tutuca/dyncomp/host/wasm/loader.mjs";

const exports = await instantiate("./app.wasm", (getExports) => ({
  tcomp: createTcompImports(getExports),
  tkv: createTkvImports(),
}));
exports.mount();
```

Your MoonBit side is an executable that calls `@uiw.mount` and re-exports the
five entry points the loader calls. It is short, and it has to be a package of
your own for exactly one reason: a wasm-gc export list is per-package `link`
configuration and cannot come from a dependency.

```moonbit
pub fn mount() -> Unit {
  @uiw.mount(
    // where a session goes; omit it for a page that starts empty every time
    session=Some(@uiw.session_in_local_storage(prefix="my-app:")),
    // bundles to offer as buttons; empty draws none
    samples=[{ label: "clock", url: "./clock.tutuca.tar.gz" }],
    // services this host lends to what it hosts
    requests=my_requests(),
    // what you will ACCEPT from a bundle. Defaults to `untrusted`: no
    // capabilities, no bundle CSS. A bundle that asks for something you do
    // not grant is refused rather than degraded, so raising this is a
    // decision to make deliberately — `granted()` is "a person said yes".
    policy=@policy.Policy::untrusted(),
  )
  |> ignore
}

pub fn on_event(ev : @core.Any) -> Unit { @uiw.on_event(ev) }
pub fn refresh_margaui() -> Unit { @uiw.refresh_margaui() }
pub fn state_json() -> String { @uiw.state_json() }
pub fn dyncomp_on_loaded(a : Int, b : Int, m : String) -> Unit {
  @uiw.dyncomp_on_loaded(a, b, m)
}
pub fn dyncomp_on_load_error(a : Int, m : String) -> Unit {
  @uiw.dyncomp_on_load_error(a, m)
}
```

`session` is one option rather than two flags on purpose: persistence has to be
gated at both ends, and a page that restores but does not save — or the reverse
— writes an empty tree over the thing it exists to keep.

`demo/universal_wasm/` in the repository is that file in full, with its
`moon.pkg` export list and its `index.html`. `dyncomp/ui/ui_test.mbt` drives the
same editor with no browser at all.

## What a bundle can do to your page

Summarized from [`../dyncomp/SECURITY.md`](../dyncomp/SECURITY.md), which
states each claim's actual strength:

| channel | reaches | state |
| --- | --- | --- |
| wasm imports (`values`, `control`) | nothing ambient | safe by construction |
| `env` — clock, randomness, ids | weakened, host-supplied answers | gated; refused by default |
| guest views | your DOM/network | untrusted refuses direct URL/CSS sinks, URL-bearing macro arguments and runtime markup; `<img src>`/`<a href>` reopen only with `cap-external-urls`; trusted tiers retain filtered URLs |
| guest CSS | your stylesheet | refused outright for an untrusted bundle |
| `control.request` → host handlers | your own services | **open** — needs caller-aware authorization |
| a runaway guest call | the page's responsiveness | **open** — needs worker isolation |

The world imports no WASI. That is not a packaging accident, it is the sandbox:
no filesystem, no network, no sockets, no environment, no subprocess, and no
clock or entropy beyond what a capability grant supplies. The default tier is
the one the design is *for* — a bundle there can still declare components, ship
views, hold state, handle events, nest children and serve its own requests, and
every sample guest runs under it unchanged.

Autonomous custom elements remain available to untrusted views, including
structured property bindings. The host page owns their JavaScript, though: a
registered element's constructor or setter can exercise page authority. The
default policy removes `is=` and browser-native network/CSS sinks, but a host
that exposes effectful custom elements should use a sanitizer allow-list to
narrow which tags and properties an untrusted bundle may invoke.

A page that wants an untrusted bundle to show pictures grants
`cap-external-urls` and names the origins in the same call:

```moonbit
@policy.Policy::untrusted().allowing_external_urls(["https://cdn.example"])
```

That reopens `src` on `<img>` and `href` on `<a>`, and only for a URL whose
ORIGIN is a literal in the view — `<img :src="$'https://cdn.example/a/{.id}.png'">`
is allowed, `<img :src=".avatar">` is not. It is a network grant: the path is
still the bundle's to write, so grant the origins you meant and read
`SECURITY.md` §3 before passing an empty list, which means any `https://`
origin.

The two open rows are open on purpose and are marked as such in the code. If
you host untrusted bundles today, they are what to think about.

## The sample guests

In [`../guests/`](../guests/), each covering a part of the contract that is
easy to get wrong (a count is left out on purpose — the list grows, and a
number in prose is the half that stops being true):

- **counter** — the reference: a scalar, a list the host iterates, a view
  method, a request round trip, and nested same-bundle children
- **slack** — a chat conversation, and the DEEP end of the same nesting:
  `ChannelHistory` → `Thread` → `Message` → `RichText` → `Segment`, all built
  from one `init`. Also the two refusals seen from a guest's side — no `href`
  for a link, no global CSS for a display toggle
- **todo**, **todomvc**, **tictactoe** — collections
- **calculator** — state the declared fields do not name
- **rust-tempconv** — the polyglot proof: the same WIT, no tutuca code at all,
  built with cargo

They live in the repository rather than the published package. `tutuca
new-guest` gives you the same tree.
