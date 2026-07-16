# Coordinate components

**Problem:** move state between components — notify an ancestor, message a
specific component, or run async work and fold in the result.

```moonbit
// bubble — walk toward the root; the first ancestor with the handler runs
input={
  "onItemClick": (inst, _args, ctx) => {
    ctx.bubble("itemSelected", [inst.get("label")])
    None
  },
},
bubble={
  "itemSelected": (inst, args, _ctx) => {
    match args {
      [Str(label), ..] => {
        let log = match inst.get("log") {
          List(a) => a.copy()
          _ => []
        }
        log.insert(0, Str(label))
        Some(inst.set("log", List(log)))
      }
      _ => None
    }
  },
},

// send / receive — deliver to one target (self, or ctx.at() for another)
input={
  "submit": (inst, _args, ctx) => {
    ctx.at().field("status").send("flash", [inst.get("draft")])
    None
  },
},
receive={
  "flash": (inst, args, _ctx) => {
    match args {
      [message, ..] => Some(inst.set("message", message))
      _ => None
    }
  },
},

// request / response — async scope-registered work, result routed back
receive={
  "init": (inst, _args, ctx) => {
    ctx.request("loadData", [], @tutuca.RequestOpts::new())
    Some(inst.set("isLoading", Bool(true)))
  },
},
response={
  "loadData": (inst, args, _ctx) => { // args = [res, err]
    match args {
      [res, _err] => Some(inst.set("isLoading", Bool(false)).set("items", res))
      _ => None
    }
  },
},
```

Pick by direction: **bubble** for aggregate state an ancestor owns (logs,
selections); **send/receive** to address one known component
(`ctx.at().field("x")` / `.index(name, i)` / `.key(name, k)`, default self);
**request/response** for fetch/timer/storage — register the callback-style
`RequestFn` on the `ModuleDef` (`requests={...}`), and the default `response`
handler gets `args = [res, err]`. Handlers get `ctx` as their explicit third
parameter. `receive.init` is a convention, not a lifecycle hook — dispatch it
with `app.send_at_root("init")`.

Carry the most granular payload across the channel, not whole objects you
won't use — `ctx.bubble("itemSelected", [inst.get("label")])` over passing the
entire instance (same reasoning as handler args: [testing.md](../testing.md)
*Designing handlers so tests stay simple*).
