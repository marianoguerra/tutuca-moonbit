# Coordinate components

**Problem:** move state between components — notify an ancestor, message a
specific component, or run async work and fold in the result.

Every incoming message lands in the component's one `update` match —
the channel picks the `Dispatch` arm:

```moonbit
// bubble — walk toward the root; the first ancestor whose update
// matches the Bubble arm runs it
update=(s : LogState, msg, ctx) => match msg {
  Input("onItemClick", _) => {
    ctx.bubble("itemSelected", [Str(s.label)])
    None
  }
  Bubble("itemSelected", [Str(label), ..]) => {
    let log = s.log.copy()
    log.insert(0, Str(label))
    Some({ ..s, log, })
  }
  _ => None
},

// send / receive — deliver to one target (self, or ctx.at() for another)
update=(s : ChatState, msg, ctx) => match msg {
  Input("submit", _) => {
    ctx.at().field("status").send("flash", [Str(s.draft)])
    None
  }
  Receive("flash", [Str(message), ..]) => Some({ ..s, message, })
  _ => None
},

// request / response — async scope-registered work, result routed back
update=(s : ListState, msg, ctx) => match msg {
  Receive("init", _) => {
    ctx.request("loadData", [], @tutuca.RequestOpts::new())
    Some({ ..s, isLoading: true })
  }
  Response("loadData", [res, _err]) => // args = [res, err]
    Some({ ..s, isLoading: false, items: res.list() })
  _ => None
},
```

Pick by direction: **bubble** for aggregate state an ancestor owns (logs,
selections); **send/receive** to address one known component
(`ctx.at().field("x")` / `.index(name, i)` / `.key(name, k)`, default self);
**request/response** for fetch/timer/storage — register the callback-style
`RequestFn` on the `ModuleDef` (`requests={...}`), and the default `Response`
arm gets `args = [res, err]`. The `update` fn gets `ctx` as its explicit
third parameter. `Receive("init", _)` is a convention, not a lifecycle
hook — dispatch it with `app.send_at_root("init")`.

Carry the most granular payload across the channel, not whole objects you
won't use — `ctx.bubble("itemSelected", [Str(s.label)])` over passing the
entire instance (same reasoning as handler args: [testing.md](../testing.md)
*Designing handlers so tests stay simple*).
