# Handle events

**Problem:** respond to a DOM event and update state.

```html
<button @on.click="inc">+</button>      <!-- bare name = update Receive arm -->
<button @on.click="dec">-</button>        <!-- ...or a generated mutator -->

<!-- pass args by name -->
<input @on.input="setStr e.value" />
<input @on.input="setN e.valueAsInt" />
<button @on.click="onAddItem">+</button>

<!-- modifiers: keydown +send (Enter) / +cancel (Esc), and +ctrl/+cmd/+alt -->
<input @on.keydown+send="submit e.value" @on.keydown+cancel="reset" />

<!-- custom elements: any CustomEvent reaches @on.<name>, detail is `e.value` -->
<emoji-picker @on.emoji-click="onPick e.value"></emoji-picker>
```

Written args arrive in the handler's `args : Array[Value]` in template order.
The first slot is a handler name — always bare in an event position, and
dispatched as `Receive(name, args)`; `$name` belongs in a VALUE position and is
a generation error here. Later slots carry a sigil for where they read from:
`e.…` the event, `.field` state, `@bind` a binding. (A bare name names none of
the three, so it is a generation error.) The computed accessors are `e.value`,
`e.valueAsInt`/`e.valueAsFloat`, `e.key`, `e.keyCode`,
`e.isAlt`, `e.isShift`, `e.isCtrl`/`e.isCmd`, `e.isSend`, `e.isCancel`,
`e.dragKey`/`e.dragValue`/`e.dragType`, `e.dragInfo`, … and `e.value` resolves
to the input's value (or the checked state for a checkbox, the metadata `Map`
for a file input, or the `detail` for a `CustomEvent`). A longer path walks the
event itself — `e.target.dataset.rowId`, `e.detail.x` — through six allowlisted
steps. There is no `event` / `ctx` arg: a DOM object is not a `Value`, so asking
for one silently yields `Null`.

```moonbit nocheck
// nocheck: a bucket argument, not a top-level item
// gets ctx: (s, msg, ctx) => S?; None = no change.
// `CounterMsg` is generated from the `@on` names the views raise, so adding
// one to the view makes this match non-exhaustive until it is answered.
update=(s, msg, _ctx) => match CounterMsg::from_dispatch(msg) {
  Some(Inc) => Next({ count: s.count + 1 })
  Some(Dec) => Next({ count: s.count - 1 })
  Some(Unknown(_, _)) | None => Unhandled
},
```

Each `Msg` case's payload type is inferred from the call site: literals
and `e.value`/`e.valueAsInt`-style accessors arrive **unwrapped** (`String` /
`Double` / `Bool`), bindings like `@key` and multi-segment paths like
`e.target.value` arrive as `@tutuca.Value`, and runtime args that don't match
the inferred shape land in `Unknown(name, args)` — the full table is in
[events.md](../events.md) *Generated `Msg` payload types*. `e.value` follows the host element's
static `type`: `Bool` on a checkbox, metadata `@tutuca.Value` on a file
input, `String` otherwise (including when `:type` is dynamic — handle
that case via the generated mutator or a raw `Receive` arm).

Bind events declaratively with `@on.` rather than reaching for the node and
`addEventListener` — an outside listener bypasses the transactor. A handler
that needs `ctx` (to `send` or raise an `intent`) must be an `update` arm —
`compute` is pure by type.

Pass the most granular arg the handler needs — `e.value`/`e.valueAsInt`/`e.key` — so
tests drive it with plain literals. Why this keeps tests simple:
[testing.md](../testing.md#designing-handlers-so-tests-stay-simple). The full arg
list and the generated `<Comp>Msg` payload types are in
[events.md](../events.md).
