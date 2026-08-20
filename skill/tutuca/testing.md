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
  "marianoguerra/tutuca/core" @tutuca,
  "marianoguerra/tutuca/component",
}

import {
  "marianoguerra/tutuca/testing/harness",
  "marianoguerra/tutuca/render",   // for DomEvent in fire(...)
} for "test"
```

Import `core` under the `@tutuca` alias, not the module root. The root package
re-exports a facade (`Value`, `Ctx`, `Obj`, the intent types, the contract
reporters), so
`@tutuca.NullCtx` — needed to call an `update` fn directly — resolves only
through `core`, and that is the spelling to use wherever it is needed.

Author tests as plain `test "..." { ... }` blocks in `*_test.mbt` files:

```moonbit nocheck
// nocheck: `counter_module` is the reader's own module
test "counter: click increments" {
  let h = @harness.mount(counter_module(), "Counter")
  inspect(h.text(".stat-value"), content="0")
  h.click(".btn-success") // @on.click="inc"
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
  module's `ExampleDef`s by title (the same artifact the storybook and
  the browser hosts show, so a passing test and a working page are
  the same thing).

**Driving** — each fires a real event through the transactor and settles
before returning (`nth?` picks among matches):

> **Selectors are ONE compound selector**, not a CSS selector list: a tag, plus
> any number of `#id`, `.class` and `[attr]` qualifiers — `input.query`,
> `[data-dragtype]`, `#tab-dnd`. There is no descendant combinator, so
> `.pane .row` matches nothing (silently — it is read as one malformed token).
> To scope, pick a class the target itself carries.

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
| `h.ns_of(sel, nth?)` | the element's XML namespace (SVG / MathML checks) |
| `h.render_count()` | renders so far (assert batching) |
| `h.drive_value()` | the settled root `Value` |
| `h.styles()` | the compiled CSS text |

**Tearing down** — `h.destroy()` unmounts the app and releases its listeners.
Tests do not normally need it (each `mount` builds a fresh scope on a fresh
memdom); reach for it when one test mounts repeatedly and you want to assert
that teardown actually releases, or when asserting on `render_count()` across
remounts.

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

Run tests when the change is observable behavior — handlers, coercion,
interaction flows. For pure template/styling tweaks, `gen-views` plus
`moon check` already prove the view compiles; mount it in the storybook if
you want to look at it.

- **Interaction flows** (the default) — mount with the harness, drive
  events, assert the DOM. This exercises the template wiring, the
  dispatch path, and the handler in one go.
- **Pure logic** — extract it into a plain `fn` next to the component
  (e.g. a `format_size` helper beside a file-picker component) and
  unit-test it directly.
- **Handlers in isolation** — the typed handlers are erased behind the
  compiled `Component` (only `swap_names` and `alter_names` remain for
  introspection; everything else is recoverable from `Component::schema`),
  so there is no handler table to call into.
  For unit-level checks, keep the handler a named `fn` (or a builder
  `fn` returning the update fn) and call it directly with a state
  struct — the arguments are plain typed values, no mounting needed:

  ```moonbit
  test "update: dec at unit level" {
    let u = counter_update() // fn () -> (S, Dispatch, &Ctx) -> Update[S]
    // NullCtx for arms that don't dispatch
    match u(CounterState::{ count: 3 }, Receive("dec", []), @tutuca.NullCtx::{  }) {
      Some(s2) => assert_eq(s2.count, 2)
      None => fail("expected a state change")
    }
  }
  ```

  Prefer the harness whenever the handler touches `ctx` — a mounted app
  gives it a real one.

## Driving a full cascade

When a message must fan out through real dispatch — an `intent` that walks
its route and feeds the answer back, a `send` that triggers more sends —
mount the module and use `h.send_at_root`; the harness settles the whole
cascade (including the callback-style `IntentFn`s) before returning:

```moonbit nocheck
// nocheck: `request_module` / `failing_intent_handlers` are the reader's own
test "the init Receive arm raises the intent, and the answer lands" {
  // request_module takes intents? so tests inject fixtures
  let h = @harness.mount(request_module(), "RequestExample")
  h.send_at_root("init")
  // the fixture answers synchronously, so by the time the send has
  // drained the loading flag is back off and the items are in
  inspect(h.find_all(".loading").length(), content="0")
  debug_inspect(
    h.texts(".card-title"),
    content=(
      #|["Tutuca", "MoonBit", "Borges"]
    ),
  )
}

test "a handler that fails takes the <name>Error arm" {
  // the intent handler lives OUTSIDE the component, so swapping the map is
  // all it takes to drive the failure case
  let h = @harness.mount(
    request_module(intents=failing_intent_handlers()),
    "RequestExample",
  )
  h.click(".another") // this button names its own on_error_name
  inspect(h.text(".error"), content="network is down")
}

test "a scope that DECLINES is not a scope that failed" {
  // every handler on the route answered `Pass`, so the route ran out and
  // the sender hears <name>Unhandled — its own arm, its own sentence
  let h = @harness.mount(
    request_module(intents=declining_intent_handlers()),
    "RequestExample",
  )
  h.send_at_root("init")
  inspect(h.text(".error"), content="nothing answers `loadData`")
}
```

