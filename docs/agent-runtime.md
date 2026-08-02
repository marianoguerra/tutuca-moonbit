# The agent universal component runtime

A language model should be able to build a working interface out of components
it has never seen, loaded at runtime from sources nobody vetted. This document
is the design for how it addresses them.

It sits on the core described in [`../dyncomp/ARCHITECTURE.md`](../dyncomp/ARCHITECTURE.md);
what a loaded component may do is in [`../dyncomp/SECURITY.md`](../dyncomp/SECURITY.md).
For the human-facing half — hosting a bundle, and writing one — see
[`dynamic-components.md`](dynamic-components.md).
Nothing here is built yet — the `tutuca:component` contract is, and it is the
half that makes the rest possible.

> **This document is out of date and needs redesigning before anything in it is
> built.** Its `ui_read` / `ui_apply` pair is specified over the `Surface`
> document and its six-op patch algebra, which were built and have since been
> **removed**: the component tree is the layout now, and it is addressed by path
> and message rather than by node id and op (see
> [`../dyncomp/ARCHITECTURE.md`](../dyncomp/ARCHITECTURE.md), "What replaced the
> patch algebra"). What survives unchanged is the half this document argues
> hardest for — a catalog searched at runtime, and tool `parameters` projected
> from a component's declared schema. What needs rethinking is how a model
> *edits*: what an atomic batch means without a document to apply it to, and
> what `STATE_DELTA` diffs over. Read the rest as motivation, not as a spec.

## Why this is a different problem from the usual generative UI

Both established answers assume the set of components is fixed before the
conversation starts.

**A2UI** hands the model a catalog and validates its JSON against it. Safe,
introspectable, and explicitly closed: *"the catalog definition must be known to
the agent and client beforehand (at compile/deploy time)."*

**MCP Apps** hands the model an iframe. Open, expressive, and opaque: there is
no schema to search, no shape to generate a form from, and no way to ask what a
widget's state is.

dyncomp is open *and* introspectable, because a component declares its shape
without revealing its state. That is what the whole contract is arranged around,
and it is what lets a catalog grow mid-session and still be describable.

The cost is that the tool surface cannot enumerate the catalog. Which decides
the design.

## The tool surface

**Six tools, fixed for the session.** Their `parameters` schemas come from
`dyncomp/jsonschema`, the same projection the human layer's forms come from.

| tool | takes | gives back |
|---|---|---|
| `ui_search_components` | `query`, `limit?` | refs with one-line summaries |
| `ui_describe_component` | `ref` | descriptor, JSON Schema, events, named inits |
| `ui_create_surface` | `surfaceId`, `root?` | the empty surface |
| `ui_apply` | `surfaceId`, `ops[]` | per-op result, errors as JSON Pointers |
| `ui_read` | `surfaceId`, `pointer?` | the surface tree and data model, or a subtree |
| `ui_act` | `surfaceId`, `nodeId`, `name`, `args` | the resulting state |

`ui_apply` carries the patch algebra from `dyncomp/surface` — `AddNode`,
`RemoveNode`, `MoveNode`, `SetProps`, `BindInstance`, `SetData`. It is the one
tool that changes anything, and a batch is atomic.

`ui_act` is the one worth arguing for. It lets the model **drive what it built,
as a user would** — click the button, type in the field, and read back what
happened. Without it a model can only assert that its UI works; with it, it can
check. That is the difference between generating markup and building something.

### Why not one tool per component

It is the obvious design and it is wrong here for a specific reason: the catalog
is runtime-mutable. N components means N tool definitions re-sent every turn,
and every bundle load would have to re-declare the tool set mid-session. Search
plus describe keeps the surface constant at six regardless of how large the
catalog grows.

Two alternatives stay on the table rather than being ruled out:

- **Pinned per-component tools for a focused subset.** When a session is working
  with three specific components, a generated tool per component genuinely does
  give better per-call reliability. This composes with the above rather than
  replacing it: pin a few, search for the rest.
- **HTTP-ish routes instead of tools.** `GET /components?q=`,
  `POST /surfaces/{id}/nodes`, `PATCH /surfaces/{id}/data`. The patch algebra
  maps onto it almost exactly, so it is a later adapter over the same core, not
  a rewrite — which is the point of putting the algebra in `dyncomp/surface`
  rather than in the tool definitions. Whether models handle it better than
  tools is an open question worth answering with a measurement.

## The event stream

AG-UI's taxonomy, because it is transport-agnostic and already the thing
frameworks emit.

Outbound, as the model works:

- `TOOL_CALL_START` / `ARGS` / `END` / `RESULT` around each of the six.
- `STATE_SNAPSHOT` on session start and after a bundle load, since a new bundle
  changes what is possible rather than what is true.
- `STATE_DELTA` as RFC 6902 patches over the surface tree and the data model —
  computed from a `Value` diff over the schema projection, which is a thing the
  core already does for change detection.
- `CUSTOM` for surface patches a client may want to render specially.

Inbound, when a person touches what the model built: a component's
`control.emit` bubbles to the surface root and becomes an agent event in A2UI's
`action` shape, which is the right one because it is already a hand-picked view
rather than the whole state:

```json
{
  "name": "submit_booking",
  "surfaceId": "booking",
  "sourceComponentId": "submit-btn",
  "context": { "partySize": 4, "reservationTime": "7:00 PM" }
}
```

And for approval flows, AG-UI's interrupt contract: the run finishes with
`outcome.type: "interrupt"` carrying a `responseSchema`, and resumes with a
`resume` array keyed by `interruptId`. A component that needs a decision does
not block; it ends a run and waits, which is the only shape that survives a
model that may not come back.

## What the model is told about a component

This is where v0.3 of the contract earns itself. `ui_describe_component` returns:

- **What it is** — `doc`, `keywords`, `category`. A catalog of bare names is one
  nobody can choose from, person or model.
- **What it holds** — the declared fields as JSON Schema, with each field's own
  `doc` and its `constraint` (`min` / `max` / `pattern` / `format` / `enum` /
  `default`). The type says a field holds a string; the constraint says it holds
  an email under 254 characters. A model needs the second half as much as a form
  does.
- **What it does** — the message buckets, each with a sentence from the
  `message-docs` table.
- **How to start it** — the named `inits`, each with a `doc` saying when to
  prefer it over the bare constructor.

None of this is guest code. A component declares its shape once, and the schema
gives the host the JSON projection, structural equality, the generated mutators,
the inspector's form, *and* this description — which is the same argument the
contract already makes for everything else.

## What the model is not told

Nothing about the state's values, unless it reads them. `get-field` is lazy and
per-name; `ui_read` projects through the declared schema. A component's internals
stay inside it, and a model — like the host — sees the shape and asks for what
it needs.

## Open questions

- **Does the pinned-subset hybrid actually help?** Worth measuring against the
  pure six-tool surface before building it.
- **Do models handle HTTP-ish routes better than tools?** The second line of
  `NOTES.md`, and the reason the patch algebra lives where it does.
- **Is a hypermedia representation viable as the transcript?** The first line of
  `NOTES.md`. If a surface is already a tree of described components with a data
  model, the transcript could be the surface's history rather than a parallel
  record of it.
- **Multi-surface isolation.** A2UI's orchestrator has to strip other surfaces'
  data before routing to a sub-agent, and warns that failing to is how one
  agent's surface scrapes another's. If several models ever share a page here,
  the same rule applies, and the `surfaceId` in every op is what it hangs on.
