# Tutuca — Runtime Semantics (paths · transactions · dispatch)

How a click becomes a state mutation, and what survives across async.
Read this when reasoning about **why** a handler ran where it did,
debugging a dispatch or async-timing bug, or changing the path layer
(`path_*.mbt` in the root package) / the `transactor` package. Not
needed for ordinary component authoring — for that start at
[core.md](./core.md).

The step and transaction names below are the ones in the source; confirm
behavior against the root package's `path_*.mbt` and `transactor/`
(their `pkg.generated.mbti` files list the exact API) rather than
trusting this doc when they disagree.

## State & identity (in one paragraph)

The application is a single immutable root value; the view is a pure
function of it; every handler takes the old state and returns a new state,
and the transactor swaps the root atomically. Updating a deep child
produces a new root that shares structure with the old one along the
unchanged spine, so untouched subtrees keep their old values. Full
version: *Mental model* in [core.md](./core.md).

## Paths are positional addresses

A `@tutuca.Path` is an array of `Step`s from the root to the value a
handler runs against — a **position**, not a captured reference (see
*Paths, not references* in [core.md](./core.md)). The step kinds:

| Step                | Addresses                          | Source syntax            |
| ------------------- | ---------------------------------- | ------------------------ |
| `FieldStep`         | a named field                      | `.field`                 |
| `SeqStep(field~, key~)` | a sequence entry by **literal** key/index | `.items[2]`      |
| `SeqAccessStep(seq_field~, key_field~)` | a sequence entry whose key is **read from another field** | `.sheets[.selId]` |
| `EachRenderItStep(field~, key~)` | an iterated `render-it` item | `<x render-it>` per iter |
| `BindStep` / `ScopeBindStep` / `EachBindStep` | nothing — frame-only (carry scope binds, no addressing) | `@each`, `@enrich-with` |

Dispatch additionally wraps steps in a `DispatchPath` of
`DispatchStep`s: `Plain(step~, origin~)`, plus `Dyn` / `DynEach` — the
dynamic-var (`*x`) render-target **teleport markers** carrying the
producer id, its own steps, and the interior component ids to drop.

`SeqAccessStep` is the important one for async correctness: it stores the
field *names* `seq_field` and `key_field`, and resolves the key from the
live data each time it runs — see *Key resolution & async races* below.

### Two derived paths

The reconstructed path is transformed two ways depending on use:

- **`DispatchPath::compact()` → the dispatch path.** Drops frame-only
  steps, keeps one step per crossed component (including the `Dyn`
  markers). `pop_step()` over it bubbles through every component. Used
  to drive `ctx.send` / `ctx.bubble` and to locate handlers.
