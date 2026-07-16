# Tutuca — Request / Response & Orchestration

The three event-driven orchestration channels beyond local `input`
handlers: `bubble` (events up the tree), `send` / `receive` (messages
to a target path), and async `request` / `response` (scope-registered
async work routed back into component state). Read this file when
wiring `bubble` / `receive` / `response` handlers, calling
`ctx.bubble` / `ctx.send` / `ctx.request`, or registering `RequestFn`
handlers. General authoring lives in [core.md](./core.md); testing these
handlers is in [testing.md](./testing.md).

## The four channels

Each channel pairs a trigger with a same-shape handler block:

| Triggered by                                | Handler block   |
| ------------------------------------------- | --------------- |
| DOM event (`click`, `input`, …)             | `input={ ... }` |
| `ctx.bubble(name, args)` — event up the tree | `bubble={ ... }` |
| `ctx.send(name, args)` — message to a target path | `receive={ ... }` |
| `ctx.request(name, args, opts)` — async request | `response={ ... }` |

Every handler in these blocks is an `InstanceHandler`:

```moonbit
(inst : Instance, args : Array[@tutuca.Value], ctx : &@tutuca.Ctx) -> Instance?
```

Return `Some(new_inst)` to swap the new value into the dispatch path, or
`None` for "no change" (a cheap no-op). `ctx` implements the
`@tutuca.Ctx` trait and exposes `ctx.send`, `ctx.bubble`, `ctx.request`,
`ctx.at()` (a `PathChanges` builder), `ctx.send_at_path` /
`ctx.bubble_at_path`, `ctx.name()` (the dispatched name),
`ctx.target_path()`, `ctx.walk_path(...)`, and — inside bubble handlers —
`ctx.stop_propagation()`.

`alter` is a fifth handler block, but it isn't event-triggered — the
renderer invokes alter handlers to produce binds, not to update state.
See *Mental model* in [core.md](./core.md) and *Scope Enrichment* in
[iteration.md](./iteration.md).

## Bubble Events

```moonbit
input={
  "onClick": (inst, _args, ctx) => {
    ctx.bubble("treeItemSelected", [inst.get("label")])
    None // no local change
  },
},
bubble={
  "treeItemSelected": (inst, args, _ctx) => { // ctx.stop_propagation() to halt
    match args {
      [Str(label), ..] => {
        let log = match inst.get("log") {
          List(a) => a.copy()
          _ => []
        }
        log.insert(0, Str("selected \{label}"))
        Some(inst.set("log", List(log)))
      }
      _ => None
    }
  },
},
```

`ctx.bubble("name", args)` emits an event that walks the dispatch path
back toward the root. Each ancestor whose component defines
`bubble.<name>` runs it (others are skipped silently);
bubbling stops at the root or when a handler calls
`ctx.stop_propagation()`. Ancestors see the event *after* descendants
have transacted, so bubble handlers are the place for aggregate state
(logs, selections, totals).

When to bubble: handle the event locally if the current component owns
the state needed to respond. Bubble when the action belongs to an
ancestor (a list item's "remove" must reach the list that owns the
items), or when an ancestor may want to react to or record something
that happened (selection, logging, analytics). Don't bubble events
with no consumer — and don't bubble merely so an ancestor can *read* a
child's state: the ancestor already holds the child as a field and can
read it directly in its own handler (`inst.get("items")` →
`obj_field`). Bubble when the ancestor must **act on** or **record**
the event, not to learn state it already owns.

## Send / Receive

`ctx.send(name, args)` delivers a message to a specific target
component (addressed by path; on its own `ctx.send` targets the current
instance). The target's `receive.<name>` handler runs. There is
**no built-in lifecycle** — `receive.init` is just a convention; the
host must dispatch it (typically after mounting) for it to run.

