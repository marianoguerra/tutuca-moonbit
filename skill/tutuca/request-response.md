# Tutuca — Request / Response & Orchestration

The three event-driven orchestration channels beyond local `Input`
events: `Bubble` (events up the tree), `send` / `Receive` (messages
to a target path), and async `request` / `Response` (scope-registered
async work routed back into component state). Read this file when
writing `Receive` / `Bubble` / `Response` arms in an `update` fn,
calling `ctx.bubble` / `ctx.send` / `ctx.request`, or registering
`RequestFn` handlers. General authoring lives in [core.md](./core.md);
testing these handlers is in [testing.md](./testing.md).

## The four channels

Each channel maps a trigger to one arm of the **same `update` match**:

| Triggered by                                | `update` arm            |
| ------------------------------------------- | ----------------------- |
| DOM event (`click`, `input`, …)             | `Input(name, args)`     |
| `ctx.bubble(name, args)` — event up the tree | `Bubble(name, args)`   |
| `ctx.send(name, args)` — message to a target path | `Receive(name, args)` |
| `ctx.request(name, args, opts)` — async request | `Response(name, args)` |

The `update` fn folds them all into one TEA-style pattern match:

```moonbit
update=(s : MyState, msg : @component.Dispatch, ctx : &@tutuca.Ctx) => match msg {
  ...
  _ => None // ALWAYS needed
},
```

Return `Some(new_state)` to swap the new value into the dispatch path,
or `None` for "no change" (a cheap no-op). The payloads are
`(String, Array[@tutuca.Value])` — pattern-match the args array
directly: `Receive("flash", [Str(m), ..]) => ...`. `ctx` implements the
`@tutuca.Ctx` trait and exposes `ctx.send`, `ctx.bubble`, `ctx.request`,
`ctx.at()` (a `PathChanges` builder), `ctx.send_at_path` /
`ctx.bubble_at_path`, `ctx.name()` (the dispatched name),
`ctx.target_path()`, `ctx.walk_path(...)`, and — inside `Bubble` arms —
`ctx.stop_propagation()`.

The render buckets (`when` / `enrich` / `enrich_scope` / `loop_with`)
aren't event-triggered — the renderer invokes them to filter and produce
binds, not to update state. See *Mental model* in [core.md](./core.md)
and *Scope Enrichment* in [iteration.md](./iteration.md).

## Bubble Events

```moonbit
update=(s : LogState, msg, ctx) => match msg {
  Input("onClick", _) => {
    ctx.bubble("treeItemSelected", [Str(s.label)])
    None // no local change
  }
  // an ancestor's update sees the same event as a Bubble arm
  // (ctx.stop_propagation() to halt)
  Bubble("treeItemSelected", [Str(label), ..]) => {
    let log = s.log.copy()
    log.insert(0, Str("selected \{label}"))
    Some({ ..s, log, })
  }
  _ => None
},
```

`ctx.bubble("name", args)` emits an event that walks the dispatch path
back toward the root. Each ancestor whose `update` matches
`Bubble("name", …)` runs its arm (others fall through to `_ => None`
and are skipped silently); bubbling stops at the root or when a handler
calls `ctx.stop_propagation()`. Ancestors see the event *after*
descendants have transacted, so `Bubble` arms are the place for
aggregate state (logs, selections, totals).

When to bubble: handle the event locally if the current component owns
the state needed to respond. Bubble when the action belongs to an
ancestor (a list item's "remove" must reach the list that owns the
items), or when an ancestor may want to react to or record something
that happened (selection, logging, analytics). Don't bubble events
with no consumer — and don't bubble merely so an ancestor can *read* a
child's state: the ancestor already holds the child as a field and can
read it directly in its own handler (a `@tutuca.Value` field plus
`v.field("x")` / `obj_field`). Bubble when the ancestor must **act on**
or **record** the event, not to learn state it already owns.

## Send / Receive

`ctx.send(name, args)` delivers a message to a specific target
component (addressed by path; on its own `ctx.send` targets the current
instance). The target's `update` runs with `Receive(name, args)`. There
is **no built-in lifecycle** — `Receive("init", _)` is just a
convention; the host must dispatch it (typically after mounting) for it
to run.

