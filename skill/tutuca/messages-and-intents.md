# Tutuca — Messages & Intents

The two dispatch channels beyond a component's own `@on` handlers:
**messages** (`send` / `sendAt` → a `receive` handler on one addressed
component) and **intents** (`intent` → a walk along a *route* until
something answers). Read this file when writing `receive` / `intent`
handlers, calling `send` / `sendAt` / `intent` / `forward` / `reply` /
`fail` / `stop` from a script block or `ctx.*` from MoonBit, or
registering `IntentFn` handlers on a scope. General authoring lives in
[core.md](./core.md); testing these handlers is in
[testing.md](./testing.md).

## The two channels

Each trigger maps to one handler bucket — one block in the script, one
arm of the **same `update` match** in MoonBit:

| Triggered by                                          | script block        | `update` arm          |
| ----------------------------------------------------- | ------------------- | --------------------- |
| DOM event (`@on.click`, `@on.input`, …)               | `on <name>`         | `Input(name, args)`   |
| `send 'name' …` / `sendAt &.child 'name' …`           | `receive <name>`    | `Receive(name, args)` |
| `intent 'name' …` — walks a route                     | `intent <name>`     | `Intent(name, args)`  |

A **message** is addressed: it names one component and stops there. An
**intent** is routed: it names a *thing to be done* and walks until
something answers or the route runs out. That is the whole distinction —
the verb no longer decides which scope answers, the route does.

If you know tutuca v1, the mapping is:

| v1                              | v2                                   |
| ------------------------------- | ------------------------------------ |
| `ctx.bubble(name, args)`        | `intent dyn 'name'` — walk ancestors |
| `ctx.request(name, args, opts)` | `intent lex 'name'` — walk the scope |
| `ctx.send(name, args)`          | unchanged — `send` / `Receive`       |
| `Response(name, [res, err])`    | three named answers (see below)      |

`Bubble` and `Response` still exist as buckets during the migration, but
new code should not reach for them: everything they did is a route.

## Messages — `send`, `sendAt`, `receive`

`send 'name' args…` delivers a message to the **current** component;
`sendAt <place> 'name' args…` delivers it to an addressed one. The
target's `receive <name>` block runs. There is **no built-in lifecycle**
— `receive init` is just a convention; the host must dispatch it
(typically after mounting) for it to run.

```html
<script type="tutuca/state">
  state {
    text : String
    rows : Array[Any]
  }
  receive { Init, Flash(String) }
</script>

<script type="tutuca/script">
  /// A parent's `sendAt &.status 'flash' 'Saved'` lands here.
  receive flash(text) {
    .text = text
  }

  /// Reuse one body from several call sites without duplicating it.
  receive init {
    sendAt &.status 'flash' 'Ready'
  }
</script>
```

`&.status` is a **position**, not a value: `.rows[k]` is what is *there*,
`&.rows[k]` is *where*. The difference is what lets a late answer land on
the row that asked for it even after the list moved — see *Positional
delivery across async* below.

From MoonBit the same two calls are `ctx.send(name, args)` and the
`ctx.at()` builder:

```moonbit nocheck
// nocheck: a fragment (a match arm or an expression), not a top-level item
app.send_at_root("init") |> ignore                   // host code, top-level
ctx.at().field("personalSite").send("init", [])      // child by field name
ctx.at().index("items", 3).send("startEditing", [])  // list element by index
ctx.at().key("byKey", "k1").send("ping", [])         // map entry by key
ctx.at().field("a").field("b").index("xs", 0).send("ping", []) // chain freely
ctx.send("loadData", [])                             // self
```

`ctx.at()` returns a `@tutuca.PathChanges` builder with `.field(name)`,
`.index(name, i)` and `.key(name, k)`; each call appends a step before
`.send(...)` / `.intent(...)` fires. (The lower-level twin is
`ctx.send_at_path(path, name, args)` with a `DispatchPath` built by hand,
e.g. `ctx.path().concat([FieldStep("x")])`.)

**When to send.** Send when *one specific component* must be told
something: a form telling its email field to focus after a failed submit,
a list telling item 3 to enter edit mode, a "Reload" button reusing the
`receive loadData` body the `init` arm also calls. Don't `send` to self
when a direct expression in the same body would do — and don't send when
you don't know who should answer. That is what an intent is for.

## Intents — routes and legs

`intent 'name' args…` dispatches a request the sender does not address.
The runtime walks a **route** and offers the intent to each hop in turn;
the first hop that answers ends the walk.

A route is a list of **legs**, and there are two:

| Leg   | word  | what it walks                                                     |
| ----- | ----- | ----------------------------------------------------------------- |
| `Dyn` | `dyn` | the **dispatch path** — the sender's parent, then *its* parent, up to the root |
| `Lex` | `lex` | the **registration scope chain** — the `IntentFn`s registered on the module, then on scopes above it |

