# Dynamic WebAssembly tutuca components

A WIT contract — [`wit/tutuca-component.wit`](wit/tutuca-component.wit),
`tutuca:component@0.3.0` — such that anything implementing it (MoonBit, Rust,
Go, Python, …) produces a WebAssembly *component* that a **running** tutuca app
can fetch, instantiate, and mount into its component tree.

Two companion documents: [`SECURITY.md`](SECURITY.md) — what a bundle can and
cannot do, checked against the code — and [`ARCHITECTURE.md`](ARCHITECTURE.md)
— the plan for the universal UI and the agent runtime built on this.

- Host: [`host/`](host/) (backend-agnostic) + [`host/wasm/`](host/wasm/) (the
  `tcomp` bridge for wasm-gc), with memdom tests: `moon test dyncomp/host`.
- Guests: [`../guests/counter/`](../guests/counter/README.md) and
  [`../guests/todo/`](../guests/todo/README.md) (MoonBit),
  [`../guests/rust-counter/`](../guests/rust-counter/) (Rust — the polyglot
  proof). One WIT, no copies: a guest cannot implement a different contract
  than the host expects.
- Demo: `demo/universal_wasm` — the ONE page that hosts runtime-loaded
  bundles. `moon run --target native cmd/dev -- universal`, serve `dist/`,
  open `/universal/`. Drop a `.tutuca.tar.gz` on it, or load one by URL.
- Contract harnesses: `node --test dyncomp/test/harness.test.mjs
  dyncomp/test/rust-harness.test.mjs`; `test/browser-smoke.html` served from
  the repo root.

## Four principles, in order of consequence

1. **The host is the framework** (inversion of control). Guests import
   host-provided interfaces (`values`, `control`); the host calls guests at
   well-defined points and drives the whole lifecycle.
2. **Views are data, rendered host-side.** tutuca has no element event
   handlers — event bindings are attributes parsed at view parse time. A guest
   ships its views as tutuca HTML template strings in its manifest; the host
   compiles them with anode exactly like local views (so the renderer, event
   delegation, morphing, modifiers and the linter apply unchanged). The guest
   renders nothing.
3. **State is opaque, its SHAPE is declared.** The interface exposes views,
   handlers and a schema. Handlers take self and return self
   (`handle-event -> option<instance>`, a *new* resource handle; `none` =
   unchanged); fields are read lazily by the host at render time
   (`get-field`). The schema says what fields exist and what they hold — it
   never carries their values.

4. **Ambient authority is granted, never assumed.** The world imports no WASI.
   The three facts a component cannot compute for itself — the time, a random
   number, a fresh id — live in `env`, each behind a capability the manifest
   requests and the host grants, and each answered more weakly than the
   platform would (a coarsened, per-dispatch-frozen clock; a seeded PRNG). An
   ungranted capability refuses the bundle rather than degrading it.

That third principle is what makes the contract small. Everything generic over
a schema works on a guest without the guest implementing any of it: structural
equality (`Obj::obj_eq`), the JSON projection (`Value::to_json`), the debug
rendering, hot-swap migration, the inspector's form, the generated per-field
mutators (`setCount`, `toggleDone`, `pushInItems`, …), and — since v3 — the
catalog entry a search ranks and a language model reads. A guest that declares
`count: s32` gets a working `setCount` with no guest code at all.

The fourth is what makes the first three worth having. A component whose state
is opaque but whose shape is declared can be searched, formed and described
without anyone trusting it; a component with no ambient authority can be
mounted from anywhere. Neither property is useful alone.

## How it maps onto existing tutuca machinery

| Requirement | Existing seam |
|---|---|
| Component = views + a declared schema | `Component::for_type(name~, views~, schema~)` |
| Opaque state uniform to the host | one host struct `DynObj` implementing `&Obj` (`core/spec.mbt`) wraps every guest instance |
| What the instance IS | `Obj::obj_schema` — built from the manifest in `register_bundle` |
| Handlers take self, return self | `Handler((Array[Value], &Ctx) -> Value?)` is already self-pre-bound; the guest's new handle wraps into a fresh `DynObj` |
| Change detection / re-render | a fresh `DynObj` is a new physical identity — the COW model everything keys on — carrying the predecessor's `ObjId` at the next revision, so the render cache still hits |
| Render reads | `Obj::obj_field` is a lazy per-name read; only fields the views evaluate cross the boundary |
| Generated mutators | `@component.schema_mutators` over a `FieldBox` — one implementation, used by typed instances and guests alike |
| Mounting a foreign bundle | a child scope of the app scope (per-bundle name isolation, shared id registry), resolution by component id |
| A bundle's own services | request handlers registered in that child scope, so `lookup_request` finds them before the host's |