```moonbit
update=(s : ListState, msg, ctx) => match msg {
  Receive("init", _) => {
    ctx.request("loadData", [], @tutuca.RequestOpts::new())
    Some({ ..s, isLoading: true })
  }
  _ => None
},
```

Dispatch from anywhere:

```moonbit
app.send_at_root("init")                             // host code, top-level
ctx.at().field("personalSite").send("init", [])      // child by field name
ctx.at().index("items", 3).send("init", [])          // list element at index 3
ctx.at().key("byKey", "k1").send("init", [])         // map entry by key
ctx.at().field("a").field("b").index("xs", 0).send("ping", []) // chain freely
ctx.send("name", [])                                 // self
ctx.bubble("name", [arg])                            // bubble up
```

`ctx.at()` returns a `@tutuca.PathChanges` builder with `.field(name)`,
`.index(name, i)`, and `.key(name, k)`. Each call appends a step to the
path before `.send(...)` / `.bubble(...)` fires; the target's `update`
runs on the addressed child instance. (The lower-level twin is
`ctx.send_at_path(path, name, args)` with a `DispatchPath` built by
hand, e.g. `ctx.path().concat([FieldStep("x")])`.) Paths are positional,
not references — see *Positional delivery* below and *Mental model* in
[core.md](./core.md) for why this matters across async boundaries.

When to send: bubble emits an *event* that any ancestor with a
matching arm can observe; send delivers a *message* to one
specific target (or to self). Reach for `ctx.at()…send("name", [])` when
one component needs to address another by path — e.g. a form telling
its email field to focus after a failed submit
(`ctx.at().field("email").send("focus", [])`), or a list telling item 3
to enter edit mode (`ctx.at().index("items", 3).send("startEditing", [])`).
Reach for `ctx.send("name", [])` on self to reuse a `Receive` arm from
multiple call sites without duplicating its body — e.g. a "Reload"
button and the `Receive("init", _)` arm both calling
`ctx.send("loadData", [])`. Don't `send` to self when a direct function
call in the same handler would do.

## Integrating with the outside world

A tutuca app talks to the outside world in two directions, and both go
through handlers — never around them.

- **Outbound** — the app reaches out (fetch, timers, storage, external
  APIs). Use `ctx.request("name", args, opts)`; the scope-registered
  `RequestFn` does the async work and the result lands back in component
  state via a `Response("name", …)` arm. See *Async Requests* below.
- **Inbound** — the outside world pushes an event in (a WebSocket message,
  a DOM event fired outside the app, a `postMessage`, a timer, a
  third-party callback). Use `app.send_at_root("name", args=[...])` from
  the host / glue code. It dispatches a `send` to the **root component**,
  running its `Receive("name", …)` arm under the same immutable
  return-a-new-state contract as every other handler.

```moonbit
// host / glue code, outside the component tree (e.g. inside a JS-FFI callback)
app.send_at_root("serverPushed", args=[@tutuca.Value::from_json(payload)])
```

```moonbit
// root component
update=(s : RootState, msg, _ctx) => match msg {
  Receive("serverPushed", [msg_val, ..]) => Some(prepend_event(s, msg_val))
  _ => None
},
```

This keeps the root component the single owner of how external inbound
events mutate state — the logic lives in one `Receive` arm, in the same
place and shape as the rest of the app's handlers, and is testable like
any other (the harness exposes `h.send_at_root(...)` — see
[testing.md](./testing.md)).

⚠️ **Do not** reach into the transactor / app internals and overwrite the
root value to inject external data. That bypasses the component handler
model, the immutable return-a-new-state discipline, scope enrichment, and
the transactor's batching — state mutated that way is invisible to the
components that own it and easily clobbered by the next transaction.
Route every inbound event through `app.send_at_root` instead.

`send_at_root` only targets the root. To land an inbound event
on nested state, let the root's `Receive` arm forward it with
`ctx.at().field(...).send(...)` (see *Send / Receive* above) — one entry
point, still reaching deep. For async/external delivery, anchor on stable
map keys rather than list indices (see *Positional delivery across async*
below).

## Async Requests