Written with no legs at all, an intent takes the default route
`dyn lex`: try the ancestors, then the registered handlers. That default
is written down in exactly one place (`@tutuca.IntentOpts::new`), so
"what does a bare `intent` do" has one answer and no second copy.

```html
<script type="tutuca/script">
  receive go {
    intent 'saveDraft' .name        // dyn lex — ancestors, then the scope
    intent dyn 'picked' .page       // ancestors only  (v1's `bubble`)
    intent lex 'loadRows'           // the scope only  (v1's `request`)
    intent lex dyn 'saveDraft' .name // legs run in the order written
  }
</script>
```

The `dyn` leg starts at the sender's **parent**, not at the sender: an
intent is never offered to the component that raised it. (A component
that wanted to handle it itself would just have written the body inline.)

Walks are depth-bounded — `@tutuca.INTENT_DEPTH` hops, after which the
runtime refuses with `RefusalCode::IntentDepth` rather than looping.

## Answering an intent

A component answers an intent with an `intent <name>` handler. Inside it:

- `reply <value>` — answer with a result. **Ends the walk.**
- `fail <value>` — answer with an error. **Ends the walk.**
- `forward` — hand the intent on to the next hop (see below).
- `stop` — end the walk **answering nothing**.
- ...or none of the above: the body runs, changes state, and the walk
  goes on. A handler that does not reply is an **observer**.

```html
<script type="tutuca/state">
  state { count : Int, page : Int }
  intent { SaveDraft(String), Picked(Int) }
</script>

<script type="tutuca/script">
  /// Answered where it arrives.
  intent saveDraft(text) {
    .count += 1
    reply .count
  }

  /// An observer: it records the intent and lets it keep walking.
  intent picked(k) {
    .page = k
  }
</script>
```

The one rule to hold on to: **a reply ends the walk; running does not.**
An observer and an answerer are the same construct with and without a
`reply`, which is why no separate "listener" bucket exists.

Two more consequences worth knowing:

- The one-shot is **per intent, across hops** — not per body. A body may
  queue two `reply`s; the transactor honours the first and refuses the
  second.
- A `requires` / `ensures` that does not hold takes the reply with it.
  The transition never happens, so the queued effects are dropped and the
  walk continues past that hop as if the handler had declined. An answer
  and a transition are all-or-nothing together.

## The three outcomes

An intent has exactly three ends, and each has its own name and its own
payload shape:

| outcome                     | dispatched name    | payload            |
| --------------------------- | ------------------ | ------------------ |
| a hop replied               | `<name>Ok`         | the replied value  |
| a hop failed                | `<name>Error`      | the error value    |
| the route ran out           | `<name>Unhandled`  | none               |

They arrive back at the sender as **ordinary messages, in the `receive`
bucket**. A handler cannot tell an answer from a message a parent sent,
and does not need to.

Declaring the three arms in the schema is what makes an intent a
*request* rather than a notification — a sender expects an answer if and
only if it declares one. Nobody writes that down twice: the generator
reads the schema's `receive` list and fills the intent's opts in.

```html
<script type="tutuca/state">
  state {
    items     : Array[Any]
    isLoading : Bool
    error     : Any
  }

  /// The three ANSWERS. Declaring them is what wires `loadData` up.
  receive {
    Init
    LoadDataOk(Any)
    LoadDataError(String)
    LoadDataUnhandled
  }
</script>

<script type="tutuca/script">
  /// `intent` is an EFFECT: it goes out only if the whole body finished. A
  /// message sent beside a transition that did not happen is the one outcome
  /// nobody can reason about afterwards.
  receive init {
    intent lex 'loadData'
    .isLoading = true
  }
</script>
```

`<name>Unhandled` is the outcome v1 had no word for. A v1 `RequestFn`
*had* to respond, so a handler with nothing to contribute could only
invent an error. "Nothing claimed it" and "a handler refused it" are
different sentences, and now they have different names.

The MoonBit arms, for a component that names its own three outcomes
rather than letting the schema fill them in:

```moonbit nocheck
// nocheck: a bucket argument, not a top-level item
update=(s : ItemsState, msg, ctx) => match msg {
  Receive("loadAnotherWay", _) => {
    ctx.intent(
      "loadData",
      [],
      @tutuca.IntentOpts::new(
        route=[Lex],
        on_ok_name="loadDataOk",
        on_error_name="loadDataError",
        on_unhandled_name="loadDataUnhandled",
      ),
    )
    Next({ ..s, isLoading: true })
  }
  // THREE outcomes, three arms, each with its own shape. v1's combined
  // `[res, err]` payload — and the split arm that read the wrong slot of
  // it — are both gone.
  Receive("loadDataOk", [res, ..]) =>
    Next({ ..s, isLoading: false, items: res.list() })
  Receive("loadDataError", [Str(e), ..]) =>
    Next({ ..s, isLoading: false, error: Str(e) })
  Receive("loadDataUnhandled", _) =>
    Next({ ..s, isLoading: false, error: Str("nothing answers `loadData`") })
  _ => Unhandled
},
```

