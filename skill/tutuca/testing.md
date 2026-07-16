# Tutuca — Testing

How to author component tests in the MoonBit port. There is **no
`tutuca test` command** and no ported `expect` / `describe` layer — the
JS runner and chai/jest matchers existed only because JS lacked a
capable native runner. **`moon test` is the runner**, MoonBit's built-in
assertions cover the whole jest surface, and the reusable headless
harness (`marianoguerra/tutuca/testing/harness`, imported as
`@harness`) mounts a `ModuleDef` as a live app on the in-memory DOM.
General authoring lives in [core.md](./core.md).

## Setup

Add the harness to the package's test imports in `moon.pkg`:

```
import {
  "marianoguerra/tutuca",
  "marianoguerra/tutuca/component",
}

import {
  "marianoguerra/tutuca/testing/harness",
  "marianoguerra/tutuca/render",   // for DomEvent in fire(...)
} for "test"
```

Author tests as plain `test "..." { ... }` blocks in `*_test.mbt` files:

```moonbit
test "counter: click increments" {
  let h = @harness.mount(counter_module(), "Counter")
  inspect(h.text(".stat-value"), content="0")
  h.click(".btn-success") // @on.click="$inc"
  inspect(h.text(".stat-value"), content="1")
}
```

Run with `moon test` (add `--update` to refresh `inspect` /
`debug_inspect` snapshots, `-p <package>` to scope). Note the module's
`preferred_target` may make a bare `moon test` cover only
target-agnostic packages — browser-glue packages need
`moon test --target js`.

## The harness API

**Mounting** — both build the scope, compile everything, mount on the
in-memory DOM (`memdom`), and render once:

- `@harness.mount(module, "CompName", args?={...})` — mount a component
  by name with optional root args.
- `@harness.mount_example(module, "Example Title")` — mount one of the
  module's `ExampleDef`s by title (the same artifact `tutuca render`
  and the browser hosts show, so a passing test and a working page are
  the same thing).

**Driving** — each fires a real event through the transactor and settles
before returning (CSS-selector addressed; `nth?` picks among matches):

| Call | Simulates |
|---|---|
| `h.click(sel, nth?)` | a click on the element |
| `h.type_into(sel, text, nth?)` | an `input` event with `value` |
| `h.key_down(sel, key, value?, nth?)` | a `keydown` (e.g. `"Enter"`, `"Escape"`) |
| `h.check(sel, checked, nth?)` | a checkbox toggle |
| `h.fire(sel, @render.DomEvent::new(name=..., value=...), nth?)` | any event, incl. custom events and file picks |
| `h.drag(sel, from_nth, to_nth)` | a drag between two matches |
| `h.send_at_root(name, args?)` | a host dispatch (e.g. `"init"`) |

**Reading** — read the re-rendered DOM and settled state back:

| Call | Returns |
|---|---|
| `h.text(sel, nth?)` / `h.texts(sel)` | text content of one / all matches |
| `h.attr(sel, name, nth?)` | attribute value (`String?`) |
| `h.prop(sel, name, nth?)` | a set property (`AttrValue?`) |
| `h.value_of(sel, nth?)` / `h.checked_of(sel, nth?)` | input value / checked state |
| `h.html()` | the whole rendered HTML |
| `h.find(sel, nth?)` / `h.find_all(sel)` | the memdom nodes |
| `h.render_count()` | renders so far (assert batching) |
| `h.drive_value()` | the settled root `Value` |
| `h.styles()` | the compiled CSS text |

Worked references: `testing/harness/harness_test.mbt` (the shape) and
the `examples/*_test.mbt` suite (forty modules' worth of interaction
tests).

## Assertions — jest → MoonBit built-ins

No matcher DSL. `@tutuca.Value` derives `Eq` (deep) and `Debug`, so
`assert_eq` and `debug_inspect` work on values directly:

| chai/jest | MoonBit built-in |
|---|---|
| `toBe` (identity) | `@test.assert_same_object` / `assert_not_same_object` |
| `toBe` / `toEqual` (value; `Eq` **is** deep-equal) | `assert_eq` / `assert_not_eq` |
| `toThrow` | `@test.assert_raise` (or `expect_error` to inspect the error) |
| `toBeInstanceOf` | `assert_true(v is Obj(_))` — pattern match, no runtime classes |
| `toBeNull` / `toBeUndefined` | `assert_true(v is Null)` (Value) / `x is None` (Option) |
| `toBeTruthy` / `toBeFalsy` | `assert_true` / `assert_false`; `v.is_truthy()` for a Value |
| `toContain` / `toHaveLength` | `assert_true(xs.contains(x))` / `assert_eq(xs.length(), n)` |
| snapshot | `inspect(x, content=..)` / `debug_inspect(x, content=..)` |

`--bail` and per-component filtering have no direct equivalent —
organize by `moon test` block names and files.

## What to test

Run tests when the change is observable behavior — handlers, methods,
coercion, interaction flows. Skip them for pure template/styling tweaks;
`tutuca render` covers those.

- **Interaction flows** (the default) — mount with the harness, drive
  events, assert the DOM. This exercises the template wiring, the
  dispatch path, and the handler in one go.
- **Pure logic** — extract it into a plain `fn` next to the component
  (the `format_size` pattern in `examples/file_picker.mbt`) and
  unit-test it directly.
- **Handlers in isolation** — the handler tables live on the
  `Component` value, so you can call them directly:

  ```moonbit
  test "inc: unit level" {
    let c = counter_comp()
    let inst = c.make({})
    // methods: (inst, args) => Value
    let next = (c.methods.get("inc").unwrap())(inst, [])
    assert_true(next is Obj(_))
    // input handlers: (inst, args, ctx) => Instance? — NullCtx for
    // handlers that don't dispatch
    let next2 = (c.input.get("dec").unwrap())(inst, [], @tutuca.NullCtx::{  })
    assert_true(next2 is Some(_))
  }
  ```

  Prefer the harness whenever the handler touches `ctx` — a mounted app
  gives it a real one.