- Intent fixtures are ordinary `IntentFn` values that call
  `answer(Ok(...))` / `answer(Failed(...))` / `answer(Pass)`
  synchronously — the parameterized-module pattern
  (`request_module(intents? = fixture_intent_handlers())`, see *The
  ModuleDef convention* in [core.md](./core.md)). Test all three answers:
  `Pass` from every handler is what produces `<name>Unhandled`, and it is
  the path a test is likeliest to leave uncovered: nothing in the component
  raises it, only the absence of an answer does.
- To exercise a handler on a nested child, click the element inside it
  (the dispatch path reconstruction is part of what you're testing) or
  call the child's extracted update fn directly on a state value.
- A root-level `intent dyn` has no ancestor to reach — test `Intent`
  arms by clicking the child element that raises the intent, or call the
  update fn directly with an `Intent(name, args)` dispatch.
- To observe every committed transaction (message/state traces), the
  transactor exposes `Transactor::observe((ObserveRecord) -> Unit) -> () -> Unit`
  — `h.app.transactor.observe(...)`, returning an **unsubscribe** closure to
  call when you are done. Each record carries `kind`, `name`, `args`, `path`,
  `path_keys`, `target_path`, `matched`, `seq`, `before` and `after`, plus a
  `to_json()` for snapshotting a whole trace in one `inspect`.

## Custom events and file inputs

Anything the glue would map to `e.value` can be fired directly with
`h.fire` and a `@render.DomEvent`:

```moonbit nocheck
// nocheck: a fragment (a match arm or an expression), not a top-level item
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

## Designing handlers so tests stay simple

Tutuca templates resolve handler args by name (see
[events.md](./events.md#handler-arguments)). When you author a handler, **pick
the most specific named args you need**. With named args the handler
pattern-matches a plain literal, which a test can pass directly.

Every `@on` handler is written BARE and dispatches a `Receive` arm of
`update`. A leading `$` is refused there: in an event position a `$name`
and a bare name are the same dispatch, so the sigil would claim a
distinction that does not exist. `$` belongs in a value position
(`@text="$label"`), where a `compute` entry answers it.

**Bad — asking for the event object:**

```html
<input @on.input="setCount event" />
```

`event`, `target` and `ctx` are **not** handler arguments in this port: a DOM
object is not a `Value`, so each resolves to `Null` and the arm receives
`[Null, ..]`. There is nothing to dig into — the handler simply never sees the
input. Nothing reports it either; the dispatch lands and does nothing.

**Good — named arg:**

```html
<input @on.input="setCount e.valueAsInt" />
```
```moonbit nocheck
// nocheck: a fragment (a match arm or an expression), not a top-level item
Receive("setCount", [Num(n), ..]) => Some({ ..s, count: n.to_int() })
```

At test time, the "good" form is driven with one call —
`h.type_into("input", "42")` — and unit-tested with a literal —
`u(state, Receive("setCount", [Num(42)]), @tutuca.NullCtx::{  })` against
the extracted update fn.

The built-in named args are listed in
[events.md](./events.md#handler-arguments). There is always a narrower arg,
because the port's glue narrows the classic exceptions too: file inputs and
custom events deliver plain `Map` metadata as `e.value`.

## Worked example

Interaction tests covering two `update` `Receive` arms and a generated
mutator:

```moonbit nocheck
// nocheck: `counter_module` is the reader's own module
test "counter: inc and dec round-trip" {
  let h = @harness.mount(counter_module(), "Counter")
  inspect(h.text(".stat-value"), content="0")
  h.click(".btn-success") // @on.click="inc"
  h.click(".btn-success")
  inspect(h.text(".stat-value"), content="2")
  h.click(".btn-error")   // @on.click="dec"
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
- [messages-and-intents.md](./messages-and-intents.md) — the `Receive` /
  `Intent` arms, routes and legs, the three answers, catch-all arms.
- [cli.md](./cli.md) — the embedded CLI (`gen-views` / `watch`) that
  pairs with `moon test` in the verification recipe.
