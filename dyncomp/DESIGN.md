# Dynamic WebAssembly tutuca components

Status: **Phases 0–4 done and green** (see results below). WIT:
[`wit/tutuca-component.wit`](wit/tutuca-component.wit). Guests:
[`../guests/counter/`](../guests/counter/README.md) (MoonBit),
[`../guests/rust-counter/`](../guests/rust-counter/) (Rust — the polyglot
proof). Host: `dyncomp/host` (+ `dyncomp/host/wasm` bridge) with memdom
tests (`moon test dyncomp/host`). Demos: `demo/dyncomp_wasm` and the
storybook's "Dynamic" story — assemble with
`moon run --target native cmd/dev -- dist` then `-- dyncomp`, serve
`dist/`, open `/dyncomp/` or `/storybook/?story=dyncomp`. Contract
harnesses: `node --test dyncomp/test/harness.test.mjs` (and
`rust-harness.test.mjs`; `test/browser-smoke.html` served from the repo
root).

## Goal

tutuca-mb is fully AOT today: a browser app is one wasm-gc module with every
component compiled in. This design adds a WIT contract — `tutuca:component`
— such that anything implementing it (MoonBit, Rust, Go, Python, …) produces
a WebAssembly *component* that a **running** tutuca app can fetch,
instantiate, and mount into its component tree.

Three principles, in order of consequence:

1. **The host is the framework** (inversion of control). Guests import
   host-provided interfaces (`values`, `control`); the host calls guests at
   well-defined points and drives the whole lifecycle.
2. **Views are data, rendered host-side.** tutuca has no element event
   handlers — event bindings are attributes parsed at view parse time. A
   guest ships its views as tutuca HTML template strings in its manifest;
   the host compiles them with anode exactly like local views (so the
   existing renderer, event delegation, morphing, and even the linter apply
   unchanged). The guest renders nothing.
3. **Guest state is opaque.** The interface exposes only views + handlers.
   Handlers take self and return self (`handle-event -> option<instance>`,
   a *new* resource handle; `none` = unchanged). Fields are internal,
   accessed lazily by the host at render time (`get-field`). State is
   therefore uniform to the host: every guest instance, in any language,
   looks like the same opaque handle.

## Why this maps 1:1 onto existing tutuca-mb machinery

| Requirement | Existing seam |
|---|---|
| Component = views/styles only, no host-visible fields | `Component::for_type` (`component/spec.mbt`) — "fields, buckets and methods live on the struct itself" |
| Opaque state uniform to the host | one host struct `DynObj { comp_id, bundle, handle }` implementing `&Obj` (`core/spec.mbt`) wraps every guest instance |
| Handlers take self, return self | `Handler((Array[Value], &Ctx) -> &PathNode?)` (`core/path_spec.mbt`) is already self-pre-bound and returns the new self; the guest's new resource handle wraps into a fresh `DynObj` |
| Change detection / re-render / cache invalidation | a fresh `DynObj` is a new physical identity — the COW model everything already keys on |
| Render reads | `Obj::obj_field` is a lazy per-name read; only fields the views actually evaluate cross the boundary |
| Mounting a foreign bundle | the storybook precedent (`storybook/ui/engine.mbt`): register into a child scope, seed the instance `Value` into a field, render with `<x render=".slot">` — resolution is by component id in the shared registry |

No changes to `render/`, `vdom/`, or `transactor/` are needed.

## Constraints discovered by research (mid-2026)

