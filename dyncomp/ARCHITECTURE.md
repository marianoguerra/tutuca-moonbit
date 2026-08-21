# One core, two layers

`dyncomp/` proves that a WebAssembly component from anywhere can register into a
running tutuca app and render through the stock machinery. This document is the
plan for turning that into a base runtime with two things built on it: a
**universal UI** a person drives, and an **agent runtime** a language model
drives. They are the same system; only the driver differs.

[`DESIGN.md`](DESIGN.md) is the contract and how it maps onto tutuca.
[`SECURITY.md`](SECURITY.md) is what a bundle can and cannot do. This is the
shape of what sits above them.

## Where this sits in the ecosystem

Three specifications cover adjacent ground, and reading them is what made the
shape below obvious.

**AG-UI** ([docs.ag-ui.com](https://docs.ag-ui.com)) is a transport and event
protocol, and says so explicitly: *"AG-UI is not a generative UI specification —
it's a User Interaction protocol."* The parts worth adopting are its event
taxonomy (`RUN_*`, `TOOL_CALL_START/ARGS/END/RESULT`, `STATE_SNAPSHOT` and
`STATE_DELTA` as RFC 6902 JSON Patch, `CUSTOM`), its tool shape
(`{ name, description, parameters: <JSON Schema> }`), and its interrupt/resume
contract for human-in-the-loop.

**A2UI** ([a2ui.org](https://a2ui.org)) is the closest prior art and validates
most of this design: a *catalog* of trusted components, a flat adjacency list of
components referring to each other by id, a separate data model bound by JSON
Pointer, and actions split into a local `functionCall` and an agent `event`.
Its stated limitation is the interesting part:

> **No Runtime Fetching:** the catalog definition must be known to the agent and
> client beforehand (at compile/deploy time).

**MCP Apps / MCP-UI** takes the other branch: arbitrary HTML in a sandboxed
iframe with a `postMessage` JSON-RPC bridge. Maximum expressiveness, an
origin-level trust boundary, and nothing introspectable to search or to generate
a form from.

dyncomp sits at a third point neither occupies. A2UI's catalog is safe because
it is fixed; MCP-UI's content is arbitrary because it is quarantined. Here the
**catalog itself is extensible at runtime by untrusted parties**, because a
component is a linear-memory wasm module with no ambient authority whose views
are data the host compiles — and whose state has a *declared shape*, so it can
be searched, formed and described without anyone trusting it.

That declared shape is what makes both layers possible from one core.

## The core

| package | status | responsibility |
|---|---|---|
| `dyncomp/wit` | v0.9.0 | the runtime behavior contract; static declaration lives in each bundle |
| `dyncomp/host` | built | registration, `DynObj`, lifecycle, GC |
| `dyncomp/policy` | built | trust tiers, capability grants, quotas, the view rule |
| `dyncomp/registry` | built | the cross-bundle catalog and its search |
| `dyncomp/jsonschema` | built | the declared schema ⇄ JSON Schema, both directions |
| `dyncomp/ui/std` | built | the standard components: the layout, and the `+` |

The dependency direction is `host → policy`, `host → jsonschema`,
`registry → host`, and `ui/std` alone: `policy` and `jsonschema` are leaves
that `host` depends on, because a decision about a bundle and a description of
one are both things you want to reason about without a bundle in hand. `ui/std`
depends on nothing in `dyncomp/` at all — it is ordinary components, and
knowing what a bundle is would be the wrong shape for the one thing every page
is made of.

### `dyncomp/registry` — the catalog

`ComponentRef { module, name }` → `Descriptor { doc, keywords, category,
schema, inits, raises, intents, provenance }`, plus `search(query, limit)`
ranking over name, title, summary, keywords and field names.

This is what v0.3 of the contract was for. Before it, a component was a name
with handlers hanging off it; there was nothing to rank on and nothing for a
person or a model to read before choosing. The static manifest now carries
`doc`, `keywords`, `category` and a `messageDocs` table, and each field carries
a `doc` of its own.

The universal demo's `listComponents` request handler becomes a thin caller of
this, instead of building rows inline from `@dhw.loaded_components()`.

### `dyncomp/jsonschema` — one projection, two consumers

The linchpin. `SchemaInfo` / `TyInfo` / `FieldInfo` plus the v3 `constraint`
project to JSON Schema (draft 2020-12) with a `$defs` table:

| `TyInfo` | JSON Schema |
|---|---|
| `TyBool` / `TyInt` / `TyFloat` / `TyText` | `boolean` / `integer` / `number` / `string` |
| `TyList(e)` | `array` + `items` |
| `TyTuple(ts)` | `array` + `prefixItems` |
| `TyOption(e)` | the element, not required |
| `TyOMap(v)` | `object` + `additionalProperties` |
| `TyFlags(_, ms)` | `array` + `items.enum` |
| `TySet` | `array` + `uniqueItems` |
| `TyRecord` / `TyEnum` / `TyVariant` | `$ref` into `$defs` |
| `TyComp(c)` | `$ref` to a component-reference schema |
| `TyAny` | `true` |

`TyRecord` / `TyEnum` / `TyVariant` become a *titled but unconstrained* `$defs`
entry, because the declared schema knows a record's name and not its fields —
core says so outright, "enough to label it, not enough to open it". Claiming
`type: object` there would be inventing a fact, since a declared `enum` is a
string.

The reverse direction validates and coerces incoming JSON into constructor args,
collecting **every** error rather than the first, each with a JSON Pointer. A
caller that fixed one field per round trip would take as many round trips as it
has mistakes, which is what makes a tool call unusable to a model and a form
unpleasant to a person. `pattern` and `format` are carried into the emitted
schema and deliberately *not* checked on the way in: there is no regex engine
here, and a check that silently passed everything would be worse than an absent
one. A caller that needs them enforced validates against the emitted schema with
[`mizchi/jsonschema`](https://mooncakes.io/docs/mizchi/jsonschema).

`inspector/schema.mbt` already *renders* a JSON Schema; this package *produces*
one, and the two meet in the universal UI.

### `dyncomp/policy` — the decisions

The executable half of [`SECURITY.md`](SECURITY.md). `host` owns the mechanics
of loading, this owns the decisions, and `register_bundle` takes a `Policy`
(defaulting to `untrusted`) and enforces it before it parses anything.

Three tiers, differing in authority deliberately extended by the host:

| | `Untrusted` (default) | `Granted` | `System` |
|---|---|---|---|
| `cap-clock` / `cap-random` | no | yes | yes |
| `cap-timer` | no | no | yes |
| `cap-external-urls` | grantable — `allowing_external_urls(origins)`, or `with_config` binding an `origin` variable | yes | yes |
| its own CSS | no | yes | yes |
| direct DOM URL/CSS sinks | no — `<img src>` / `<a href>` only with `cap-external-urls`, and only to an origin settled before render: a literal the view states, or a config var the host bound | yes, render-time scheme filtered | yes, render-time scheme filtered |
| sanitized runtime HTML | no | configurable | configurable |

An ungranted capability **refuses the bundle** rather than degrading it: a guest
reading a frozen zero from an ungranted clock cannot tell that from midnight.
The untrusted tier is the one this design is *for*, and a bundle there can still
declare components, ship views, hold state, handle events, nest children and
serve its own requests — most sample guests run under it unchanged, and the two
that display other people's records ask for `cap-external-urls` and name the
origins they spend it on (`guests/bluesky`, `guests/slack`).

Also here: the Sanitizer-API config over the ANode tree (`anode/sanitize`, run by
`check_view`), the untrusted authority walk that refuses direct network/CSS
sinks while retaining autonomous custom elements, the render-time URL filter
(`vdom/filter`), and quotas on manifest/archive size. Still to come, and marked
as such in the code: the `mizchi/css` style validator (until it lands,
`allow_custom_css` means someone vouched, not that anything checked) and
content-addressed bundle ids.

### `dyncomp/ui/std` — layout as components

There is no layout document. The component tree IS the layout, and every piece
of it is an ordinary tutuca component authored the normal way (`std.html` with a
`tutuca/state` block and templates, through `gen-views`):

- **`Universal`** — holds one thing, or draws a `+`. The only one that MUST
  exist.
- **`Stack`** — the flex subset: `direction | wrap | justify | align | gap | padding`
- **`Grid`** — uniform `cols × rows`, every cell the same size, children in
  row-major order
- **`Tabs`** / **`TabPage`** — several pages, one at a time
- **`Text`** / **`Textarea`** — leaves

Containers hold `children: values`, so recursive nesting needs no framework
change. Styling is a `compute` returning an inline CSS string, which keeps
layout CSS host-generated and therefore outside the guest-CSS validator
entirely.

The design turns on one decision: **`Universal` is a holder, not a placeholder
that gets replaced.** Everything a person places sits inside one, which gives
the editing chrome — the badge, the `×`, the config-pill drop target — a single
host-owned home that nothing has to opt into. A guest component is decorated
exactly like a standard one, because neither of them is asked to participate.
It also makes every container's children uniform, so "insert a cell here" is
always "insert an empty universal at index i", with no kind to decide and no
binding to invent.

Edit mode is a VIEW, not a field. The app pushes `edit` with `@push-view` and
every component that declares one shows its affordances; a component that does
not — every guest, and every leaf here — is simply itself in both modes. A
boolean threaded through the tree would be the same fact stored once per node,
and a guest, which cannot grow the field, could never join in.

Standard components are in the catalog beside loaded ones (`dyncomp/ui/builtins.mbt`
builds a `Descriptor` from each one's own declared schema). The same search
ranks them, the same generated form configures them, and the same validator
refuses their bad arguments. The ONE place they are told apart is construction:
one is compiled in, the other arrived in an archive.

### What replaced the patch algebra

An earlier version of this document specified a `Surface` document with a
six-op patch algebra (`AddNode`/`RemoveNode`/`MoveNode`/`SetProps`/`BindInstance`/
`SetData`), applied atomically, as "the seam both layers drive". It was built,
and it is gone.

What replaced it is the runtime `core/` already had. A `+` raises an intent that
walks to the app; `ctx.target_path()` is the FIXED path of the component that
raised it, however many hops the walk took; the app holds that path across
dispatches and `send_at_path`s the answer back to exactly that component. Asking
and answering are two separate dispatches — a bar opens over the whole page, the
choice comes later — and the path is the whole mechanism.

The trade is real and worth stating plainly. What was lost: a serializable
document with one atomic apply, and a wire format an agent could diff. What was
gained: one class of thing instead of two, and a seam that reaches INSIDE a
guest's own placeholder — which a document describing only the host's layout
never could.

## Layer 1 — the universal UI

Built. `dyncomp/ui` is the app and `demo/universal_wasm` is the page around it;
the whole viewport is the app, and the bar keeps only what a host has to supply
(loading a bundle) plus the config pill and the mode toggle.

- **The root is one component, and it starts as a `Universal`.** The first thing
  a person does is choose what the page is; everything after that is the same
  gesture one level in.
- **A command bar** over `dyncomp/registry.search`, opened by a `+` and aimed at
  the cell that raised it. Keyboard-navigable; the cursor moves by telling two
  rows about it rather than by rebuilding the list, because rebuilding would
  replace the `<input>` being typed in.
- **A generated form** from `dyncomp/jsonschema`, opened by ctrl/cmd — or
  automatically, when a component has a required argument with no default. The
  same projection an agent's tool reads is the one it draws.
- **A config sidebar**, opened by clicking a badge or dropping the pill on a
  cell. A component that declares a `config` view of its own gets it rendered
  live; everything else gets the form, pre-filled from what the instance
  already holds. Applying writes through the instance's own COW rather than
  rebuilding it, so what the schema does not name survives.
- **Hover-only insert buttons** on the containers: before each child and after
  the last on a `Stack`, one per edge on a `Grid`.

What is still missing: an inspector pane reusing `inspector/` over
`Obj::obj_schema`, and richer form controls (repeatable rows for lists,
key/value rows for maps, a picker for `TyComp`).

The proof it holds together is the notepad reproduced by composition — tabs, a
tab holding a universal, pick a textarea — with no bespoke guest and nothing
written for notepads. It is a test in `dyncomp/ui/ui_test.mbt`, and it is why
`guests/rust-notepad` no longer exists: a component that primitives can be
composed into is not one worth shipping. The Rust guest is now a temperature
converter (`guests/rust-tempconv`), which primitives cannot express — it holds a
number three ways at once, and a half-typed one that is not a number at all.

## Layer 2 — the agent runtime

A new `agent/` tree driving the *same* core. The tool surface **needs designing**
before any of it is built: the document that once specified it described an
`ui_apply` over `SurfaceOp`s that no longer exist, and has been deleted. In
outline:

- `agent/tools` — stable tools whose `parameters` schemas come from
  `dyncomp/jsonschema`, which is unchanged and still the right seam.
- `agent/session` — a session over `registry` plus the component tree. The
  operations are the ones the human layer already uses: address a component by
  path, send it a message, read its declared fields back. A user interaction
  that reaches the app becomes an agent event in A2UI's `action` shape.
- `agent/agui` — the AG-UI event encoding. `STATE_DELTA` is the open question:
  a diff over the component tree's schema projection rather than over a
  document, and nothing has been written for it yet.

## How the pieces line up

| AG-UI / A2UI concept | the seam here |
|---|---|
| catalog | `dyncomp/registry` over registered bundles |
| catalog negotiation by id | `api-version` plus the content-addressed bundle id |
| surface | the component tree itself (`dyncomp/ui/std`) |
| `updateComponents` | messages to a component at a path |
| data model, JSON Pointer binding | tutuca's own path/dispatch runtime in `core/` |
| `action` / event to the agent | `control.emit` bubbling to the app root |
| `functionCall` (local) | host request handlers, via `lookup_request` |
| validation error feedback | `Bundle::diagnostics()` plus JSON Schema errors |
| `STATE_DELTA` | a `Value` diff over the schema projection (unbuilt) |
| tool `parameters` | `dyncomp/jsonschema` over the declared schema |

The right-hand column is almost entirely things that already exist. That is the
argument for this shape: the two layers are mostly a matter of *exposing* the
core rather than building beside it.

## Order of work

The core packages are **done**: `jsonschema`, `registry` and `policy`, with
`host` wired to the last two. **Layer 1 is built** (see above).

What is left, in order:

1. **The rest of Layer 1**: an inspector pane over `Obj::obj_schema`, richer
   form controls (lists, maps, a picker for `TyComp`), a settings panel for a
   container's own properties beyond what the generated form gives, and
   import/export of a page as JSON. The DOCUMENT for that is built — the page is
   a tagged `$component` tree (`core/component_json.mbt`), written and read by
   `UniversalUi::tree_of_json` and its encode twin, which is what the shell now
   puts in `localStorage`. What is left is the two buttons.
2. **The security work `policy` names but does not yet do**: the `mizchi/css`
   validator and caller-aware request authorization, which needs `RequestFn` to
   carry the requester's `DispatchPath` (`SECURITY.md` §4–§5). The Sanitizer-API
   port landed; what is left of it is the spec's default allow-list and
   re-admitting raw markup through the render-time filter
   (`docs/sanitizer.md`).
3. **Two debts from the v0.3 bump**: `manifest.capabilities` is now enforced,
   but `control.after` still has no host implementation (it needs a timer the
   transactor owns), and the bridge supplies `env` unconditionally rather than
   per grant.
4. **Design the agent tool surface** from what the tree actually offers —
   address a component by path, send it a message, read its declared fields
   back — rather than from the document it used to be specified against. Then
   Layer 2.

## Known gaps in what is built

Stated here rather than left to be discovered:

- **A guest's placeholder does not survive a reload.** `Bundle::make_instance`
  fills a declared foreign `ty-comp` field, and a restore rebuilds the guest
  from its snapshot — which fills the placeholder fresh. What a person put in
  it is lost. Carrying it needs the placeholder's contents in the snapshot,
  which the host can do and does not yet. The codec is no longer the obstacle:
  `Snapshot.fields` is a flat `Value::from_json` per key
  (`dyncomp/persist/persist.mbt`), and moving it to `from_component_json` would
  make a nested instance in that projection come back.
- **A nested same-bundle child gets no placeholders at all.**
  `Bundle::wrap_instance` runs on every read of such a field, so filling there
  would rebuild the placeholder per read; the fix is a host-side table keyed by
  guest token.
- **A live `config` view costs the cell it came from.** An instance rendered in
  two places has one of them holding a handle the host has already collected,
  so the sidebar MOVES it and the canvas shows a placeholder until the panel
  closes. The generated-form path — the common one — leaves it where it is.
- **`describe_instance` matches by declared name.** Two modules declaring the
  same component name make the config sidebar ambiguous; the first match wins,
  and the catalog puts the standard components first.
