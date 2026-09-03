# Tutuca — Testing

How to author component tests in the MoonBit port. There is **no
`tutuca test` command** and no ported `expect` / `describe` layer — the
JS runner and chai/jest matchers existed only because JS lacked a
capable native runner. **`moon test` is the runner**, MoonBit's built-in
assertions cover the whole jest surface, and the reusable headless
harness (`marianoguerra/tutuca/testing/harness`, imported as
`@harness`) mounts a `ModuleDef` as a live app on the in-memory DOM.
General authoring lives in [core.md](./core.md).

This file also contains the complete Tutucard scene reference. If the
deliverable is a card, read [tutucard.md](./tutucard.md) for the authoring
model, then jump to [Testing a CARD](#testing-a-card-script-typetutucatest).

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

test "a handler that fails takes the <name>Failed arm" {
  // the intent handler lives OUTSIDE the component, so swapping the map is
  // all it takes to drive the failure case
  let h = @harness.mount(
    request_module(intents=failing_intent_handlers()),
    "RequestExample",
  )
  h.click(".another") // this button names its own on_failed_name
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
- A root-level `ask dyn` has no ancestor to reach — test `Intent`
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
<input @on.input="countTo event" />
```

`event`, `target` and `ctx` are **not** handler arguments in this port: a DOM
object is not a `Value`, so each resolves to `Null` and the arm receives
`[Null, ..]`. There is nothing to dig into — the handler simply never sees the
input. Nothing reports it either; the dispatch lands and does nothing.

**Good — named arg:**

```html
<input @on.input="countTo e.valueAsInt" />
```
```moonbit nocheck
// nocheck: a fragment (a match arm or an expression), not a top-level item
Receive("countTo", [Num(n), ..]) => Next({ ..s, count: n.to_int() })
```

At test time, the "good" form is driven with one call —
`h.type_into("input", "42")` — and unit-tested with a literal —
`u(state, Receive("countTo", [Num(42)]), @tutuca.NullCtx::{  })` against
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

## Testing a CARD: `<script type="tutuca/test">`

Everything above is the ahead-of-time path: a view file, `gen-views`, a
`ModuleDef`, and `moon test` over `@harness`. A **card** is the other
thing a `.html` file can be — one file the browser compiles to a
`tutuca:component@0.12.0` wasm module with no MoonBit toolchain on the
page. There is no `moon test` there and no MoonBit to write a test in,
so a card declares its tests as a **fifth block**, in JSON, beside its
schema and its handlers.

Use this when the file is a card. Use `moon test` + `@harness` when it
is a view file compiled by `gen-views`. The block is inert on the
ahead-of-time path — `gen-views` ignores it, exactly as it ignores
`<script type="tutuca/wax">` — so a file carrying one is a file with a
block that path skips.

### The block

```html
<script type="tutuca/spec">
  state Counter {
    count: Int, step: Int
    property { label: String { get } }
  }
</script>

<script type="tutuca/script">
  receive init { .step = 1 }
  receive inc  { .count += .step }
  get label { $'the count is {state.count}' }
</script>

<script type="tutuca/test">
{
  "two clicks add two": {
    "steps": [
      { "send": "init" },
      { "click": "button.inc" },
      { "click": "button.inc" },
      { "expect": "text",  "at": "output", "is": "2" },
      { "expect": "text",  "at": "p", "is": "the count is 2" },
      { "expect": "state", "at": ".count", "is": 2 }
    ]
  }
}
</script>

<template id="Counter">
  <div>
    <button class="inc" @on.click="inc">+</button>
    <output @text=".count"></output>
    <p @text="$label"></p>
  </div>
</template>
```

One object of **named scenes**, the same shape `tutuca/fixtures` has. Each
scene is `{ "steps": [ … ] }` plus four optional keys:

| key | means |
| --- | --- |
| `"component": "TodoItem"` | which component to mount. Optional for a card with one; required for a card with several |
| `"init": "fresh"` | start from a `tutuca/fixtures` fixture |
| `"args": { "count": 3 }` | start from these field values (written over the fixture, if there is one) |
| `"intents": { … }` | answer the intents this card raises — see below |
| `"raw": true` | keep the renderer's `data-cid` / `§…§` bookkeeping in the reported HTML |

**`send "init"` is usually the first step.** tutuca has no lifecycle:
`receive init` runs because a HOST dispatches it, and in a scene the
scene is the host.

### The verbs

One key per step names the verb and carries the selector. `"nth"` picks
among matches and is `0` when unwritten.

| step | does |
| --- | --- |
| `{ "click": "button.inc" }` | click it |
| `{ "click": "li.todo", "nth": 2 }` | click the third match |
| `{ "type": "input.draft", "value": "milk" }` | an `input` event carrying the text |
| `{ "key": "input.draft", "is": "Enter" }` | a `keydown` |
| `{ "check": "input.done", "is": true }` | toggle a checkbox |
| `{ "fire": "section", "event": "emoji-click", "value": { "u": "😀" } }` | any event, custom ones included |
| `{ "drag": "li.todo", "from": 0, "to": 2 }` | a full drag gesture |
| `{ "send": "init", "args": [1, "two"] }` | a host dispatch at the root |

A step naming two verbs is refused: an object's keys have no order, so
`{ "click": …, "type": … }` does not say which happens first.

### The readers

Reads are all spelled `expect`, naming what to read.

| step | reads |
| --- | --- |
| `{ "expect": "text", "at": "output", "is": "2" }` | text content, whitespace collapsed |
| `{ "expect": "texts", "at": "li.todo", "is": ["milk", "eggs"] }` | every match's text |
| `{ "expect": "attr", "at": "a.home", "name": "href", "is": "/here" }` | an attribute |
| `{ "expect": "prop", "at": "input", "name": "value", "is": "hi" }` | a **property** — form state (`value`, `checked`, `disabled`) is set as one, not as an attribute |
| `{ "expect": "value", "at": "input.draft", "is": "" }` | an input's value |
| `{ "expect": "checked", "at": "input.done", "is": true }` | a checkbox |
| `{ "expect": "count", "at": "li.todo", "is": 3 }` | how many match |
| `{ "expect": "state", "at": ".count", "is": 2 }` | the settled state at a place |
| `{ "expect": "state", "is": { "count": 2, "step": 1 } }` | …or all of it |
| `{ "expect": "html", "contains": "class=\"done\"" }` | the rendered markup |
| `{ "expect": "renders", "is": 1 }` | renders so far — assert batching |
| `{ "expect": "log", "contains": "does not hold" }` | what the card has SAID since you last asked |
| `{ "expect": "refused", "is": [] }` | what the HOST refused since you last asked |

`"at"` for `state` is a dotted place: `.count`, `.rows[0].label`,
`.byId['a'].n`. A bare key (`.rows[a]`) is refused rather than guessed
at, because the block language already has a spelling for "the key held
in `.a`".

`"contains"` works on `text` and `html` only. Everywhere else `"is"`
says what you mean exactly.

### Assert on `log`, not just on the DOM

Clicking a button whose `requires` declines changes nothing. So does
clicking a selector that matches nothing. **From the DOM they are
identical**, which means a scene written against a typo passes.

For a card, the thing that tells them apart is `log`. A `requires`, an
`ensures` or an `invariant` that does not hold makes the transition not
happen, and the card says so through `control.log` — carrying the rule's
own `format` sentence, evaluated over the state that was rejected:

```html
<script type="tutuca/spec">
  state {
    n : Int

    pred room
      format $'the counter is full at {.n}' { .n < 3 }
  }
</script>

<script type="tutuca/script">
  receive bump requires room { .n += 1 }
</script>

<script type="tutuca/test">
{
  "the guard stops it at three": { "steps": [
    { "click": "button" }, { "click": "button" }, { "click": "button" },
    { "expect": "text", "at": "output", "is": "3" },
    { "click": "button" },
    { "expect": "text", "at": "output", "is": "3" },
    { "expect": "log", "contains": "precondition `room` does not hold" }
  ] },
  "and says nothing while it holds": { "steps": [
    { "click": "button" },
    { "expect": "log", "is": [] }
  ] }
}
</script>
```

**`refused` is the HOST's channel, and for a card it is usually empty.**
That is not a gap to work around — it is what the two sides mean. A host
component that no arm answers raises a structured `Refusal`; a compiled
guest is asked about every `receive` by name and answers `unhandled`
instead, so the host has nothing to refuse and falls back to the field
mutator. Reach for `refused` when driving a **module** through
`@harness`, and for `log` when driving a **card**.

Both accumulate until read: `{ "expect": "log" }` answers everything
since the last time a scene asked, so the check does not have to sit in
the step immediately after the click. Each also appears whole in the
scene's report (`log`, `refusals`), so a rule that fired unexpectedly is
visible even in a scene that never mentions it.

### Selectors are ONE compound selector

A tag plus any number of `#id`, `.class` and `[attr]` qualifiers —
`input.draft`, `[data-dragtype]`, `#tab-dnd`. **There is no descendant
combinator and no list.** `.pane .row` is refused when the block is
read, rather than silently matching nothing at run time. To scope, pick
a class the target itself carries.

### Leave `is` out to RECORD

An expectation with no answer never fails: the runner reads it and hands
the answer back. Write the drive first, look at what the component
actually did, then keep the answers you meant.

```json
{ "what does it even do": { "steps": [
  { "type": "input.draft", "value": "milk" },
  { "click": "button.add" },
  { "expect": "texts", "at": "li.todo" },
  { "expect": "state" }
] } }
```

### What comes back

Assertions are optional; the read-back is not. **A scene with no
`expect` at all is a drive**, and it still answers everything — which is
the shape to write when you have just generated a card and want to see
it work:

```json
{
  "ok": false,
  "ran": 2,
  "failed": 1,
  "scenes": {
    "two clicks add two": {
      "ok": true,
      "component": "Counter",
      "html": "<div><button class=\"inc\">+</button><output>2</output>…</div>",
      "state": { "count": 2, "step": 1 },
      "styles": "…",
      "activity": [ { "kind": "receive", "name": "inc", … } ],
      "log": [],
      "refusals": [],
      "steps": [
        { "at": 0, "ok": true },
        { "at": 3, "ok": true, "got": "2", "want": "2" }
      ]
    }
  }
}
```

`html` is **cleaned**: the renderer's `data-cid` / `data-eid` stamps and
its `§…§` boundary comments come off, so what you read is the markup and
a snapshot does not move because a component id did. `"raw": true` on
the scene keeps them, for debugging the renderer rather than the card.

A scene that could not be mounted at all carries an `error` instead —
and the other scenes still run, so one bad `"component"` does not hide
nine working scenes.

### A card may declare more than one component

One file, several components — the same device a view file has always
used, and a `TodoItem` belongs beside the `TodoList` that renders it
rather than in a file of its own:

```html
<script type="tutuca/spec">
  state Board { title: String, tally: Int }
  state Row   { label: String, done: Bool }
</script>

<script type="tutuca/script" for="Board">
  receive bump { .tally += 1 }
  compute caption { $'{.title}: {.tally}' }
</script>

<script type="tutuca/script" for="Row">
  receive toggle { .done = not .done }
  compute caption { if .done { 'done' } else { .label } }
</script>

<template id="Board:main"> … </template>
<template id="Row:main">   … </template>
```

- One `state` per component in the **one** spec block.
- One `<script type="tutuca/script" for="Comp">` each. A bare block with
  no `for=` is only unambiguous when the file declares one component; with
  several, name every block.
- `<template id="Comp:view">`, or `<template id="Comp">` for its `main`.
- The two are genuinely separate: separate schemas (a `Row` has no
  `.tally`), separate dispatch (a `Board` answers `unhandled` to
  `toggle`), and the same name may mean different things in each.

**The root** — what a host mounts when told no other name — is the first
component in the file. `data-root` on a `<template>` overrides that, for
the file where the order you want to read is not the order you want
mounted:

    <template id="Row:main"> … </template>
    <template id="Board:main" data-root> … </template>

A scene names the component it drives, so one block tests both:

```json
{
  "the board counts": {
    "component": "Board", "args": { "title": "Sprint" },
    "steps": [
      { "click": "button.bump" },
      { "expect": "text", "at": "h1.title", "is": "Sprint: 1" }
    ]
  },
  "a row strikes itself through": {
    "component": "Row", "args": { "label": "write it" },
    "steps": [
      { "click": "li.row" },
      { "expect": "text", "at": "li.row", "is": "done" }
    ]
  }
}
```

A component may hold another as a **slot** — `focus: Row` names the
sibling — and such a field carries a real child instance across the
boundary: a scene reads an empty one as `null`, and a filled one is the
child, not a number.

A handler **builds** one with `new <Component>` naming a sibling — the
same `new` / `cur` shape a declared `record` uses:

```
receive add requires typed {
  new Todo
  cur.text = .draft
  cur.done = false
  .items.push cur
  .draft = ''
}
```

Nothing is built at the `new`: it opens an argument map for the sibling,
`cur.text` fills it in, and the child is made when `cur` is READ — the
push. Reading it twice does not make two.

> **A card cannot READ through a child.** `.items[0].text` is refused when the
> card compiles: the instance belongs to the host and the card holds a token.
> Send it a message instead — which is what clicking the row does.
>
> Writing ONE member of a child it holds directly is different, and allowed:
> `.child.body = 'x'` is addressed at the child's position rather than read
> through, and it goes through the PUBLIC door — what a child lets a holder
> write is what its `property { … }` declares writable. A field with no
> property beside it is private, and stays private however it is held.

### Running them

**In the card playground**, the Tests pane runs every scene on each
recompile and lists what disagreed, step by step. It drives the module
already on the page, so it is neither a second compile nor a disturbance
to the card in the preview beside it.

**Headless**, through the card runtime's own `card-wasm.js` — no
browser, no server, no `moon`:

```js
import { readFileSync } from "node:fs";
// The card runtime is a classic script that installs globalThis.__tutucard.
(0, eval)(readFileSync("tutucard.js", "utf8"));
const { driveCard } = await import("./card-wasm.js");

const report = await driveCard(readFileSync("counter.html", "utf8"), "Counter");
for (const [name, scene] of Object.entries(report.scenes)) {
  if (scene.ok) continue;
  for (const step of scene.steps) {
    if (!step.ok) console.error(`${name} step ${step.at}: ${step.why}`);
  }
  console.error(scene.html);
}
```

Pass `{ scenes: "<json>" }` to drive a card that declares **no** test
block — the situation anything that has just written one is in.

**From a page**, the same `driveCard`. It mounts on the in-memory DOM
and never touches `document`, so the call that answers under `node`
answers in a tab, and an agent driving the browser reads the same
report:

```js
const report = await driveCard(source, "Counter", { scenes: sceneJson });
```

Underneath it is `__tutucard.drive(key, manifest, source, scenes)` — the
card runtime's ninth entry point, beside `check` / `compile` /
`mountCompiled`. It is synchronous and answers the report as a JSON
string; `""` for `scenes` means "the card's own block". Call it directly
only when a compiled card is **already instantiated** under `key`, which
is the playground's case: the preview's `mountCard` left the guest under
`"preview"` and handed back the manifest from the same compile, so the
Tests pane asks that guest to build some more instances rather than
compiling a second time. Each scene still gets its own scope and its own
memdom, so nothing it drives touches the card in the preview beside it.

```js
// only where a card is already mounted; `manifest` is that mount's own
const out = JSON.parse(
  globalThis.__tutucard.drive("preview", JSON.stringify(manifest), source, ""),
);
```

Two things it will not forgive:

- **A `key` with nothing under it does not get one.** The answer is
  `{ "ok": false, "error": "no compiled card is instantiated on this page" }`,
  not a card mounted on your behalf. Instantiation is
  `WebAssembly.instantiate`, which answers a promise, and a promise is
  the one thing this boundary cannot carry — which is why `driveCard` is
  the async one and this is not.
- **The manifest must come from the compile the module came from.** A
  manifest's field list is the order `get-field` answers in, so one
  paired with a different module is a bundle whose halves disagree.

So reach for `__tutucard.drive` when you already hold both — a mounted
guest and its own manifest — and for `driveCard` everywhere else. It is
check, compile, instantiate and drive in one call, and doing it by hand
is those same four steps.

### Intents answer synchronously

A card raising `intent lex 'rows'` is asking a host for something, and
in a scene the scene is the host:

```json
{ "the list loads": { "intents": {
    "rows": { "ok": [{ "title": "Tutuca" }] },
    "boom": { "failed": "network is down" },
    "shrug": "pass"
  },
  "steps": [
    { "send": "init" },
    { "expect": "count", "at": "li.row", "is": 1 }
  ] } }
```

The three answers an intent has, and no fourth. **A name with no fixture
answers nothing at all** — the route runs out, nobody claims it, and the
card hears `<name>Unhandled`. That is a different sentence from a
failure's and the path a test is likeliest to leave uncovered: nothing
in a card raises it, only the absence of an answer does.

They answer at once, not late. A page's fixtures answer on a timer
because a card author has to write for a loading state; a runner has
nothing to wait with.

## See also

- [core.md](./core.md) — *Verifying changes*, *Event Handling*,
  *Component Skeleton*.
- [messages-and-intents.md](./messages-and-intents.md) — the `Receive` /
  `Intent` arms, routes and legs, the three answers, catch-all arms.
- [cli.md](./cli.md) — the embedded CLI (`gen-views` / `watch`) that
  pairs with `moon test` in the verification recipe.