- **Components require MoonBit's linear-memory `wasm` backend.** wasm-gc
  cannot be componentized (component-model-gc is still a pre-proposal,
  WebAssembly/component-model#525). The host app stays wasm-gc; a guest is a
  *separate* linear-memory wasm instance, bridged by JS. Only data and
  handles cross — which the opaque-state contract is built around.
- Guest pipeline: `wit-bindgen moonbit wit/ --out-dir .` → fill in
  `interface/**/stub.mbt` → `moon build --target wasm` → `wasm-tools
  component embed wit … --encoding utf16` (MoonBit strings are UTF-16) →
  `wasm-tools component new` → `npx @bytecodealliance/jco transpile
  --instantiation async` for the browser. All four tools are
  version-coupled; pin them and commit generated bindings.
  (npm note: the package is `@bytecodealliance/jco`; the bare `jco` npm name
  is a dependency-confusion placeholder.)
- The world imports **no WASI**, so no preview2 shims are needed in the
  browser.
- WIT has no recursive types → the `value` variant carries scalars inline
  and u64 *arena handles* for lists/maps, read/built through the `values`
  import. Handles live only for the current host→guest call.
- MoonBit closures cannot cross into JS on wasm-gc, so all host↔bridge
  signalling is host-driven callbacks through exports (the existing
  `on_event` / `tdom.add_listener` pattern).

## Architecture

```
        browser page (one host app, N guest bundles)
┌──────────────────────────────────────────────────────────────┐
│  host app (wasm-gc)                    JS bridge             │
│  ┌───────────────────────┐   externs   ┌──────────────────┐  │
│  │ App/Transactor/render │◄───tcomp───►│ bundle table     │  │
│  │ DynObj (&Obj) ────────┼─────────────┼─► instance table │  │
│  │ value arena           │   exports   │  import fwd      │  │
│  └───────────────────────┘  dyncomp_*  └───────┬──────────┘  │
│                                                │ jco ESM     │
│                                        ┌───────▼──────────┐  │
│                                        │ guest component  │  │
│                                        │ (linear-mem wasm)│  │
│                                        └──────────────────┘  │
└──────────────────────────────────────────────────────────────┘
```

### Host (`dyncomp/host`, wasm-gc)

- **Proxy components**: per manifest `component-def`, call
  `Component::for_type(name~, view=main_html, views={…}, style~)` and
  register into a fresh **child scope** of the app scope (per-bundle name
  isolation; shared id registry). anode parse errors of guest views surface
  as load-time diagnostics.
- **`DynObj`** implements `&Obj`: `component_id()` returns the proxy's id
  (stock view resolution); `obj_field` → `tcomp.get_field` (arena-decoded;
  `instance(h)` payloads wrap as nested `DynObj`s); `obj_seq_entries` →
  `tcomp.seq_entries`; `obj_handler(bucket, name)` returns a `Handler` that
  calls `tcomp.dispatch(...)` and wraps a returned new handle in a fresh
  `DynObj` (superseded handle queued for drop post-settle);
  `obj_render_handler` → `tcomp.call_method`; `obj_eq` → `tcomp.eq`;
  `obj_debug` → `tcomp.to_json`.
- **Lifecycle**: `load(url)` → `tcomp.load(load_id, url)`; the bridge
  `import()`s the jco ESM, `instantiate()`s it, and calls back
  `dyncomp_on_loaded(load_id, bundle_id, manifest)` /
  `dyncomp_on_load_error`. The glue synthesizes + compiles proxies, injects
  styles (`tdom_inject_css`, container class `dc-<module>-<comp>`), installs
  missing DOM listeners (names come from the *compiled* views), then pushes
  a `dyncompLoaded` send so a host handler seeds instances via
  `make_instance(bundle, component, args?) -> Value` — a plain state change.
  Explicit `destroy(value)` / `drop_bundle(id)`; tutuca has no lifecycle
  hooks, so un-destroyed instances leak (a render-generation sweep is future
  work).
- **Inspection**: `Value::to_json` maps `Obj` to null, so state display
  substitutes the guest's `to-json` projection for guest subtrees.

### Guest SDK (MoonBit)

Guests are separate moon modules under `guests/` with the wit-bindgen
layout. A template `sdk.mbt` (no tutuca dependency) exposes:

```moonbit
pub(open) trait DynComponent {
  fn def(Self) -> ComponentDef        // name/views(html)/handlers/style
  fn get_field(Self, name : String) -> Val?
  fn handle(Self, bucket : Bucket, name : String, event : DomEvent?,
            args : Array[Val], ctl : Ctl) -> Self?   // self in, self out
  fn method_(Self, name : String, args : Array[Val]) -> Val
  fn to_json(Self) -> String
}
pub fn register(module_name : String, factories : …) -> Unit
```

Non-MoonBit guests implement the WIT directly — e.g. a Rust counter is a
plain `struct Counter { count: f64 }` whose `handle_event("inc")` returns
`Some(Instance::new(Counter { count: self.count + 1.0 }))`.

### JS bridge

Extends the existing demo loader (`createJsCoreImports` /
`createTdomImports` stay as-is) with a `tcomp` import namespace: bundle
table (dynamic `import()` + `instantiate(undefined, guestImports)`),
integer-handle instance table, and guest-import forwarders —
`tutuca:component/values` forwards into `dyncomp_val_*` host exports (the
arena lives in wasm-gc memory); `tutuca:component/control` buffers into the
pending dispatch, drained through the handler's `&Ctx` on return.

## Trade-offs accepted

- Render-time field reads cross guest↔JS↔host per name. Proportional to
  what views touch; instances are immutable, so a per-render memo keyed by
  handle is a valid mitigation if profiling demands it.
- Host-side state serialization/inspection needs the guest `to-json`
  projection.
- Guest components can nest only same-bundle guest children; composition
  with host components stays parent-side (a host field holds the guest
  instance, never the reverse).
- Guest views are parsed by the *host's* anode; the manifest `api-version`
  covers template-syntax evolution.

## Phases

- **0 — spike**: real WIT through wit-bindgen-moonbit → `moon build
  --target wasm` → wasm-tools → jco → node instantiation. Gates: the
  toolchain trio, utf16 strings, multi-instance resources, and
  **resource-returning methods** (the self-in/self-out cornerstone).
  Measure a 1000-call `get-field` loop. Fallback if resource-returning
  methods fail: `handle-event -> bool` + guest-internal swap + host version
  counter (keeps the opaque contract, loses functional purity).
- **1 — counter guest + harness**: `guests/counter/` (SDK + counter with a
  real tutuca view string) + a node harness asserting manifest shape and
  functional handler semantics.
- **2 — host mount**: `dyncomp/host` (DynObj, arena, proxy synthesis, glue
  exports), `demo/dyncomp_wasm` (shell app + loader with `tcomp`), memdom
  unit tests with fake `tcomp` externs; browser demo loads a bundle by URL.
- **3 — control/methods/polish**: emit/send/request end-to-end,
  `call-method` in view expressions, `@each` via seq-entries, nested
  children + `with-field`, error surfaces, dev tasks + dist packaging,
  optional Rust guest.
- **4 — later**: storybook dynamic section, instance sweep GC, bundle
  hot-swap (state migration via the JSON projection).

## Phase 0/1 results (2026-07-17)

All gates green, in node and in a real browser (`test/browser-smoke.html`):
instantiation with host imports and no WASI; the manifest (utf16 view HTML
with `@on.click` attributes) crosses; multiple independent instances of the
exported resource; **`handle-event` returns a new owned instance and the old
one is unchanged** — resource-returning methods work through
wit-bindgen-moonbit 0.59 + jco 1.25; the guest calls `values` imports
mid-dispatch (host→guest→host re-entrancy).

Numbers: 38 KB component; ~5.4 µs per `get-field` round trip steady-state on
node (~0.3 ms for a 50-field render), ~24 µs/call cold in the browser.

Gotchas found (all documented in `guests/counter/README.md` and hidden by
the SDK): the canonical-ABI rep/handle asymmetry (returned `Instance`s are
handles via `Instance::new(rep)`; received `self`/params carry the rep);
jco emits unversioned import keys at runtime (provide both spellings);
uncalled imports are DCE'd from the component; `moon fmt` migrates the
generated `moon.mod.json`/`moon.pkg.json` to the extensionless format
(harmless — regen recreates the `.json` variants, the next `moon fmt`
re-migrates).

## Phase 2 results (2026-07-17)

The host mount works end-to-end in the browser: the demo shell (wasm-gc)
loads the jco-transpiled counter bundle **by URL at runtime**, the manifest
crosses, `register_bundle` synthesizes + compiles the proxy component into a
child scope of the live app, `make_instance` seeds a `DynObj` value into the
shell's `slot`, and the guest renders with its constructor args. Clicks on
the guest's buttons dispatch through the **stock** pipeline (delegated
listener → `on_event` → §Comp§/`data-eid` path reconstruction → DynObj's
forwarding `Handler` → `tcomp` bridge → guest `handle-event` → successor
handle → new `DynObj` → COW → morph): counter went 5 → 6 → 7 → 6. Guest
styles inject scoped under the synthesized `data-cid`; the state display
shows the guest's `to-json` projection; the existing counter_wasm demo is
regression-clean; `moon test` is 697/697 (including the new
`dyncomp/host` memdom tests driven by an in-process FakeGuest through the
real harness — render, dispatch, control drain, post-boot styles and
event_names).

