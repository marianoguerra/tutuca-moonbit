# Tutuca — Events

Read this file when wiring `@on.<event>` handlers, choosing which handler
argument to ask for, matching a generated `<Comp>Msg` case, using event
modifiers, or handling a custom element's `CustomEvent`.

## Wiring a handler

```html
<!-- a bare name dispatches an `Input` arm of `update` -->
<button @on.click="inc">+</button>
<button @on.click="dec">-</button>

<!-- pass args by name -->
<input @on.input="setStr value" />
<input @on.input="setN valueAsInt" />
<button @on.click="pick @key isAlt">pick</button>
<button @on.click="loadAnotherWay">load</button>
```

Every `@on` handler is written **bare**. A leading `$` is refused in an event
position: a `$name` and a bare name are the same dispatch there, so the sigil
would claim a distinction that does not exist. `$` belongs in value positions
(`@text="$label"`), where a `compute` entry answers it.

Written args arrive in the handler's `args` array in template order — pattern-match
them directly (`Input("search", [Str(q), ..]) => ...`). For an `update` arm the
`&Ctx` is the explicit third parameter of the update fn; a `compute` entry gets no
ctx (it is pure). So `loadAnotherWay` dispatches `Input("loadAnotherWay", [])`
plus ctx.

## Handler arguments

Every argument is a **name the glue resolves to a `Value`**:

`value`, `valueAsInt`, `valueAsFloat`, `key`, `keyCode`, `isAlt`, `isShift`,
`isCtrl`/`isCmd`, `isUpKey`, `isDownKey`, `isSend`, `isCancel`, `isTabKey`,
`dragInfo`.

> **There is no `event`, `target` or `ctx` argument.** A DOM object is not a
> `Value`, so the port exposes none: `@on.input="setCount event"` resolves to
> `Null` and the handler receives `[Null, ..]`. Nothing reports it — the dispatch
> lands and does nothing. Ask for the narrowest named arg instead
> (`render/dom_event.mbt:38-57`). The `&Ctx` reaches an `update` arm as the third
> parameter, never as an argument.

The content of `value` depends on the event source:

| Source                      | What `value` resolves to                         |
|-----------------------------|--------------------------------------------------|
| `<input type="checkbox">`   | the checked state (`Bool`)                       |
| `<input type="file">`       | the picked file's metadata as a `Map` (name/size/type/lastModified), `Null` if none |
| `CustomEvent`               | the event's `detail`, mapped to a `Value` (`Map` for objects) |
| anything else               | the input's value (`Str`), or `Null` if absent   |

For numeric inputs, prefer `valueAsInt` / `valueAsFloat` to skip the string
parse.

Because file inputs and custom events already arrive as plain `Map` metadata,
there is no case left where a handler would need the raw event — which is why
the port drops it rather than mapping DOM objects into the value layer. An arm
matching `[Str(q), ..]` off a plain `value` is also trivial to call from a test;
see [testing.md](./testing.md#designing-handlers-so-tests-stay-simple).

## Generated `Msg` payload types

When the views are generated (`gen-views`), each `@on` name becomes a case of the
`<Comp>Msg` enum, and the payload type of each argument is inferred from what is
**written at the call site**:

| Written in the template | Payload type in `<Comp>Msg` |
| ----------------------- | --------------------------- |
| `'literal'` / `1` / `true` | `String` / `Double` / `Bool` |
| `value` | `String` — but `Bool` on `<input type="checkbox">` and `@tutuca.Value` on `<input type="file">` (the host element's static `type` decides) |
| `key` | `String` |
| `valueAsInt`, `valueAsFloat`, `keyCode` | `Double` |
| `isAlt`, `isShift`, `isCtrl`/`isCmd`, `isUpKey`, `isDownKey`, `isSend`, `isCancel`, `isTabKey` | `Bool` |
| a binding (`@key`, `@value.x`), `dragInfo`, anything else | `@tutuca.Value` |

So `@on.click="setTab 'edit'"` generates `SetTab(String)` (unwrapped — match
`Some(SetTab(tab))`, not `Some(SetTab(Str(tab)))`), `@on.input="setCompleted
value"` on a checkbox generates `SetCompleted(Bool)`, and
`@on.click="removeInItemsAt @key"` generates `RemoveInItemsAt(@tutuca.Value)`.
Two call sites that disagree on an argument's shape join to `@tutuca.Value`. At
runtime, arguments that don't match the inferred shape land in
`Unknown(name, args)` with the raw `Array[@tutuca.Value]`.

> The `value` inference reads the host element's **static** `type` attribute,
> matching what the glue delivers (checkbox → the checked state, file → the
> metadata `Map` / `Null`). An input whose `type` is dynamic (`:type=".kind"`)
> keeps the default `String` — if such an input can render as a checkbox at
> runtime, handle its `value` via the generated mutator or a raw
> `Input(name, args)` arm rather than a typed case.

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
<input @on.keydown+send="submit value" @on.keydown+cancel="reset" />
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
`@on.<event-name>`. The event's `detail` surfaces as `value` — the glue maps it
to a `Value::Map`:

```html
<section @on.emoji-click="onEmojiClick value">
  <emoji-picker @show=".isPickerVisible"></emoji-picker>
</section>
```

```moonbit nocheck
// nocheck: one bucket argument, not a compilable item
// the host page loads <emoji-picker> (emoji-picker-element) from a CDN;
// the component just hosts the tag and handles its event.
// `current: any` in the schema
update=(s, msg, _ctx) => match msg {
  Input("onEmojiClick", [Map(detail), ..]) =>
    Some({ ..s, current: detail.get("unicode").unwrap_or(Null) })
  _ => None
}
```

Handle these events declaratively with `@on.<event-name>` in the view — don't
grab the node from host/glue code and `addEventListener` on it. A listener
attached from outside the component runs outside the handler model: no
new-state return, no transactor batching, and the mutation is invisible to the
component that owns the state. For any event with a real element in the tree,
`@on.` is the only entry point you need. Genuinely external inbound sources
(WebSocket, `postMessage`, timers) have no element to bind — route those through
`app.send_at_root` instead (see
[request-response.md](./request-response.md)).

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