`@tutuca.IntentOpts::new(route?, on_ok_name?, on_error_name?,
on_unhandled_name?, live_path?)` — every field optional, `route`
defaulting to `[Dyn, Lex]`. Omit the three names and the answers are
dispatched as `<name>Ok` / `<name>Error` / `<name>Unhandled`.

## `forward` — one operation, two sides

`forward` is the same word from both ends of a walk, and which one you
get depends on which bucket you are in:

- **In an `intent` body** it *amends the hop*: the walk goes on to the
  next hop, optionally with new arguments or a narrowed route.
- **In a `receive` body** it *starts a walk*: the message that arrived
  becomes an intent, keeping its name and payload.

```html
<script type="tutuca/script">
  /// A receive that turns a message into an intent — same name, same args.
  receive saveDraft(text) { forward }              // default route: dyn lex
  receive picked(k)       { forward dyn }          // ancestors only
  receive saveDraft(text) { forward lex }          // the scope only
  receive saveDraft(text) { forward lex dyn }      // legs in the order written

  /// Amend the arguments; the name and the route are kept.
  receive saveDraft(text) { forward .name }

  /// Run first, then hand it on.
  receive saveDraft(text) {
    .count += 1
    forward
  }

  /// The intent side: record it, then let the walk continue.
  intent picked(k) {
    .page = k
    forward
  }
</script>
```

From MoonBit: `ctx.forward(args?, opts?)` — pass `None` for either to
keep what arrived.

## Registering intent handlers — the `lex` leg

The `lex` leg walks handlers registered on the **scope**, not components.
They are `IntentFn` values — callback-style, not async/await:

```moonbit
pub(all) struct IntentFn(
  (@tutuca.IntentCall, (@tutuca.IntentAnswer) -> Unit) -> Unit
)
```

An `IntentCall` carries `name`, `args` and `from` (the dispatch path the
intent was raised at). The handler calls `answer(...)` whenever it is
done — immediately for a fixture, or from a real fetch's callback — with
one of three answers:

| answer            | meaning                                        |
| ----------------- | ---------------------------------------------- |
| `Ok(value)`       | answered; the sender hears `<name>Ok`          |
| `Failed(value)`   | failed; the sender hears `<name>Error`         |
| `Pass`            | **declines**; the walk goes on to the next hop |

`Pass` is the `IntentFn`'s half of "running is not answering". A `Pass`
from every handler on the route is what produces `<name>Unhandled`.

Handlers are registered as a **list per name**, because the leg walks: a
declining handler hands the intent to the next one, and the scope chain
can hold several for a name.

```moonbit
fn fixture_intent_handlers() -> Map[String, Array[@component.IntentFn]] {
  {
    "loadData": [
      IntentFn((_call, answer) => {
        // a real handler would call `answer` from its network callback;
        // this fixture answers synchronously
        answer(
          Ok(
            List([
              Map({
                "title": Str("Tutuca"),
                "description": Str("A SPA framework that fits in your head"),
              }),
            ]),
          ),
        )
      }),
    ],
  }
}

///|
/// A scope that DECLINES. v1's `RequestFn` had to respond, so this handler
/// could only have invented an error.
fn declining_intent_handlers() -> Map[String, Array[@component.IntentFn]] {
  { "loadData": [IntentFn((_call, answer) => answer(Pass))] }
}
```

Register them on the `ModuleDef` (or directly with
`scope.register_intent_handlers(...)`):

```moonbit nocheck
// nocheck: a fragment (a match arm or an expression), not a top-level item
@component.ModuleDef::new(
  name="request-example",
  components=[...],
  intents=fixture_intent_handlers(),
)
```

Because the handler is registered **outside** the component, the same
component can be driven by a real fetch in production and by a fixture in
a test — parameterize the module function with
`intents? : Map[String, Array[IntentFn]] = real_handlers()` and pass a
fixture map when testing:

```moonbit nocheck
// nocheck: a fragment (a match arm or an expression), not a top-level item
let h = @harness.mount(
  request_module(intents=declining_intent_handlers()),
  "RequestExample",
)
h.send_at_root("init")
inspect(h.text(".error"), content="nothing answers `loadData`")
```

An intent name that **nothing** is registered for is not a crash and not
an error: the route simply runs out and the sender hears
`<name>Unhandled`. A typo surfaces there.

## Integrating with the outside world

A tutuca app talks to the outside world in two directions, and both go
through handlers — never around them.

- **Outbound** — the app reaches out (fetch, timers, storage, external
  APIs). `intent lex 'name'`; the scope-registered `IntentFn` does the
  async work and the answer lands back in component state as
  `<name>Ok` / `<name>Error`.
