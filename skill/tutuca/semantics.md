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

Dispatch additionally keeps the steps in a `DispatchPath`, a stack of render
continuations. Each frame is `{ base: Path, items: Array[DispatchStep] }`; a
`DispatchStep` is `Plain(step~, origin~)`. The first frame starts at the app
root. Rendering a value located elsewhere pushes a frame whose `base` is that
value's absolute app-root-relative path.

`SeqAccessStep` is the important one for async correctness: it stores the
field *names* `seq_field` and `key_field`, and resolves the key from the
live data each time it runs — see *Key resolution & async races* below.

### Two derived paths

The reconstructed path is transformed two ways depending on use:

- **`DispatchPath::compact()` → the dispatch path.** Drops frame-only
  steps independently in every frame and keeps the continuation stack.
  `pop_step()` walks the active frame upward; at its top it pops the frame and
  resumes the saved visual caller. Used
  to drive `ctx.send` and the `Dyn` leg of an intent walk, and to locate
  handlers.
- **`DispatchPath::to_transaction_path()` → the transaction path.**
  Reads only the active frame: its absolute `base` plus its items. That is the
  value the current handler owns, regardless of where it was visually
  rendered. Used by `Path::lookup` / `Path::set_value` to read and write state.

## Reconstructing a path from the DOM

The DOM is the only thing that survives between render and click, so the
renderer leaves breadcrumbs: `data-cid` / `data-nid` / `data-eid` on
elements, and `§…§` comment "metas" adjacent to component boundaries,
iteration entries, and scope boundaries (loop-less `@enrich-with`, so
their custom binds can be replayed). A resumed component boundary also stores
its absolute base (and repeats it as `data-rp` on fragment-root siblings). On an event, the render package's
event-path reconstruction walks from the target up to the root, reads
the breadcrumbs, and rebuilds the path (`render/build_stack.mbt` mirrors
the exact frames the renderer pushed). Along the way it resolves the
handler: normally on the **leaf** component, but an intent walking its
`Dyn` leg resolves on an **ancestor**, in which case the descending
steps below that ancestor are dropped so the path resolves to the
ancestor's value.

## The transaction lifecycle

Each dispatch is a `@transactor.Transaction`. The `Transactor` holds a
FIFO queue; the app layer drains it in batches
(`App::drain_batched(max_per_batch~, cb)` on the browser glue's
scheduler; `Transactor::settle(max_turns~)` drains synchronously in
headless tests), so transactions complete **asynchronously and
interleaved** — which is exactly why an intent's answer can land after
other transactions have rebuilt the root.

The core of applying one is `Path::update(root, bucket, name, args)`:

1. compute the transaction path (`to_transaction_path()`, or a pinned
   path for an answer);
2. `lookup` the addressed leaf value **now**;
3. find the handler on it — **one** lookup, by exact name, with no fallback
   sentinel behind it — and call it: old self in, new self out;
4. if the result differs, `set_value` rebuilds the root spine; otherwise
   the root is returned unchanged.

The root swap is atomic and structure-sharing: unchanged subtrees keep
their values. Per-dispatch completion is tracked by
`@transactor.Completion` (counter-based): `on_settled` fires once a
transaction's own work finishes, `on_subtree_settled` once the subtree
it spawned (intent walks, follow-on sends) settles too.

## Dispatch channels, semantically

The authoring API (`ctx.send` / `ctx.intent` / `ctx.forward`, the
`update` dispatch arms) is in
[messages-and-intents.md](./messages-and-intents.md). Underneath, each
maps to a transactor push:

| Channel                          | Push          | Notes                                              |
| -------------------------------- | ------------- | -------------------------------------------------- |
| DOM event → `Receive` arm        | `push_send`   | queued, then drained by the same `settle()` before the handler returns |
| `ctx.send` → `Receive` arm       | `push_send`   | queued; `skip_self` runs no self-handler           |
| `ctx.intent` → `Intent` arms     | `push_intent` | returns an `IntentWalk`; each hop is its own queued transaction |

