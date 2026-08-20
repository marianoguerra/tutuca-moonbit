# Tutuca — Events

Read this file when wiring `@on.<event>` handlers, choosing which handler
argument to ask for, matching a generated `<Comp>Msg` case, using event
modifiers, or handling a custom element's `CustomEvent`.

## Wiring a handler

```html
<!-- a bare name dispatches a `Receive` arm of `update` -->
<button @on.click="inc">+</button>
<button @on.click="dec">-</button>

<!-- pass args: an event read is written `e.<something>` -->
<input @on.input="setStr e.value" />
<input @on.input="setN e.valueAsInt" />
<button @on.click="pick @key e.isAlt">pick</button>
<button @on.click="loadAnotherWay">load</button>
```

The **handler name** is written bare. A leading `$` is refused in an event
position: a `$name` and a bare name are the same dispatch there, so the sigil
would claim a distinction that does not exist. `$` belongs in value positions
(`@text="$label"`), where a `compute` entry answers it.

Its **arguments** carry a sigil that says where the value comes from, and there
are three:

| Written  | Reads                                     |
| -------- | ----------------------------------------- |
| `e.…`    | the DOM event                             |
| `.field` | this component's state                    |
| `@bind`  | a binding — `@key`, `@value.x`            |

Written args arrive in the handler's `args` array in template order — pattern-match
them directly (`Receive("search", [Str(q), ..]) => ...`). For an `update` arm the
`&Ctx` is the explicit third parameter of the update fn; a `compute` entry gets no
ctx (it is pure). So `loadAnotherWay` dispatches `Receive("loadAnotherWay", [])`
plus ctx.

> **Every argument carries a sigil.** A bare name — `@on.input="setStr value"`
> — is refused at generation time, as `BareEventArg`, and the message names the
> three prefixes above. Without a sigil the same word reads two ways: `value`
> could be the DOM event's value or an enclosing `@each` bind's, decided by
> whichever loop happens to surround the element. The runtime does not rescue
> one either — a name with no sigil is looked up among the binds and nowhere
> else, so an unbound one answers `Null`. Write `e.value`.

## Handler arguments

An event read is an `e.<path>`, and it resolves in two layers —
**layer 1 shadows layer 2**.

### Layer 1 — the computed accessors

A single segment naming one of these is answered by the glue, not by a property
read. A DOM `Event` has no `value` at all; `value` is *computed*, which is why
this layer goes first:

`e.value`, `e.valueAsInt`, `e.valueAsFloat`, `e.key`, `e.keyCode`, `e.isAlt`,
`e.isShift`, `e.isCtrl`/`e.isCmd`, `e.isUpKey`, `e.isDownKey`, `e.isSend`,
`e.isCancel`, `e.isTabKey`, `e.dragInfo`, `e.dragKey`, `e.dragValue`,
`e.dragType`.

The list is one array — `@eventpath.event_accessors` — read by the runtime
resolver, the generator and the linter, so the three cannot disagree about what
`e.value` is.

Only a *single* segment can be an accessor: they are framework names, not
properties of anything, so `e.value.length` is not a read of a shorter one.

The content of `e.value` depends on the event source:

| Source                      | What `e.value` resolves to                       |
|-----------------------------|--------------------------------------------------|
| `<input type="checkbox">`   | the checked state (`Bool`)                       |
| `<input type="file">`       | the picked file's metadata as a `Map` (name/size/type/lastModified), `Null` if none |
| a `drop` carrying FILES     | a `List` of the dropped files as `Map`s (`id`/name/size/type/lastModified), on any element — `Null` for an in-app drag, which carries `e.dragInfo` instead |
| `CustomEvent`               | the event's `detail`, mapped to a `Value` (`Map` for objects) |
| anything else               | the input's value (`Str`), or `Null` if absent   |

A dropped file's `id` is how a handler names it again: the `File` itself is a
browser object and never becomes a `Value`, so the backend keeps the last
drop's files and a host reads one by id (the wasm bridge's `load_dropped`,
`globalThis.__tutucaDroppedFile(id)` on js). That is what lets a page take a
dropped file without a listener of its own — `@on.drop="load e.value"` is an
ordinary handler.

For numeric inputs, prefer `e.valueAsInt` / `e.valueAsFloat` to skip the string
parse.