**Implementation divergences from the sketch above** (all host-internal;
the WIT is unchanged):
- **The `values` arena lives in the JS bridge, not in wasm-gc memory.**
  Guest `values` imports are answered entirely in JS (no host round-trip),
  and compound values cross the JS↔host-wasm boundary as **JSON strings**
  (`Value::to_json`/`from_json`), matching the codebase's existing pattern
  for structured payloads. Arena entries are cleared after each `tcomp`
  call.
- **Control messages** are buffered JS-side per dispatch and returned in
  the dispatch result (`{next, msgs}`), then drained through the
  dispatching handler's `&Ctx` (bubble/send/request) — no separate drain
  call.
- The host side splits into backend-agnostic `dyncomp/host` (`&Guest`
  trait, `DynObj`, manifest parsing, `register_bundle`) and
  `dyncomp/host/wasm` (`WasmGuest` over the `tcomp` externs + the
  load/on_loaded lifecycle); the demo loader adds `createTcompImports`
  and dedups `add_listener` so the host can re-run `install` after a
  bundle loads.
- The guest never receives the WIT `dom-event` yet (the host passes no
  event object; event data reaches handlers through evaluated args, the
  same convention native components use). The parameter stays in the WIT
  for a later phase.
- `handle-event`'s bucket ints at the `tcomp` boundary follow WIT order
  (0=input, 1=receive, 2=response); tutuca's `Bubble` bucket is never
  forwarded (guests declare no bubble handlers in v0.1).

