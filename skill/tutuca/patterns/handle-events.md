# Handle events

**Problem:** respond to a DOM event and update state.

```html
<button @on.click="$inc">+</button>      <!-- $ calls a mutate/generated -->
<button @on.click="dec">-</button>        <!-- bare name = update Input arm -->

<!-- pass args by name -->
<input @on.input="$setStr value" />
<input @on.input="$setN valueAsInt" />
<button @on.click="onAddItem">+</button>

<!-- modifiers: keydown +send (Enter) / +cancel (Esc), and +ctrl/+cmd/+alt -->
<input @on.keydown+send="$submit value" @on.keydown+cancel="$reset" />

<!-- custom elements: any CustomEvent reaches @on.<name>, detail is `value` -->
<emoji-picker @on.emoji-click="onPick value"></emoji-picker>
```

Written args arrive in the handler's `args : Array[Value]` in template order.
The first slot is a handler name (`$name` for `mutate`/`compute`/generated,
or a bare name dispatched as `Input(name, args)` to `update`); later slots
are built-in arg names — `value`, `valueAsInt`/`valueAsFloat`, `event`,
`key`, `isAlt`, `isShift`, `isCtrl`/`isCmd`, `dragInfo`, … `value` resolves
to the input's value (or the checked state for a checkbox, the metadata
`Map` for a file input, or the `detail` for a `CustomEvent`).

```moonbit
mutate={ // pure: (s, args) => S
  "inc": (s : CounterState, _args) => { count: s.count + 1 },
},
// gets ctx: (s, msg, ctx) => S?; None = no change
update=(s : CounterState, msg, _ctx) => match msg {
  Input("dec", _) => Some({ count: s.count - 1 })
  _ => None
},
```

Bind events declaratively with `@on.` rather than reaching for the node and
`addEventListener` — an outside listener bypasses the transactor. A handler
that needs `ctx` (to `send`/`bubble`/`request`) must be an `update` arm —
`mutate`/`compute` are pure by type.

Pass the most granular arg the handler needs — `value`/`valueAsInt`/`key`, not
the raw `event` — so tests drive it with plain literals. Why this keeps tests
simple: [testing.md](../testing.md) *Designing handlers so tests stay simple*.
