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
| `dyncomp/wit` | v0.4.0 | the contract |
| `dyncomp/host` | built | registration, `DynObj`, lifecycle, GC |
| `dyncomp/policy` | built | trust tiers, capability grants, quotas, the view rule |
| `dyncomp/registry` | built | the cross-bundle catalog and its search |
| `dyncomp/jsonschema` | built | the declared schema ⇄ JSON Schema, both directions |
| `dyncomp/surface` | built | the layout model and its patch algebra |

The dependency direction is `host → policy`, `host → jsonschema`,
`registry → host`, and `surface` alone: `policy` and `jsonschema` are leaves
that `host` depends on, because a decision about a bundle and a description of
one are both things you want to reason about without a bundle in hand.

### `dyncomp/registry` — the catalog

`ComponentRef { module, name }` → `Descriptor { doc, keywords, category,
schema, inits, raises, bubbles, provenance }`, plus `search(query, limit)`
ranking over name, title, summary, keywords and field names.

This is what v0.3 of the contract was for. Before it, a component was a name
with handlers hanging off it; there was nothing to rank on and nothing for a
person or a model to read before choosing. `component-def` now carries `doc`,
`keywords`, `category` and a `message-docs` table, and `field-def` carries a
`doc` of its own.

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

Three tiers, differing in *convenience* rather than in authority — a bundle has
no ambient authority at any of them:

| | `Untrusted` (default) | `Granted` | `System` |
|---|---|---|---|
| `cap-clock` / `cap-random` | no | yes | yes |
| `cap-timer` | no | no | yes |
| its own CSS | no | yes | yes |

An ungranted capability **refuses the bundle** rather than degrading it: a guest
reading a frozen zero from an ungranted clock cannot tell that from midnight.
The untrusted tier is the one this design is *for*, and a bundle there can still
declare components, ship views, hold state, handle events, nest children and
serve its own requests — all three sample guests run under it unchanged.

Also here: the `@dangerouslysetinnerhtml` refusal, and quotas on manifest size
(an availability bound, not a security one — the host parses every view before
it renders anything). Still to come, and marked as such in the code: the
`mizchi/css` style validator (until it lands, `allow_custom_css` means someone
vouched, not that anything checked), the Sanitizer-API config over the ANode
tree, and content-addressed bundle ids.

### `dyncomp/surface` — layout as data

The layout tree is ordinary tutuca state, so both layers edit the same thing.
Host components, authored the normal way (a `surface.html` with a
`tutuca/state` block and templates, through `gen-views`):

- **`Stack`** — the flex subset: `direction | wrap | justify | align | gap | padding`
- **`Grid`** — the grid subset: `columns` / `rows` as lists of `Nfr | Npx | auto`,
  `gap`, `autoFlow`; per-cell `colSpan` / `rowSpan` / `colStart` / `rowStart`
- **`Box`** — `padding | border | background | overflow`
- **`Slot`** — holds one component instance
- **`Surface`** — the root, plus the data model

Both containers hold `children: values` — a list of arbitrary component values,
which is exactly what `ComponentList.entries` in `demo/universal_wasm` already
is. So recursive nesting needs no framework change, and the existing demo is the
proof. Styling follows the `FlexStyle` precedent there: a `compute` returning an
inline CSS string, which also keeps layout CSS host-generated and therefore
outside the guest-CSS validator entirely.

The patch algebra is the seam both layers drive:

```
SurfaceOp =
  | AddNode(parent, index, kind, props)
  | RemoveNode(nodeId)
  | MoveNode(nodeId, parent, index)
  | SetProps(nodeId, props)
  | BindInstance(nodeId, ComponentRef, argsJson)
  | SetData(pointer, valueJson)        // RFC 6901 pointer into the data model
```

`apply(surface, ops) -> Result[Surface, Array[OpError]]`, atomic per batch, with
errors carrying the failing op index and a JSON Pointer.

## Layer 1 — the universal UI

`demo/universal_wasm` grows into this. Four pieces, all over the core:

- **Palette and search** over `dyncomp/registry`, replacing `ComponentPicker`'s
  substring filter.
- **An instantiate form** generated from `dyncomp/jsonschema`. This generalizes
  `inspector/state_editor.mbt`, which today picks a control per `FieldKind` and
  falls back to read-only for `FList | FMap | FAny | FComp | FSet | FOMap`. It
  needs repeatable rows for lists, key/value rows for maps, a picker for
  `TyComp`, and the v3 `constraint` for validation.
- **A layout editor** over `dyncomp/surface`: add and remove cells, reorder,
  switch a container between Stack and Grid, edit its settings.
- **An inspector pane** reusing `inspector/` over `Obj::obj_schema`.

Plus import/export of the surface as JSON — which is also the agent's wire
format, and the cheapest possible proof that the two layers share a core.

## Layer 2 — the agent runtime

A new `agent/` tree driving the *same* core. See
[`../docs/agent-runtime.md`](../docs/agent-runtime.md) for the tool surface and
the protocol mapping. In outline:

- `agent/tools` — six stable tools whose `parameters` schemas come from
  `dyncomp/jsonschema`.
- `agent/session` — a session over `registry` + `surface`. A user interaction
  that bubbles to the surface root becomes an agent event in A2UI's `action`
  shape.
- `agent/agui` — the AG-UI event encoding, including `STATE_DELTA` as RFC 6902
  patches computed over the surface and data model.

## How the pieces line up

| AG-UI / A2UI concept | the seam here |
|---|---|
| catalog | `dyncomp/registry` over registered bundles |
| catalog negotiation by id | `api-version` plus the content-addressed bundle id |
| surface | `dyncomp/surface` |
| `updateComponents` | the patch algebra's node ops |
| data model, JSON Pointer binding | tutuca's own path/dispatch runtime in `core/` |
| `action` / event to the agent | `control.emit` bubbling to the surface root |
| `functionCall` (local) | host request handlers, via `lookup_request` |
| validation error feedback | `Bundle::diagnostics()` plus JSON Schema errors |
| `STATE_DELTA` | a `Value` diff over the schema projection |
| tool `parameters` | `dyncomp/jsonschema` over the declared schema |

The right-hand column is almost entirely things that already exist. That is the
argument for this shape: the two layers are mostly a matter of *exposing* the
core rather than building beside it.

## Order of work

The four core packages are **done**: `jsonschema`, `registry`, `surface` and
`policy`, with `host` wired to the last two.

What is left, in order:

1. **Layer 1**, over what now exists. It is next rather than the agent layer for
   a reason: the human layer is the cheapest way to find out whether the core is
   right before something automated depends on it. The pieces are a palette over
   `registry.search`, a form generated from `Descriptor::args_schema`, an editor
   over the patch algebra, and import/export of `Surface::to_json`.
2. **The security work `policy` names but does not yet do**: the `mizchi/css`
   validator, the Sanitizer-API port, and caller-aware request authorization,
   which needs `RequestFn` to carry the requester's `DispatchPath`
   (`SECURITY.md` §3–§5).
3. **Two debts from the v0.3 bump**: `manifest.capabilities` is now enforced,
   but `control.after` still has no host implementation (it needs a timer the
   transactor owns), and the bridge supplies `env` unconditionally rather than
   per grant.
4. **Layer 2**.