## Driving a full cascade

When a message must fan out through real dispatch — a `request` that
resolves and feeds its `response`, a `send` that triggers more sends —
mount the module and use `h.send_at_root`; the harness settles the whole
cascade (including the callback-style requests) before returning:

```moonbit
test "receive.init fires the request, and the response lands" {
  // request_module takes requests? so tests inject fixtures
  let h = @harness.mount(request_module(), "RequestExample")
  h.send_at_root("init")
  // the fixture responds synchronously, so by the time the send has
  // drained the loading flag is back off and the items are in
  inspect(h.find_all(".loading").length(), content="0")
  debug_inspect(
    h.texts(".card-title"),
    content=(
      #|["Tutuca", "MoonBit", "Borges"]
    ),
  )
}

test "the error path routes to on_error_name" {
  // swapping the request map is all it takes to drive the failure case
  let h = @harness.mount(
    request_module(requests=failing_request_handlers()),
    "RequestExample",
  )
  h.click(".another") // this button requests with on_error_name="loadDataErr"
  inspect(h.text(".error"), content="network is down")
}
```

(These are condensed from `examples/request_test.mbt`.)

- Request fixtures are ordinary `RequestFn` values that call
  `respond(Ok(...))` / `respond(Err(...))` synchronously — the
  parameterized-module pattern in `examples/request.mbt`
  (`request_module(requests? = fixture_request_handlers())`).
- To exercise a handler on a nested child, click the element inside it
  (the dispatch path reconstruction is part of what you're testing) or
  call the handler directly on the child instance.
- A root-level `bubble` has no ancestor to receive it — test `bubble`
  handlers by clicking the child element that emits the bubble, or call
  them directly.
- To observe every committed transaction (message/state traces), the
  transactor exposes `Transactor::observe((ObserveRecord) -> Unit)` —
  `h.app.transactor.observe(...)` — each record carries
  `{kind, name, args, path, before, after}`.

## Custom events and file inputs

Anything the glue would map to `value` can be fired directly with
`h.fire` and a `@render.DomEvent`:

```moonbit
// a CustomEvent: detail arrives as a Map value
h.fire(
  "section",
  @render.DomEvent::new(name="emoji-click", value=Map({ "unicode": Str("😀") })),
)

// a file pick: metadata Map (Null = selection cleared)
h.fire(
  "input",
  @render.DomEvent::new(
    name="change",
    value=Map({
      "name": Str("photo.png"),
      "size": Num(2048),
      "type": Str("image/png"),
      "lastModified": Num(1700000000000),
    }),
  ),
)
```

(See `examples/new_examples_test.mbt` for both, live.)

## Designing handlers so tests stay simple

Tutuca templates resolve handler args by name (see
[core.md](./core.md) *Event Handling*). When you author a handler,
**pick the most specific named args you need; don't take the raw
event**. With named args, the handler pattern-matches a plain literal;
with `event`, it must dig through an event-shaped `Map`.

The prefix in the template picks the handler block: a leading `$`
means a `methods` entry, no prefix means an `input` handler. The same
named-arg rule applies to both.

**Bad — input handler taking the event:**

```html
<input @on.input="setCount event" />
```
```moonbit
"setCount": (inst, args, _ctx) => {
  match args {
    [Map(ev), ..] => ... // dig target.value out of an event Map
    _ => None
  }
},
```

**Good — named arg:**

```html
<input @on.input="setCount valueAsInt" />
```
```moonbit
"setCount": (inst, args, _ctx) => {
  match args {
    [Num(n), ..] => Some(inst.set("count", Num(n)))
    _ => None
  }
},
```

At test time, the "good" form is driven with one call —
`h.type_into("input", "42")` — and unit-tested with a literal —
`(c.input.get("setCount").unwrap())(inst, [Num(42)], @tutuca.NullCtx::{  })`.

The built-in named args are listed in [core.md](./core.md) *Event
Handling*. Reach for `event` only when no narrower arg fits — and note
the port's glue already narrows the classic exceptions: file inputs and
custom events deliver plain `Map` metadata as `value`.

## Worked example

Interaction tests covering a method (`$inc`), an input handler (`dec`),
and a generated mutator, mirroring `examples/counter_test.mbt`:

```moonbit
test "counter: inc and dec round-trip" {
  let h = @harness.mount(counter_module(), "Counter")
  inspect(h.text(".stat-value"), content="0")
  h.click(".btn-success") // @on.click="$inc"   (method)
  h.click(".btn-success")
  inspect(h.text(".stat-value"), content="2")
  h.click(".btn-error")   // @on.click="dec"    (input handler)
  inspect(h.text(".stat-value"), content="1")
}

test "counter: example args seed the instance" {
  let h = @harness.mount_example(
    counter_module(),
    "Counter with negative initial value",
  )
  inspect(h.text(".stat-value"), content="-5")
}

test "counter: immutability — one render per interaction" {
  let h = @harness.mount(counter_module(), "Counter")
  let before = h.render_count()
  h.click(".btn-success")
  assert_eq(h.render_count(), before + 1)
}
```

## See also

- [core.md](./core.md) — *Verifying changes*, *Event Handling*,
  *Component Skeleton*.
- [request-response.md](./request-response.md) — handler signatures for
  `bubble` / `receive` / `response`, override forms, `$unknown`.
- [cli.md](./cli.md) — the embedded CLI (`lint` / `render`) that pairs
  with `moon test` in the verification recipe.