- **`DispatchPath::to_transaction_path()` → the transaction path.**
  Teleports every `Dyn` marker (drops the steps interior to its
  producer..consumer span and splices in the producer's own steps) so a
  mutation lands on the data's real location. A path with no `Dyn` is
  returned unchanged. Used by `Path::lookup` / `Path::set_value` to read
  and write state.

## Reconstructing a path from the DOM

The DOM is the only thing that survives between render and click, so the
renderer leaves breadcrumbs: `data-cid` / `data-nid` / `data-eid` on
elements, and `§…§` comment "metas" adjacent to component boundaries,
iteration entries, and scope boundaries (loop-less `@enrich-with`, so
their custom binds can be replayed). On an event, the render package's
event-path reconstruction walks from the target up to the root, reads
the breadcrumbs, and rebuilds the path (`render/build_stack.mbt` mirrors
the exact frames the renderer pushed). Along the way it resolves the
handler: normally on the **leaf** component, but for bubbling events
(and explicit `bubble`) it can resolve on an **ancestor**, in which case
the descending steps below that ancestor are dropped so the path
resolves to the ancestor's value.

## The transaction lifecycle

Each dispatch is a `@transactor.Transaction`. The `Transactor` holds a
FIFO queue; the app layer drains it in batches
(`App::drain_batched(max_per_batch~, cb)` on the browser glue's
scheduler; `Transactor::settle(max_turns~)` drains synchronously in
headless tests), so transactions complete **asynchronously and
interleaved** — which is exactly why a request's response can land after
other transactions have rebuilt the root.

The core of applying one is `Path::update(root, bucket, name, args)`:

1. compute the transaction path (`to_transaction_path()`, or a pinned
   path for a response);
2. `lookup` the addressed leaf value **now**;
3. find the handler on it (exact name, then the `$unknown` fallback),
   call it — old self in, new self out;
4. if the result differs, `set_value` rebuilds the root spine; otherwise
   the root is returned unchanged.

The root swap is atomic and structure-sharing: unchanged subtrees keep
their values. Per-dispatch completion is tracked by
`@transactor.Completion` (counter-based): `on_settled` fires once a
transaction's own work finishes, `on_subtree_settled` once the subtree
it spawned (requests, follow-on sends) settles too.

## Dispatch channels, semantically

The authoring API (`ctx.send` / `bubble` / `request`, the `update`
dispatch arms) is in [request-response.md](./request-response.md).
Underneath, each maps to a transactor push:

| Channel             | Push                | Notes                                            |
| ------------------- | ------------------- | ------------------------------------------------ |
| DOM event → `Input` arm | `push_input`    | transacted **synchronously**, not queued         |
| `ctx.send` → `Receive` arm | `push_send`  | queued; `skip_self` runs no self-handler         |
| `ctx.bubble` → `Bubble` arm | `push_send(bubbles=true)` | queued; re-pushes itself at `path.pop_step()` until it reaches the root or `stop_propagation` |
| `ctx.request` → `Response` arm | `push_request` | queued **after** the async work calls `respond` |

Bubbling is just walking up the dispatch path one `pop_step` at a time.
`target_path` (the originator's path) stays fixed as `path` shortens, so a
bubble handler can reply to the originator via
`ctx.send_at_path(ctx.target_path(), name, args)`.

## Dynamic-var teleporting

A component rendered through `<x render="*sel">` *physically lives* at the
producer that declared `provide={ "sel": … }`, not under the consumer that
wrote the render. The reconstructed dispatch path keeps every intermediate
component (so bubbling visits them), but `to_transaction_path()` teleports
the `Dyn` marker: it pops the steps tagged with the marker's `interior`
component ids and splices in the producer's own `steps`. The mutation
therefore lands on the producer's data, and the consumer's view of it
updates in lock-step. Authoring view: *Teleporting* in
[advanced.md](./advanced.md).

When the producer's `provide` value is a seq-access (`.sheets[.selId]`),
the teleported steps include a `SeqAccessStep` — which is where async key
races come from.

## Key resolution & async races

A `SeqAccessStep` resolves `key_field` from the live root **every time it
runs**. For synchronous dispatch this is invisible — the key cannot change
mid-transaction. For an async `request`/`response` it is the whole
problem: between issuing the request and applying the response, the key
may move (e.g. the user switches the selected tab, so `.selId` changes),
and a naive re-resolution would deliver the response to **whatever item is
selected now**, not the one that issued the request.

**Key pinning is the default.** `push_request` snapshots the resolved key
at request time by running `Path::pin_keys(cur_root)` over the transaction
path — each `SeqAccessStep(seq_field, key_field)` becomes a literal
`SeqStep(field, resolved_key)`. The pinned path is stored on the queued
response, so the response updates the item that issued the request
regardless of later key changes. (Pinning runs on the transaction path,
after teleporting, because the `SeqAccessStep` may have come from a
`Dyn` marker.)

**Opt out per request with `live_path=true`:**

```moonbit
ctx.request("save", [payload], @tutuca.RequestOpts::new(live_path=true))
```

With `live_path`, the response re-evaluates the key at apply time — the
"follow the latest selection" behavior. Use it only when the response is
*meant* to follow wherever the key now points.

Edge cases:

- **Pinned target deleted before the response arrives** — the pinned
  `SeqStep` resolves to nothing, the handler runs against a null leaf, and
  the result equals the input → a safe no-op (root unchanged). With
  `live_path` it would instead hit the current item.
- **The ctx path stays live (un-pinned).** A response handler
  that itself re-dispatches via `ctx.send` / `ctx.request` re-resolves
  against current state — pinning covers the *update*, not nested
  re-dispatch.

## What "positional delivery" guarantees

Because a path is a position, an async response survives intervening
transactions that rebuild the root — but "the right slot" means different
things per step kind:

- **`SeqAccessStep` (`.seq[.key]`)** — the key is **pinned by default**, so
  the response reaches the entry that issued the request even if the key
  field moved. Opt out with `live_path=true`.
- **`SeqStep` with a list index (`.items[3]`)** — the index is literal and
  **not** pinned to identity: if the list re-sorted or an item was inserted
  ahead of it, index 3 is now a different item and the response lands
  there. Anchor on **map keys**, not list indices, when an async result
  must reach a specific item.
- **`FieldStep`** — a named field is stable; no ambiguity.

## See also

- [core.md](./core.md) — *Mental model* and *Paths, not references* (the
  high-level invariants this file expands on), `view` directives, the
  `update`/`mutate`/`compute` buckets.
- [request-response.md](./request-response.md) — the dispatch **API**:
  `Bubble` / `send`-`Receive` / `request`-`Response`, `ctx.at()`,
  catch-all arms, request-handler registration, and the `live_path`
  request option.
- [advanced.md](./advanced.md) — dynamic bindings (`*x`) and the authoring
  view of teleporting.