```moonbit
receive={
  "init": (inst, _args, ctx) => {
    ctx.request("loadData", [], @tutuca.RequestOpts::new())
    Some(inst.set("isLoading", Bool(true)))
  },
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
path before `.send(...)` / `.bubble(...)` fires; the handler runs on the
addressed child instance. (The lower-level twin is
`ctx.send_at_path(path, name, args)` with a `DispatchPath` built by
hand, e.g. `ctx.path().concat([FieldStep("x")])`.) Paths are positional,
not references — see *Positional delivery* below and *Mental model* in
[core.md](./core.md) for why this matters across async boundaries.

When to send: bubble emits an *event* that any ancestor with a
matching handler can observe; send delivers a *message* to one
specific target (or to self). Reach for `ctx.at()…send("name", [])` when
one component needs to address another by path — e.g. a form telling
its email field to focus after a failed submit
(`ctx.at().field("email").send("focus", [])`), or a list telling item 3
to enter edit mode (`ctx.at().index("items", 3).send("startEditing", [])`).
Reach for `ctx.send("name", [])` on self to reuse a handler from multiple
call sites without duplicating its body — e.g. a "Reload" button and
`receive.init` both calling `ctx.send("loadData", [])`. Don't `send` to
self when a direct function call in the same handler would do.

## Integrating with the outside world

A tutuca app talks to the outside world in two directions, and both go
through handlers — never around them.

- **Outbound** — the app reaches out (fetch, timers, storage, external
  APIs). Use `ctx.request("name", args, opts)`; the scope-registered
  `RequestFn` does the async work and the result lands back in component
  state via `response.<name>`. See *Async Requests* below.
- **Inbound** — the outside world pushes an event in (a WebSocket message,
  a DOM event fired outside the app, a `postMessage`, a timer, a
  third-party callback). Use `app.send_at_root("name", args=[...])` from
  the host / glue code. It dispatches a `send` to the **root component**,
  running its `receive.<name>` handler under the same immutable
  return-a-new-self contract as every other handler.

```moonbit
// host / glue code, outside the component tree (e.g. inside a JS-FFI callback)
app.send_at_root("serverPushed", args=[@tutuca.Value::from_json(payload)])
```

```moonbit
// root component
receive={
  "serverPushed": (inst, args, _ctx) => {
    match args {
      [msg, ..] => Some(prepend_event(inst, msg))
      _ => None
    }
  },
},
```

This keeps the root component the single owner of how external inbound
events mutate state — the logic lives in one `receive` block, in the same
place and shape as the rest of the app's handlers, and is testable like
any other (the harness exposes `h.send_at_root(...)` — see
[testing.md](./testing.md)).

⚠️ **Do not** reach into the transactor / app internals and overwrite the
root value to inject external data. That bypasses the component handler
model, the immutable return-a-new-self discipline, scope enrichment, and
the transactor's batching — state mutated that way is invisible to the
components that own it and easily clobbered by the next transaction.
Route every inbound event through `app.send_at_root` instead.

`send_at_root` only targets the root. To land an inbound event
on nested state, let the root's `receive` handler forward it with
`ctx.at().field(...).send(...)` (see *Send / Receive* above) — one entry
point, still reaching deep. For async/external delivery, anchor on stable
map keys rather than list indices (see *Positional delivery across async*
below).

## Async Requests

`ctx.request("name", args, opts)` triggers a scope-registered handler
and routes the result back to the issuing component's
`response.<name>`. Use it for fetch / timer / storage work that should
land back in component state.

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
receive={
  "init": (inst, _args, ctx) => {
    ctx.request("loadData", [], @tutuca.RequestOpts::new())
    Some(inst.set("isLoading", Bool(true)))
  },
},
response={
  // the default response handler gets BOTH the result and the error:
  // args = [res, err]
  "loadData": (inst, args, _ctx) => {
    match args {
      [res, _err] => Some(inst.set("isLoading", Bool(false)).set("items", res))
      _ => None
    }
  },
},
```

Because the request handler is registered **outside** the component, the
same component can be driven by a real fetch in production and by a
fixture in a test — parameterize the module function with
`requests? : Map[String, RequestFn] = real_handlers()` and pass a fixture
map when testing (the pattern in `examples/request.mbt`).

### The `err` argument and the error path

The default handler receives `args = [res, err]`. On success the
handler's `Ok` value is `res` and `err` is `Null`; on failure `res` is
`Null` and `err` is the `Err` value. Branch on `err` when failure needs
different state:

```moonbit
"loadData": (inst, args, _ctx) => {
  match args {
    [_res, Str(e)] =>
      Some(inst.set("isLoading", Bool(false)).set("error", Str(e)))
    [res, _] =>
      Some(inst.set("isLoading", Bool(false)).set("items", res))
    _ => None
  }
},
```

A **request name that isn't registered** doesn't crash — the runtime
routes `Err(Str("Request not found: <name>"))` to the same error path,
so it arrives as `err`. A `ctx.request("name", ...)` call with a typo
surfaces only at runtime as an `err`.

### Per-call handler-name overrides — and their signature