Deferred to Phase 3 (unchanged from the plan): emit/send/request
end-to-end beyond the memdom-tested drain (browser demo for a guest
`request` round trip), `call-method` in wasm demo views, `@each` via
seq-entries, nested same-bundle children (`instance` values +
`with-field`), instance-handle GC (successors currently accumulate in the
JS table until `drop_bundle`), and load-error UI polish.

## Phase 3 results (2026-07-17)

All deferred items landed and verified in Chrome (plus 7 memdom tests and
9 node contract tests; full suite 699/699):

- **Request round trip**: guest input handler calls `control.request`;
  the host `RequestFn` (registered via `scope.register_request_handlers`)
  responds; the response dispatches the guest's `response` bucket handler
  with `[result, error]` — browser demo doubles 7 → 14.
- **Methods in views**: `@text="$label"` evaluates through
  `obj_render_handler`/`call-method` live in the wasm demo.
- **List fields**: the guest's `history` crosses as an arena list and
  renders host-side with `@each=".history" @text="@value"`.
- **Nested same-bundle children**: a guest `Pair` creates two child
  Counters via the new **`control.make-instance`** import (WIT addition,
  with `control.drop-instance`) and exposes them as
  `value::instance(token)` fields; the host renders them with
  `<x render=".left">` and dispatch flows through TWO DynObj levels —
  the spine rebuild writes through the parent via `with-field`, with the
  child's handle recovered through the `__dyncomp_handle` protocol field
  on `&Obj` (no downcasting). Tokens live in ONE space: the bridge's
  instance table.