- **Inbound** — the outside world pushes an event in (a WebSocket
  message, a `postMessage`, a timer, a third-party callback). Use
  `app.send_at_root("name", args=[...])` from the host / glue code. It
  dispatches a message to the **root component**, running its
  `receive <name>` body under the same immutable return-a-new-state
  contract as every other handler.

```moonbit nocheck
// nocheck: a fragment (a match arm or an expression), not a top-level item
// host / glue code, outside the component tree (e.g. inside a JS-FFI callback)
app.send_at_root("serverPushed", args=[@tutuca.Value::from_json(payload)])
|> ignore
```

⚠️ **Do not** reach into the transactor / app internals and overwrite the
root value to inject external data. That bypasses the component handler
model, the immutable return-a-new-state discipline, scope enrichment and
the transactor's batching — state mutated that way is invisible to the
components that own it and easily clobbered by the next transaction.
Route every inbound event through `app.send_at_root` instead.

`send_at_root` only targets the root. To land an inbound event on nested
state, let the root's `receive` body forward it with
`sendAt &.child 'name' …` — one entry point, still reaching deep.

## Fire-and-forget

An intent whose answer you don't need declares no answer arms, so the
generator wires none and the outcome is dropped. Idiomatic for
side-effect-only work like persisting state:

```html
<script type="tutuca/script">
  receive applyFilter(value) {
    intent lex 'persistState' new { key: 'sectionFilter', value: value }
    .filter = value
  }
</script>
```

Fire several in one body when needed — effects come out in the order
written, after the transition succeeds.

## `live_path` — pinning vs following a moving key

`IntentOpts` takes `live_path`. It controls where the answer lands when
the sender's path addresses a seq-access entry (`.sheets[.selId]`): by
**default** the resolved key is *pinned* at dispatch time, so the answer
updates the item that raised the intent even if `.selId` moved while the
walk was in flight (e.g. the user switched tabs). Set `live_path=true` to
opt out and re-resolve the key live, delivering to whatever the key now
points at:

```moonbit nocheck
// nocheck: a fragment (a match arm or an expression), not a top-level item
ctx.intent("save", [payload], @tutuca.IntentOpts::new())              // pinned
ctx.intent("refresh", [], @tutuca.IntentOpts::new(live_path=true))    // live
```

The pinning rules per step kind (and why list indices still slide) are in
[semantics.md](./semantics.md) (*Key resolution & async races*).

## Catch-all arms

In MoonBit, `update` is one pattern match, so the catch-all is just a
wildcard pattern: `Receive(name, args) => ...` (after the specific arms)
catches every message and binds the dispatched name directly — no
separate registration needed. The final `_ => Unhandled` is the silent
drop.

```moonbit nocheck
// nocheck: a bucket argument, not a top-level item
update=(s : DebugState, msg, _ctx) => match msg {
  // specific arms first...
  Receive(name, _args) => Next({ ..s, lastUnhandled: name })
  _ => Unhandled
},
```

(There is no `"$unknown"` sentinel behind this. Dispatch does **one**
lookup; a typed `update` whose match ends in `_ => Unhandled` already
*is* the catch-all, with the name statically bound. A name nothing
handles is simply dropped.)

Return `Next(new_state)` to swap the new value into the dispatch path,
`Unchanged` for "this arm ran and nothing moves", or `Unhandled` for "not
mine" — which is the one that falls through to a generated mutator.

## Positional delivery across async

The path a message or an answer is delivered to is **positional** — an
array of steps from the root, not a captured reference. This is why an
answer survives intervening transactions that rebuilt the root (see
*Mental model* in [core.md](./core.md)). Practical rule: anchor on map
keys, not list indices, when an async answer must reach a specific item —
the per-step-kind pinning rules are in
[semantics.md](./semantics.md).

For observing the dispatch chain an intent belongs to, the `ctx` passed
to `update` exposes `ctx.walk_path(callback)`, which walks the component
instances on the issuing path **leaf→root**, calling
`callback(component_id, instance_value)` (return `false` to stop early).
It captures the immutable dispatch root/path at call time.

## See also

- [core.md](./core.md) — the core mental model, `view` directives, the
  `update`/`compute` overview, and *The ModuleDef convention*.
- [schema.md](./schema.md) — the `receive` and `intent` message
  declarations these handlers are typed by.
- [semantics.md](./semantics.md) — the path/transaction model behind
  these channels: path steps, the transaction lifecycle, teleporting,
  and the key-pinning rules `live_path` toggles.
- [testing.md](./testing.md) — driving message and intent flows from
  tests via the harness.
- [component-design.md](./component-design.md) — which channel to reach
  for when.
- [cli.md](./cli.md) — the embedded CLI commands and exit codes.