While a drag is in flight, four names answer from it. `e.dragInfo` is the whole
capture (an `Obj` exposing `type` / `value` / `lookupBind(name)`); the other
three are the answers a drop usually wants, so the handler neither opens the
`Obj` nor applies the `Fn` inside it:

| name | answers |
| ---- | ------- |
| `e.dragKey` | the SOURCE row's `@key` — `lookupBind("key")`, as a value |
| `e.dragValue` | the dragged value itself (`dragInfo.value`) |
| `e.dragType` | the `data-dragtype` the source declared |

All four are `Null` when no drag is in flight, which is why all four carry
`@tutuca.Value` in a generated `Msg` rather than the type they look like. The
narrow three are also the ONLY way an interpreted card can read the source row:
a block cannot apply a function it did not name. Worked example:
[advanced.md](./advanced.md#drag-and-drop).

### Layer 2 — the allowlisted property walk

Anything else is a real path into the event object, and every **traversed** step
is checked against an allowlist:

```html
<button @on.click="pick e.target.dataset.rowId">pick</button>
<input @on.input="setName e.target.value" />
<section @on.emoji-click="onEmojiClick e.detail.unicode">…</section>
<div @on.wheel="zoom e.deltaY">…</div>
```

The object-valued steps a path may go **through** are exactly six:

`currentTarget`, `dataTransfer`, `dataset`, `detail`, `relatedTarget`, `target`.

Two of them — `dataset` and `detail` — are *terminals*: once a path reaches
author data there is nothing left to escalate into, so everything below them is
free. `e.detail.a.b.c` works with no framework release.

Anything else is a **generation error** (`BadEventPath`) naming the step:
`ownerDocument`, `parentNode`, `parentElement`, `children`, `form`, `view`,
`window`. Each leads out of the event and into the page, and
`e.target.ownerDocument.defaultView.localStorage.length` is a view template
reading the host. A view is data the host compiles — including one a dyncomp
guest supplied — so a permitted root is not a permitted path.

Two more rules worth holding:

- **A path always produces a `Value`.** The last segment is the leaf and is
  converted; a leaf that is not representable is `Null`. So `e.target` on its
  own is `Null` — an `Element` is not a `Value` — and it is the *leaf* rule
  rather than the allowlist that says so.
- **A rooted name no event interface declares is a hint**, with the nearest
  match: `e.valeu` says *did you mean `e.value`?*. It is a hint and not an error
  because `e.target.someVendorThing` may be deliberate, and a generator cannot
  tell the two apart. The known set is the accessors above plus every property
  the generated DOM table carries for any `*Event` interface, so `e.deltaY` and
  `e.pointerId` say nothing.

> **There is no `event` or `ctx` argument.** A DOM object is not a `Value`, so
> `@on.input="setCount event"` resolves to `Null` and the handler receives
> `[Null, ..]` with nothing reported. Reach the event through `e.` — that is
> what it is for — and the `&Ctx` reaches an `update` arm as the third
> parameter, never as an argument.

An `e.` path is refused **outside** an argument slot: `@text="e.value"` is a
render-time read of an event that is not happening.

## Generated `Msg` payload types

When the views are generated (`gen-views`), each `@on` name becomes a case of the
`<Comp>Msg` enum, and the payload type of each argument is inferred from what is
**written at the call site**:

| Written in the template | Payload type in `<Comp>Msg` |
| ----------------------- | --------------------------- |
| `'literal'` / `1` / `true` | `String` / `Double` / `Bool` |
| `e.value` | `String` — but `Bool` on `<input type="checkbox">` and `@tutuca.Value` on `<input type="file">` (the host element's static `type` decides) |
| `e.key` | `String` |
| `e.valueAsInt`, `e.valueAsFloat`, `e.keyCode` | `Double` |
| `e.isAlt`, `e.isShift`, `e.isCtrl`/`e.isCmd`, `e.isUpKey`, `e.isDownKey`, `e.isSend`, `e.isCancel`, `e.isTabKey` | `Bool` |
| a multi-segment path (`e.target.value`, `e.detail.x`) | `@tutuca.Value` |
| a binding (`@key`, `@value.x`), `e.dragInfo`/`e.dragKey`/`e.dragValue`/`e.dragType`, a drop's files, anything else | `@tutuca.Value` |

There is one spelling for an event read and one table that types it, so a
payload type is decided in a single place. A **longer** path is `@tutuca.Value`
and nothing narrows it: the DOM property table could answer for a rooted read,
but not for a path through `detail` or `dataset`, where the shape is the
application's.

So `@on.click="setTab 'edit'"` generates `SetTab(String)` (unwrapped — match
`Some(SetTab(tab))`, not `Some(SetTab(Str(tab)))`), `@on.input="setCompleted e.value"` on a checkbox generates `SetCompleted(Bool)`, and
`@on.click="removeInItemsAt @key"` generates `RemoveInItemsAt(@tutuca.Value)`.
Two call sites that disagree on an argument's shape join to `@tutuca.Value`. At
runtime, arguments that don't match the inferred shape land in
`Unknown(name, args)` with the raw `Array[@tutuca.Value]`.

> The `e.value` inference reads the host element's **static** `type` attribute,
> matching what the glue delivers (checkbox → the checked state, file → the
> metadata `Map` / `Null`). An input whose `type` is dynamic (`:type=".kind"`)
> keeps the default `String` — if such an input can render as a checkbox at
> runtime, handle its value via the generated mutator or a raw
> `Receive(name, args)` arm rather than a typed case.

## Event modifiers

`@on.<event>+<mod>+<mod>=...`

Modifiers are **guards**: a failing one makes the handler a no-op. They are
defined for two events only, and an unknown event/modifier pair passes through
as if it were not there (`app/app.mbt:35-54`):

| Event | Modifiers |
| ----- | --------- |
| `keydown` | `+send` (Enter), `+cancel` (Escape), `+ctrl`, `+cmd`, `+meta`, `+alt` |
| `click` | `+ctrl`, `+cmd`, `+meta`, `+alt` |

```html
<input @on.keydown+send="submit e.value" @on.keydown+cancel="reset" />
<button @on.click+ctrl="soloOnly">ctrl-click</button>
```

> **No effect modifiers.** The JS framework's `+prevent` and `+stop` have no
> counterpart here, and a modifier the table does not list is silently ignored
> rather than refused — so `@on.submit+prevent="save"` compiles, runs `save`, and
> does **not** call `preventDefault`. Porting a view that relied on either, use a
> form control that does not navigate (a `<button type="button">`) or restructure
> so the default action is harmless.

## Web components & custom events

Custom elements just work, and any `CustomEvent` they fire is reachable via
`@on.<event-name>`. The event's `detail` surfaces two ways: `e.value` is the
whole `detail` mapped to a `Value::Map`, and `e.detail.<field>` walks into it —
`detail` is a terminal, so the path may go as deep as the payload does.

```html
<section @on.emoji-click="onEmojiClick e.value">
  <emoji-picker @show=".isPickerVisible"></emoji-picker>
</section>
```

```moonbit nocheck
// nocheck: one bucket argument, not a compilable item
// the host page loads <emoji-picker> (emoji-picker-element) from a CDN;
// the component just hosts the tag and handles its event.
// `current: any` in the schema
update=(s, msg, _ctx) => match msg {
  Receive("onEmojiClick", [Map(detail), ..]) =>
    Some({ ..s, current: detail.get("unicode").unwrap_or(Null) })
  _ => Unhandled
}
```

Asking for `e.detail.unicode` instead moves that `.get` into the template and
gives the arm a plain value to match. Either is fine; the choice is whether the
handler wants the whole payload or one field of it.

Handle these events declaratively with `@on.<event-name>` in the view — don't
grab the node from host/glue code and `addEventListener` on it. A listener
attached from outside the component runs outside the handler model: no
new-state return, no transactor batching, and the mutation is invisible to the
component that owns the state. For any event with a real element in the tree,
`@on.` is the only entry point you need. Genuinely external inbound sources
(WebSocket, `postMessage`, timers) have no element to bind — route those through
`app.send_at_root` instead (see
[messages-and-intents.md](./messages-and-intents.md)).

Pitfall: binding a camelCase JS property on a custom element silently fails —
the HTML parser lowercases attribute names before tutuca sees them, so `:mapId`
arrives as `:mapid`. See *Attribute Binding* in
[core.md](./core.md#attribute-binding).

## See also

- [core.md](./core.md#the-handler-buckets) — which bucket answers a name, and
  the dispatch precedence between them.
- [testing.md](./testing.md) — driving real events through `@harness`, including
  `h.fire` for custom events and file picks.
- [patterns/handle-events.md](./patterns/handle-events.md) — the minimal recipe.
- [patterns/file-input.md](./patterns/file-input.md) — reading a picked file.
