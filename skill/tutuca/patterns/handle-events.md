# Handle events

**Problem:** respond to a DOM event and update state.

```html
<button @on.click="inc">+</button>      <!-- bare name = update Input arm -->
<button @on.click="dec">-</button>        <!-- ...or a generated mutator -->

<!-- pass args by name -->
<input @on.input="setStr value" />
<input @on.input="setN valueAsInt" />
<button @on.click="onAddItem">+</button>

<!-- modifiers: keydown +send (Enter) / +cancel (Esc), and +ctrl/+cmd/+alt -->
<input @on.keydown+send="submit value" @on.keydown+cancel="reset" />

<!-- custom elements: any CustomEvent reaches @on.<name>, detail is `value` -->
<emoji-picker @on.emoji-click="onPick value"></emoji-picker>
```

Written args arrive in the handler's `args : Array[Value]` in template order.
The first slot is a handler name — always bare in an event position, and
dispatched as `Input(name, args)`; `$name` belongs in a VALUE position and is
a generation error here. Later slots
are built-in arg names — `value`, `valueAsInt`/`valueAsFloat`, `key`,
`keyCode`, `isAlt`, `isShift`, `isCtrl`/`isCmd`, `isSend`, `isCancel`,
`dragKey`/`dragValue`/`dragType`, `dragInfo`, … `value` resolves to the input's value (or the checked state for a
checkbox, the metadata `Map` for a file input, or the `detail` for a
`CustomEvent`). There is no `event` / `target` / `ctx` arg: a DOM object is not
a `Value`, so asking for one silently yields `Null`.

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
and `value`/`valueAsInt`-style names arrive **unwrapped** (`String` /
`Double` / `Bool`), bindings like `@key` arrive as `@tutuca.Value`, and
runtime args that don't match the inferred shape land in
`Unknown(name, args)` — the full table is in [core.md](../core.md)
*Generated `Msg` payload types*. `value` follows the host element's
static `type`: `Bool` on a checkbox, metadata `@tutuca.Value` on a file
input, `String` otherwise (including when `:type` is dynamic — handle
that case via the generated mutator or a raw `Input` arm).

Bind events declaratively with `@on.` rather than reaching for the node and
`addEventListener` — an outside listener bypasses the transactor. A handler
that needs `ctx` (to `send` or raise an `intent`) must be an `update` arm —
`compute` is pure by type.

Pass the most granular arg the handler needs — `value`/`valueAsInt`/`key` — so
tests drive it with plain literals. Why this keeps tests simple:
[testing.md](../testing.md#designing-handlers-so-tests-stay-simple). The full arg
list and the generated `<Comp>Msg` payload types are in
[events.md](../events.md).