`push_intent` creates the walk and queues its first hop. The `Dyn` leg is
just walking up the dispatch path one `pop_step` at a time, starting at
the sender's **parent**; the `Lex` leg queues each registered `IntentFn`
in turn and waits for its `answer` callback. A hop that replies ends the
walk and the answer is dispatched back at the originator's path as an
ordinary `Receive`; a walk whose route runs out dispatches
`<name>Unhandled` there instead. `target_path` (the originator's path)
stays fixed as `path` shortens, which is how the answer finds its way
home, and is also what an intent handler can address directly with
`ctx.send_at_path(ctx.target_path(), name, args)`.

Walks are bounded by `@transactor.INTENT_DEPTH` hops; past it the transactor
refuses with `RefusalCode::IntentDepth` rather than looping.

## Rendering with a resumed path

A provider evaluates both halves of a lowercase binding: its value and the
absolute path of that value. The pair is pushed into the dynamic render stack
under the provided name. A descendant `<x render="*sel">` retrieves the nearest
pair and renders the value after pushing its path as a continuation frame.
There is no producer search, producer id, interior list, portal, or teleport
rewrite during event reconstruction.

This gives the two behaviors the feature needs directly:

- mutation uses the active frame, so an event inside the resumed component
  updates the provider's data;
- bubbling reaches the top of that frame and pops directly back to the visual
  caller, then continues through the caller's ancestry.

Nested providers of one lowercase name are therefore valid: ordinary render
stack shadowing makes the nearest one win. An uppercase provide still publishes
a component type and is not a render target because it carries no value path.

When the located path is a seq-access (`.sheets[.selId]`), the frame base
contains a `SeqAccessStep` — which is where async key races come from.

A provider inside an `@each` publishes the ITEM's address: the loop re-binds
`it` to the item whether or not the body is a component, so a `.rows` iterated
at `key` contributes `rows[key]` to the render position, and everything
published below it is located under that.

The path half can be **absent**. A provider whose own render position cannot be
written down as an address — a constant `lookup` default, or a sequence that is
not a plain field — publishes the value with no path. `*name` still READS it;
`<x render="*name">` renders it in place and enters no continuation frame, so
an event inside it belongs to the enclosing component rather than to a guessed
address. This is deliberate: the empty path names the ROOT, so publishing an
address that does not resolve back to the value being rendered would silently
resume the whole app there and drop every edit made inside.

## Name lookup — two environments, one route

Type lookup, `provide`/`lookup` and intent routing ask ONE question: what does
this name mean, and where do I look for it. They share two environments and one
route vocabulary.

| leg   | environment                                                        |
|-------|--------------------------------------------------------------------|
| `dyn` | the render ancestry — `RenderStack.dyn_binds`, keyed by plain NAME  |
| `lex` | the registration scope chain — component types and app-root-relative value paths |

`ctx.lookup(name, opts)` and `ctx.make(name, args, opts)` take `opts.route`
with the same legs, the same array-is-walk-order contract and the same default
(`@tutuca.default_route()`, `dyn lex`) as `ctx.intent`. `@tutuca.route_lookup`
is the one walk all of them share: legs in the order written, first non-`None`
wins, legs evaluated lazily, and an empty route answering nothing rather than
falling back to the default.

The `lex` leg needs no render-stack search — it is the registration scope of
the component whose handler is running. Lowercase entries are absolute paths
looked up against the current app root; uppercase entries are component types.
The
`dyn` leg REBUILDS one from the ctx (`@app.ScopeNames`), because the stack that
evaluated a handler's arguments is a local in the dispatch pipeline and is gone
once the body runs, and a `send` or an `intent` transaction never built one.
The rebuilt path is compacted, so per-item bindings (`@each`,
`@enrich-with`) are not replayed: a `provide` whose expression reads a loop
binding is the one case this cannot reproduce.

An UPPERCASE name is a component type and a lowercase one is a value, so the
two keyspaces cannot collide and one binding frame carries both — the frame
holds values in `binds` and published component ids in `types`, and
nearest-ancestor-wins falls out of frame order for each. Types are not in the
value language at all: `KType` is in no grammar group, so a handler argument or
a macro attribute cannot be one.

`send` stays ADDRESSED — it walks nothing. It gains `ctx.send_reply(name,
args)`, which answers whoever sent the message being handled, at the position
they sent from, pinned at dispatch. `NO_SENDER` when nobody is waiting.

## Key resolution & async races

A `SeqAccessStep` resolves `key_field` from the live root **every time it
runs**. For synchronous dispatch this is invisible — the key cannot change
mid-transaction. For an async intent walk it is the whole problem:
between raising the intent and applying its answer, the key may move
(e.g. the user switches the selected tab, so `.selId` changes), and a
naive re-resolution would deliver the answer to **whatever item is
selected now**, not the one that raised the intent.

**Key pinning is the default.** `push_intent` snapshots the resolved key
at dispatch time by running `Path::pin_keys(cur_root)` over the
transaction path — each `SeqAccessStep(seq_field, key_field)` becomes a
literal `SeqStep(field, resolved_key)`. The pinned path is stored on the
walk, so the answer updates the item that raised the intent regardless of
later key changes. Pinning runs on the active transaction path, so a
`SeqAccessStep` in a resumed frame base is pinned too.

**Opt out per intent with `live_path=true`:**

```moonbit nocheck
// nocheck: a fragment (a match arm or an expression), not a top-level item
ctx.intent("save", [payload], @tutuca.IntentOpts::new(live_path=true))
```

With `live_path`, the answer re-evaluates the key at apply time — the
"follow the latest selection" behavior. Use it only when the answer is
*meant* to follow wherever the key now points.

Edge cases:

- **Pinned target deleted before the answer arrives** — the pinned
  `SeqStep` resolves to nothing, the handler runs against a null leaf, and
  the result equals the input → a safe no-op (root unchanged). With
  `live_path` it would instead hit the current item.
- **The ctx path stays live (un-pinned).** An answer handler
  that itself re-dispatches via `ctx.send` / `ctx.intent` re-resolves
  against current state — pinning covers the *update*, not nested
  re-dispatch.

## What "positional delivery" guarantees

Because a path is a position, an async answer survives intervening
transactions that rebuild the root — but "the right slot" means different
things per step kind:

- **`SeqAccessStep` (`.seq[.key]`)** — the key is **pinned by default**, so
  the answer reaches the entry that raised the intent even if the key
  field moved. Opt out with `live_path=true`.
- **`SeqStep` with a list index (`.items[3]`)** — the index is literal and
  **not** pinned to identity: if the list re-sorted or an item was inserted
  ahead of it, index 3 is now a different item and the answer lands
  there. Anchor on **map keys**, not list indices, when an async result
  must reach a specific item.
- **`FieldStep`** — a named field is stable; no ambiguity.

## See also

- [core.md](./core.md) — *Mental model* and *Paths, not references* (the
  high-level invariants this file expands on), `view` directives, the
  `update`/`compute` buckets.
- [messages-and-intents.md](./messages-and-intents.md) — the dispatch **API**:
  `send`-`Receive`, `intent` and its `dyn` / `lex` route, the three
  answers, `ctx.at()`, catch-all arms, `IntentFn` registration, and the
  `live_path` option.
- [advanced.md](./advanced.md) — dynamic bindings (`*x`) and resumed render
  paths from provider or lexical scope.
