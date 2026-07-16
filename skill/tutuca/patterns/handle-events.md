# Handle events

**Problem:** respond to a DOM event and update state.

```html
<button @on.click="$inc">+</button>      <!-- $ calls a method -->
<button @on.click="dec">-</button>        <!-- bare name = input handler -->

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
The first slot is a handler name (`$method` in `methods`, or a bare name in
`input`/`alter`); later slots are built-in arg names — `value`,
`valueAsInt`/`valueAsFloat`, `event`, `key`, `isAlt`, `isShift`,
`isCtrl`/`isCmd`, `dragInfo`, … `value` resolves to the input's value (or the
checked state for a checkbox, the metadata `Map` for a file input, or the
`detail` for a `CustomEvent`).

```moonbit
methods={ // pure: (inst, args) => Value
  "inc": (inst, _args) => {
    match inst.get("count") {
      Num(n) => inst.set("count", Num(n + 1)).to_value()
      _ => inst.to_value()
    }
  },
},
input={ // gets ctx: (inst, args, ctx) => Instance?; None = no change
  "dec": (inst, _args, _ctx) => {
    match inst.get("count") {
      Num(n) => Some(inst.set("count", Num(n - 1)))
      _ => None
    }
  },
},
```

Bind events declaratively with `@on.` rather than reaching for the node and
`addEventListener` — an outside listener bypasses the transactor. A handler
that needs `ctx` (to `send`/`bubble`/`request`) must be an `input` handler —
`methods` are pure by type.

Pass the most granular arg the handler needs — `value`/`valueAsInt`/`key`, not
the raw `event` — so tests drive it with plain literals. Why this keeps tests
simple: [testing.md](../testing.md) *Designing handlers so tests stay simple*.