`ctx.request("name", args, opts)` triggers a scope-registered handler
and routes the result back to the issuing component's
`Response("name", …)` arm. Use it for fetch / timer / storage work that
should land back in component state.

Request handlers are **callback-style** `RequestFn` values — not
async/await:

```moonbit
pub(all) struct RequestFn(
  (Array[@tutuca.Value], (Result[@tutuca.Value, @tutuca.Value]) -> Unit) -> Unit
)
```

The handler calls `respond(Ok(v))` or `respond(Err(e))` whenever it is
done — immediately (a fixture), or from a real fetch's callback:

```moonbit
fn request_handlers() -> Map[String, @component.RequestFn] {
  {
    "loadData": @component.RequestFn((_args, respond) => {
      // a real handler would call respond from its network callback;
      // this fixture responds synchronously
      respond(Ok(List([Map({ "title": Str("Tutuca") })])))
    }),
  }
}
```

Register them on the `ModuleDef` (or directly with
`scope.register_request_handlers(...)`):

```moonbit
@component.ModuleDef::new(
  name="request-example",
  components=[...],
  requests=request_handlers(),
)
```

In a component:

```moonbit
update=(s : QuotesState, msg, ctx) => match msg {
  Receive("init", _) => {
    ctx.request("loadData", [], @tutuca.RequestOpts::new())
    Some({ ..s, isLoading: true })
  }
  // the default response arm gets BOTH the result and the error:
  // args = [res, err]
  Response("loadData", [res, _err]) =>
    Some({ ..s, isLoading: false, items: res.list() })
  _ => None
},
```

Because the request handler is registered **outside** the component, the
same component can be driven by a real fetch in production and by a
fixture in a test — parameterize the module function with
`requests? : Map[String, RequestFn] = real_handlers()` and pass a fixture
map when testing (the pattern in `examples/request.mbt`).

### The `err` argument and the error path

The default arm receives `args = [res, err]`. On success the
handler's `Ok` value is `res` and `err` is `Null`; on failure `res` is
`Null` and `err` is the `Err` value. Branch on `err` when failure needs
different state — put the error pattern first:

```moonbit
Response("loadData", [_res, Str(e)]) =>
  Some({ ..s, isLoading: false, error: e })
Response("loadData", [res, _]) =>
  Some({ ..s, isLoading: false, items: res.list() })
```

A **request name that isn't registered** doesn't crash — the runtime
routes `Err(Str("Request not found: <name>"))` to the same error path,
so it arrives as `err`. A `ctx.request("name", ...)` call with a typo
surfaces only at runtime as an `err`.

### Per-call handler-name overrides — and their signature

`@tutuca.RequestOpts` overrides which `Response` name is dispatched,
with three name keys:

- `on_res_name` — base name for **both** outcomes (replaces `<name>`);
  the arm still gets `args = [res, err]`.
- `on_ok_name` — name for the **success** path only.
- `on_error_name` — name for the **error** path only.

⚠️ When `on_ok_name` / `on_error_name` is used, the split arm
receives a **single** payload arg — *not* `[res, err]`:

```moonbit
update=(s : ItemsState, msg, ctx) => match msg {
  Input("loadAnotherWay", _) => {
    ctx.request(
      "loadData",
      [],
      @tutuca.RequestOpts::new(
        on_ok_name="loadDataOk",
        on_error_name="loadDataErr",
      ),
    )
    Some({ ..s, isLoading: true })
  }
  Response("loadDataOk", [res, ..]) =>   // args = [res]
    Some({ ..s, isLoading: false, items: res.list() })
  Response("loadDataErr", [err, ..]) => { // args = [err]
    let msg_txt = match err {
      Str(e) => e
      _ => "request failed"
    }
    Some({ ..s, isLoading: false, error: msg_txt })
  }
  _ => None
},
```

The combined `[res, err]` shape is only for the default /
`on_res_name` case. Mixing them up — a split arm matching
`[res, err]` — silently misreads the args, a common bug. (Worked
version of both routes: `examples/request.mbt`.)

### `live_path` — pinning vs following a moving key