`@tutuca.RequestOpts` overrides which `response` handler runs, with
three name keys:

- `on_res_name` — base name for **both** outcomes (replaces `<name>`);
  the handler still gets `args = [res, err]`.
- `on_ok_name` — name for the **success** path only.
- `on_error_name` — name for the **error** path only.

⚠️ When `on_ok_name` / `on_error_name` is used, the split handler
receives a **single** payload arg — *not* `[res, err]`:

```moonbit
input={
  "loadAnotherWay": (inst, _args, ctx) => {
    ctx.request(
      "loadData",
      [],
      @tutuca.RequestOpts::new(
        on_ok_name="loadDataOk",
        on_error_name="loadDataErr",
      ),
    )
    Some(inst.set("isLoading", Bool(true)))
  },
},
response={
  "loadDataOk": (inst, args, _ctx) => {   // args = [res]
    match args {
      [res, ..] => Some(inst.set("isLoading", Bool(false)).set("items", res))
      _ => None
    }
  },
  "loadDataErr": (inst, args, _ctx) => {  // args = [err]
    let msg = match args {
      [Str(e), ..] => e
      _ => "request failed"
    }
    Some(inst.set("isLoading", Bool(false)).set("error", Str(msg)))
  },
},
```

The combined `[res, err]` shape is only for the default /
`on_res_name` case. Mixing them up — a split handler matching
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

A request whose result you don't need can omit the `response` handler
entirely — when no `response.<name>` (and no `$unknown`) matches, the
result is silently dropped. Idiomatic for side-effect-only work like
persisting state:

```moonbit
input={
  "onApplyFilter": (inst, args, ctx) => {
    match args {
      [value, ..] => {
        ctx.request(
          "persistState",
          [Map({ "key": Str("sectionFilter"), "value": value })],
          @tutuca.RequestOpts::new(),
        )
        Some(inst.set("filter", value))
      }
      _ => None
    }
  },
},
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
component handlers exposes `ctx.walk_path(callback)`, which walks the
component instances on the issuing path **leaf→root**, calling
`callback(component_id, instance_value)` (return `false` to stop early).
It captures the immutable dispatch root/path at call time.

### Chaining from a response handler

A `response` handler gets the full `ctx`, so it can issue further
`ctx.request` (request → response → request chains), `ctx.send`, or
`ctx.bubble`:

```moonbit
response={
  "loadUser": (inst, args, ctx) => {
    match args {
      [Map(user), Null] => {
        ctx.request(
          "loadUserDetails",
          [user.get("id").unwrap_or(Null)],
          @tutuca.RequestOpts::new(),
        )
        Some(inst.set("user", Map(user)))
      }
      _ => None
    }
  },
  "loadUserDetails": (inst, args, _ctx) => {
    match args {
      [details, _err] => Some(inst.set("userDetails", details))
      _ => None
    }
  },
},
```

## `$unknown` fallback

`receive` / `bubble` / `response` all share one fallback: when no
handler matches the dispatched name, the runtime looks for a handler
registered under the literal name `"$unknown"` in the same block and
runs that instead; `ctx.name()` tells it which name was dispatched.
Absent both the named handler and `$unknown`, the message is silently
dropped (the value passes through unchanged). Use `$unknown` for a
single catch-all (logging, a generic router); rely on the silent drop
for fire-and-forget requests.

```moonbit
receive={
  "$unknown": (inst, _args, ctx) => {
    let name = ctx.name().unwrap_or("?")
    Some(inst.set("lastUnhandled", Str(name)))
  },
},
```

## Positional delivery across async

The path a response (or `send` / `bubble`) is delivered to is
**positional** — an array of steps from the root, not a captured
reference. This is why an async response survives intervening
transactions that rebuilt the root (see *Mental model* in
[core.md](./core.md)). Practical rule: anchor on map keys, not list
indices, when an async result must reach a specific item — the
per-step-kind pinning rules are in [semantics.md](./semantics.md).

## See also

- [core.md](./core.md) — the core mental model, `view` directives, handler
  blocks overview, and *The ModuleDef convention*.
- [semantics.md](./semantics.md) — the path/transaction model behind these
  channels: path steps, the transaction lifecycle, teleporting, and the
  key-pinning rules `live_path` toggles.
- [testing.md](./testing.md) — driving `receive` / `response` flows from
  tests via the harness.
- [cli.md](./cli.md) — linter rules, exit codes, and `render` flags.
