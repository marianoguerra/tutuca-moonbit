# Coordinate components

**Problem:** move state between components — tell one component something,
ask for work you can't name a handler for, or run async work and fold in
the result.

Every incoming message lands in the component's one `update` match — the
channel picks the `Dispatch` arm:

```moonbit nocheck
// nocheck: a bucket argument, not a top-level item
// send / receive — deliver to ONE target (self, or ctx.at() for another)
update=(s : ChatState, msg, ctx) => match msg {
  Receive("submit", _) => {
    ctx.at().field("status").send("flash", [Str(s.draft)])
    None
  }
  Receive("flash", [Str(message), ..]) => Next({ ..s, message, })
  _ => Unhandled
},

// intent dyn — walk toward the root; the first ancestor whose Intent arm
// REPLIES ends the walk, and one that only records it is an observer
update=(s : LogState, msg, ctx) => match msg {
  Receive("onItemClick", _) => {
    ctx.intent("itemSelected", [Str(s.label)], @tutuca.IntentOpts::new(route=[Dyn]))
    None
  }
  Intent("itemSelected", [Str(label), ..]) => {
    let log = s.log.copy()
    log.insert(0, Str(label))
    Some({ ..s, log, })
  }
  _ => Unhandled
},

// intent lex — async scope-registered work; the answer comes back as an
// ordinary message, under one of THREE names
update=(s : ListState, msg, ctx) => match msg {
  Receive("init", _) => {
    ctx.intent("loadData", [], @tutuca.IntentOpts::new(route=[Lex]))
    Some({ ..s, isLoading: true })
  }
  Receive("loadDataOk", [res, ..]) =>
    Some({ ..s, isLoading: false, items: res.list() })
  Receive("loadDataError", [Str(e), ..]) =>
    Some({ ..s, isLoading: false, error: Str(e) })
  Receive("loadDataUnhandled", _) =>
    Some({ ..s, isLoading: false, error: Str("nothing answers `loadData`") })
  _ => Unhandled
},
```

Pick by **what you know**: `send` / `receive` when you can name the target
(`ctx.at().field("x")` / `.index(name, i)` / `.key(name, k)`, default self);
`intent` when you can only name the job, and let the route find who does it.
The route is a list of legs — `dyn` walks the ancestors (starting at the
sender's *parent*), `lex` walks the `IntentFn`s registered on the scope
(`intents={ "loadData": [...] }` on the `ModuleDef`), and a bare `intent`
takes `dyn lex`: try the ancestors, then the scope.

Every intent ends in exactly one of three named answers — `<name>Ok`,
`<name>Error`, `<name>Unhandled` — dispatched back to the sender as ordinary
`Receive` arms. `<name>Unhandled` means the route ran out with nobody
claiming it, which is a different sentence from a handler failing.

The `update` fn gets `ctx` as its explicit third parameter.
`Receive("init", _)` is a convention, not a lifecycle hook — dispatch it with
`app.send_at_root("init")`.

Carry the most granular payload across the channel, not whole objects you
won't use — `ctx.intent("itemSelected", [Str(s.label)], opts)` over passing
the entire instance (same reasoning as handler args:
[testing.md](../testing.md) *Designing handlers so tests stay simple*).