- **Superseded-handle GC**: a handler that returns a successor queues its
  old handle; the queue is dropped at the start of the NEXT guest
  dispatch (by then the previous transaction has settled and rendered) —
  `collect_superseded()`/`superseded_count()` in `dyncomp/host`. After
  25+ successor-producing clicks in the browser, the bridge table held 5
  entries (the live instances + one queued successor).

**Component-model constraint discovered**: a component may NOT be
re-entered while a call into it is active (jco enforces the canonical
ABI's non-reentrance: "component should have been exclusively locked").
So `control.make-instance` cannot construct the child synchronously from
inside a guest call: the bridge reserves the token immediately and
**defers the constructor call until the current guest call returns**,
draining before the arena clears so captured args stay valid (nested
children of children drain iteratively). Both the browser bridge and the
node harness implement this.

Remaining for later phases: guest `seq-entries` exercised end-to-end
(host `@each` over an instance rather than a list field), event modifiers
and drag/drop inside guest subtrees, markers nested inside compound
values, bundle hot-swap, a storybook dynamic section, and an optional
Rust guest.

## Phase 4 results (2026-07-17) — the remaining work

All verified in Chrome; `moon test` 702/702; node contract harnesses 9+1.

- **seq-entries end-to-end**: `@each` over a guest INSTANCE (not a list
  field) renders via `obj_seq_entries` → guest `seq-entries` — the shell's
  `.seq` list iterates the counter's history both on memdom and in the
  browser.
- **Event modifiers in guest views work as-is** (they're parsed host-side
  at view compile time): `@on.keydown+cancel` gates on Escape exactly like
  local components — memdom-tested. (Modifier semantics live in
  `app/app.mbt` `modifiers_pass`: keydown `+send`=Enter, `+cancel`=Escape,
  ctrl/cmd/meta/alt on keydown+click.)
- **Nested markers at any depth**: the wasm bridge decodes `{"$dyn": …}`
  markers recursively inside lists/maps (`WasmGuest::json_to_value`), and
  uses the same decoder for seq-entries and control-message args. (Host →
  guest encoding of an Obj nested inside a compound is still unsupported —
  `Value::to_json` drops it; top-level `with-field` covers the write path
  that exists.)
- **Bundle hot-swap with state migration**: reloading a module registers
  the new bundle, the shell's `dyncompLoaded` handler migrates mounted
  instances via `migrate_instance` (state-json protocol field → parsed
  projection → constructor args — the counter keeps count AND history
  across a brand-new wasm instance), and the old bundle drops after the
  synchronous settle. Load completion routes to the LOADING component via
  `load_from(ctx.path(), url)` (targeted transactor send), so any pane
  anywhere in a tree can host bundles.
- **Storybook "Dynamic" section**: the shared shell
  (`@dhw.shell_module(bundle_url~)`) is a regular story in
  demo/storybook_wasm; the pane loads/reloads bundles live inside the
  gallery (`?story=dyncomp`). The storybook dist ships the dyncomp loader
  (superset) and the `dyncomp` dev task copies the counter bundle into
  `dist/storybook/counter/`.
- **Rust guest** (`guests/rust-counter/`): the polyglot proof — the same
  WIT implemented with `wit_bindgen::generate!`, zero tutuca code, built
  via `cargo build --target wasm32-unknown-unknown` → `wasm-tools
  component new` → jco (62 KB vs MoonBit's 38 KB). The node harness
  drives it with the identical fake-host protocol
  (`dyncomp/test/rust-harness.test.mjs`): manifest, functional handlers,
  request buffering, response application, eq.

Still open (small): drag/drop inside guest subtrees is expected to work
(stock dispatch + drag_info in args) but has no test; host→guest encoding
of instances nested inside compound values; a render-generation sweep as
an alternative to explicit `destroy`; playground emission of dyncomp
bundles (needs in-browser componentize).
