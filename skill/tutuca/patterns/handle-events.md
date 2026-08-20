# Handle events

**Problem:** respond to a DOM event and update state.

```html
<script type="tutuca/state">
  state Counter { count: Int, str: String, n: Int }
</script>

<script type="tutuca/script" for="Counter">
  receive inc { .count += 1 }
  receive dec { .count -= 1 }

  /// The argument the view wrote arrives by name; its type is inferred from
  /// the call site, so nothing declares it twice.
  receive submit(text) { .str = text }
  receive reset { .str = '' }
</script>

<template id="Counter">
  <div>
    <button @on.click="inc">+</button>      <!-- bare name = a handler -->
    <button @on.click="dec">-</button>        <!-- ...or a generated mutator -->

    <!-- pass args by name -->
    <input @on.input="setStr e.value" />
    <input @on.input="setN e.valueAsInt" />

    <!-- modifiers: keydown +send (Enter) / +cancel (Esc), and +ctrl/+cmd/+alt -->
    <input @on.keydown+send="submit e.value" @on.keydown+cancel="reset" />

    <!-- custom elements: any CustomEvent reaches @on.<name>, detail is `e.value` -->
    <emoji-picker @on.emoji-click="setStr e.value"></emoji-picker>
  </div>
</template>
```

An `@on` name is answered by the first of three that claims it: a `receive` in
the script block, an arm of your `update`, or the generated mutator the field's
kind comes with (`setStr`, `setN`, `toggleDone`, `removeInItemsAt`). Reach for
a mutator when one already says it — `@on.click="toggleHideCompleted"` needs no
handler anywhere.

Written args arrive in template order. The first slot is a handler name —
always bare in an event position, and dispatched as `Receive(name, args)`;
`$name` belongs in a VALUE position and is a generation error here. Later slots
carry a sigil for where they read from: `e.…` the event, `.field` state,
`@bind` a binding. (A bare name names none of the three, so it is a generation
error.) The computed accessors are `e.value`,
`e.valueAsInt`/`e.valueAsFloat`, `e.key`, `e.keyCode`,
`e.isAlt`, `e.isShift`, `e.isCtrl`/`e.isCmd`, `e.isSend`, `e.isCancel`,
`e.dragKey`/`e.dragValue`/`e.dragType`, `e.dragInfo`, … and `e.value` resolves
to the input's value (or the checked state for a checkbox, the metadata `Map`
for a file input, or the `detail` for a `CustomEvent`). A longer path walks the
event itself — `e.target.dataset.rowId`, `e.detail.x` — through six allowlisted
steps. There is no `event` / `ctx` arg: a DOM object is not a `Value`, so asking
for one silently yields `Null`.

Bind events declaratively with `@on.` rather than reaching for the node and
`addEventListener` — an outside listener bypasses the transactor.

Sending a message or raising an intent does **not** need MoonBit: `send`,
`sendAt`, `intent <route>` and `forward` are effects the block spells, queued so
they go out only if the whole transition finished — see
[coordinate-components.md](coordinate-components.md).

**When it stays MoonBit.** A handler whose body the block cannot spell falls
through to the `update` match, which the generator types from the `@on` names
the views raise:

```moonbit nocheck
// nocheck: a bucket argument, not a top-level item
// gets ctx: (s, msg, ctx) => Update[S]; Unhandled falls through to the
// generated mutators. `CounterMsg` is generated from the @on names, so adding
// one to the view makes this match non-exhaustive until it is answered.
update=(s, msg, _ctx) => match CounterMsg::from_dispatch(msg) {
  Some(Inc) => Next({ ..s, count: s.count + 1 })
  Some(Dec) => Next({ ..s, count: s.count - 1 })
  Some(Unknown(_, _)) | None => Unhandled
},
```

A name the block answers is **dropped from that enum** — its arm could never
run — so the two halves cannot both claim one handler.

Each `Msg` case's payload type is inferred from the call site: literals
and `e.value`/`e.valueAsInt`-style accessors arrive **unwrapped** (`String` /
`Double` / `Bool`), bindings like `@key` and multi-segment paths like
`e.target.value` arrive as `@tutuca.Value`, and runtime args that don't match
the inferred shape land in `Unknown(name, args)` — the full table is in
[events.md](../events.md) *Generated `Msg` payload types*. `e.value` follows the host element's
static `type`: `Bool` on a checkbox, metadata `@tutuca.Value` on a file
input, `String` otherwise (including when `:type` is dynamic — handle
that case via the generated mutator or a raw `Receive` arm).

Pass the most granular arg the handler needs — `e.value`/`e.valueAsInt`/`e.key` — so
tests drive it with plain literals. Why this keeps tests simple:
[testing.md](../testing.md#designing-handlers-so-tests-stay-simple). The full arg
list and the generated `<Comp>Msg` payload types are in
[events.md](../events.md).