No changes to `render/` or `vdom/` are needed.

## Constraints (discovered by research, mid-2026)

- **Components require MoonBit's linear-memory `wasm` backend.** wasm-gc cannot
  be componentized (component-model-gc is still a pre-proposal,
  WebAssembly/component-model#525). The host app stays wasm-gc; a guest is a
  *separate* linear-memory wasm instance, bridged by JS. Only data and handles
  cross — which the opaque-state contract is built around.
- Guest pipeline: `wit-bindgen moonbit <this dir's wit/>` → fill in the
  component file → `moon build --target wasm` → `wasm-tools component embed
  --encoding utf16` (MoonBit strings are UTF-16) → `wasm-tools component new`
  → `jco transpile --instantiation async`. All four tools are version-coupled;
  pin them and commit the generated bindings. Here: `guests/build-guest.mjs
  <name>` and `cmd/dev -- gen-guest-bindings` (regenerate + drift check).
- The world imports **no WASI**, so no preview2 shims are needed in the browser.
- WIT has **no recursive types**, twice over: the `value` variant carries
  scalars inline and u64 *arena handles* for lists/maps (handles live only for
  the current host→guest call), and a declared field's type is a flat table of
  `ty-def`s that point at each other by index.
- A component may **not be re-entered** while a call into it is active (jco
  enforces the canonical ABI's non-reentrance). So `control.make-instance`
  cannot construct a child synchronously from inside a guest call: the bridge
  reserves the token and defers the constructor until the current call returns,
  draining before the arena clears so captured args stay valid.
- MoonBit closures cannot cross into JS on wasm-gc, so all host↔bridge
  signalling is host-driven callbacks through exports.

## Architecture

```
        browser page (one host app, N guest bundles)
┌──────────────────────────────────────────────────────────────┐
│  host app (wasm-gc)                    JS bridge             │
│  ┌───────────────────────┐   externs   ┌──────────────────┐  │
│  │ App/Transactor/render │◄───tcomp───►│ bundle table     │  │
│  │ DynObj (&Obj) ────────┼─────────────┼─► instance table │  │
│  │ schema + mutators     │   exports   │  value arena     │  │
│  └───────────────────────┘  dyncomp_*  └───────┬──────────┘  │
│                                                │ jco ESM     │
│                                        ┌───────▼──────────┐  │
│                                        │ guest component  │  │
│                                        │ (linear-mem wasm)│  │
│                                        └──────────────────┘  │
└──────────────────────────────────────────────────────────────┘
```

### Host (`host/`, backend-agnostic)

- **`register_bundle`**: per manifest `component-def`, build each view at
  runtime with `@anode.View::new` (a guest's views arrive as source, so they
  cannot be compiled ahead of time), build the declared `SchemaInfo`, call
  `Component::for_type`, and register into a fresh child scope. Then compile —
  which is also where the `@on` names the views raise are read off the compiled
  tree and folded into the schema's `inputs`. Guest view parse errors surface
  as the compile error; lint findings surface as `Bundle::diagnostics()`.
- **`DynObj`** implements `&Obj`: `component_id` → the synthesized component
  (stock view resolution); `obj_field` → `get-field` (arena-decoded; `instance`
  payloads wrap as nested `DynObj`s), falling back to the schema's mutators;
  `obj_schema` → what the guest declared; `obj_seq_entries` → `seq-entries`;
  `obj_callable` → `call-method`, in the value namespace and the render-time
  (`@when`) one; `obj_handler` → a `Handler` that either applies a generated
  mutator through `with-field` or forwards to `handle-event` and drains the
  guest's buffered `control` calls through the dispatching `&Ctx`.
- **Lifecycle**: a load registers the bundle, refreshes listeners and styles,
  and pushes a `dyncompLoaded` message so a host component seeds instances as a
  plain state change. Loading a module that is already registered hot-swaps it:
  the host component migrates what it holds (`Bundle::migrate_instance`, which
  reads the old instance's declared fields) and the old bundle is dropped after
  the settle.
- **Superseded handles**: a handler that returns a successor makes the old
  guest instance garbage. `install_gc(transactor)` sweeps them at the end of
  every drained cascade — after the App's own re-render, since that is what
  still reads the successors.

### Guest SDK (MoonBit)

Guests are separate moon modules under `guests/` with the wit-bindgen layout. A
template `sdk.mbt` (no tutuca dependency) implements every generated `declare`
over a `DynComponent` trait, so authoring a guest is: one struct per component
implementing that trait, plus a `dyn_module()` listing the `ComponentDef`s,
their factories, and the bundle's `serve` (its own request handlers).
Non-MoonBit guests implement the WIT directly — the Rust counter is a plain
`struct Counter { count: f64 }` with zero tutuca code.

### JS bridge (`demo/wasm-loader-lib.mjs`)

A `tcomp` import namespace beside the existing `jscore` / `tdom` ones: the
bundle table (dynamic `import()` + `instantiate`), an integer-handle instance
table, the `values` arena (answered entirely in JS — compounds cross the
JS↔host-wasm boundary as JSON), and the `control` buffer drained through the
dispatch result. Bundles arrive as a single `.tutuca.tar.gz` — gunzipped with
`DecompressionStream` and untarred in-browser — named either by a dropped
file's id or by URL.

## What a guest declares, and what it does not

| It declares | It does NOT declare |
|---|---|
| its views (tutuca template source) | which `@on` names those views raise — the host reads them off the compiled views |
| its fields, over a flat type table | how to project them to JSON, or how to compare two instances — the host does both from the schema |
| the input names it ANSWERS ITSELF | the rest: those are the mutators its fields imply, applied host-side through `with-field` |
| `receives` / `bubbles` / `responses` | how they are routed — that is the transactor's |
| `methods` and `whens` (`@when` filters) | — |
| `requests` it serves, and named `inits` | which HOST requests it may reach — the host decides that per call, from the requester's path |
| what it is, in sentences: `doc`, `keywords`, `category`, `message-docs`, per-field `doc` and `constraint` | anything that resolves — the metadata is advisory, and a bundle's identity is the hash of its archive |
| the capabilities it needs (`cap-clock` / `cap-random` / `cap-timer`) | whether it gets them |
| a SCOPED style, or none | any global CSS — there is no field for it, deliberately |

## Trade-offs accepted

- Render-time field reads cross guest↔JS↔host per name. Proportional to what
  views touch; instances are immutable, so a per-render memo keyed by handle is
  a valid mitigation if profiling demands it.
- Guest components nest only same-bundle guest children; composition with host
  components stays parent-side (a host field holds the guest instance, never
  the reverse).
- Guest views are parsed by the *host's* anode; the manifest `api-version`
  covers template-syntax and contract evolution, and a mismatch is refused
  rather than adapted.
- A generated mutator name a guest wants for logic of its own has to be
  declared in `handlers` (`resetLeft` is both a plausible handler and the
  mutator a `left` field implies). `handle-event` is one opaque entry point, so
  the host cannot ask "is this yours?" without calling it.
- `@dangerouslysetinnerhtml` is refused in a guest view, so a bundle that
  genuinely needs to render markup cannot. Its value is an expression, so no
  registration-time pass can see what it will hold; refusing the construct is
  the only decision available ahead of time. A Sanitizer-API pass over the
  rendered markup is what would let it back in (`SECURITY.md` §3).
- Nothing in `env` is a real clock or real entropy, by design. A component that
  needs either asks the host through `control.request`.

## Still open

- Host → guest encoding of an instance nested inside a compound value
  (`with-field` covers the write path that exists).
- A render-generation sweep as an alternative to explicit `destroy` for
  instances a host seeded and dropped.
- Playground emission of dyncomp bundles (needs in-browser componentize).
- `@enrich-with` / `@loop-with` for guests: `@when` reaches `call-method`
  today, the other two render-time buckets do not.
- The BRIDGE still supplies `env` unconditionally rather than per grant.
  `register_bundle` now refuses a bundle whose capabilities the policy does not
  grant, so a guest cannot legitimately reach it — but the import is there, and
  closing that is the bridge's half of the same job.
- `control.after` is in the contract and has no host implementation; it needs a
  timer the transactor owns.
- A per-bundle cap on LIVE INSTANCES, which unlike the other quotas has to be
  enforced at `make_instance` time rather than at registration.
- Caller-aware authorization of HOST request handlers, which needs `RequestFn`
  to carry the requester's `DispatchPath` (`SECURITY.md` §5).
- Whether the `values` arena earns its keep now that compounds already cross
  the JS↔host boundary as JSON — a measurement, not an argument.