The same opts value takes `live_path`. It controls where the response
lands when the request path addresses a seq-access entry
(`.sheets[.selId]`): by **default** the resolved key is *pinned* at
request time, so the response updates the item that issued the request
even if `.selId` moved while the request was in flight (e.g. the user
switched tabs). Set `live_path=true` to opt out and re-resolve the key
live, delivering to whatever the key now points at:

```moonbit
ctx.request("save", [payload], @tutuca.RequestOpts::new())            // pinned
ctx.request("refresh", [], @tutuca.RequestOpts::new(live_path=true))  // live
```

The pinning rules per step kind (and why list indices still slide) are
in [semantics.md](./semantics.md) (*Key resolution & async races*).

### Fire-and-forget requests

A request whose result you don't need can omit the `Response` arm
entirely — an unmatched dispatch falls to `_ => None` and the result is
silently dropped. Idiomatic for side-effect-only work like persisting
state:

```moonbit
Input("onApplyFilter", [value, ..]) => {
  ctx.request(
    "persistState",
    [Map({ "key": Str("sectionFilter"), "value": value })],
    @tutuca.RequestOpts::new(),
  )
  Some({ ..s, filter: value })
}
```

Fire several in one handler when needed (call `ctx.request` repeatedly
before returning).

### The request-handler contract

A `RequestFn` has no component instance — it can't read component state,
so pass everything it needs through `args`. It is a plain closure; build
aggregate maps from sub-modules by merging their `Map`s before
constructing the `ModuleDef`.

Request handlers are looked up through the registration scope
(`ComponentStack::lookup_request`), so handlers registered on a parent
scope are visible to components registered under it.

For observing the dispatch chain a request belongs to, the ctx passed to
`update` exposes `ctx.walk_path(callback)`, which walks the
component instances on the issuing path **leaf→root**, calling
`callback(component_id, instance_value)` (return `false` to stop early).
It captures the immutable dispatch root/path at call time.

### Chaining from a response arm

A `Response` arm gets the full `ctx`, so it can issue further
`ctx.request` (request → response → request chains), `ctx.send`, or
`ctx.bubble`:

```moonbit
update=(s : UserState, msg, ctx) => match msg {
  Response("loadUser", [Map(user), Null]) => {
    ctx.request(
      "loadUserDetails",
      [user.get("id").unwrap_or(Null)],
      @tutuca.RequestOpts::new(),
    )
    Some({ ..s, user: Map(user) })
  }
  Response("loadUserDetails", [details, _err]) =>
    Some({ ..s, userDetails: details })
  _ => None
},
```

## Catch-all arms

`update` is one pattern match, so the catch-all is just a wildcard
pattern: `Receive(name, args) => ...` (after the specific arms) catches
every message and binds the dispatched name directly — no separate
registration needed. The final `_ => None` is the silent drop: an
unmatched message passes the state through unchanged. Use a name-binding
wildcard arm for a single catch-all (logging, a generic router); rely on
`_ => None` for fire-and-forget requests.

```moonbit
update=(s : DebugState, msg, _ctx) => match msg {
  // specific arms first...
  Receive(name, _args) => Some({ ..s, lastUnhandled: name })
  _ => None
},
```

(At the value layer — custom `Obj` implementations, `for_type`
components — the runtime still probes a literal `"$unknown"` handler
name before dropping a dispatch; typed components never need it, the
wildcard arm is the same thing with the name statically bound.)

## Positional delivery across async

The path a response (or `send` / `bubble`) is delivered to is
**positional** — an array of steps from the root, not a captured
reference. This is why an async response survives intervening
transactions that rebuilt the root (see *Mental model* in
[core.md](./core.md)). Practical rule: anchor on map keys, not list
indices, when an async result must reach a specific item — the
per-step-kind pinning rules are in [semantics.md](./semantics.md).

## See also

- [core.md](./core.md) — the core mental model, `view` directives, the
  `update`/`mutate`/`compute` overview, and *The ModuleDef convention*.
- [semantics.md](./semantics.md) — the path/transaction model behind these
  channels: path steps, the transaction lifecycle, teleporting, and the
  key-pinning rules `live_path` toggles.
- [testing.md](./testing.md) — driving `Receive` / `Response` flows from
  tests via the harness.
- [cli.md](./cli.md) — linter rules, exit codes, and `render` flags.
