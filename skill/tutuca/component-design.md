# Tutuca — Component Design

How to *shape* a feature into one or more tutuca components — responsibilities,
where state lives, which channel to reach for — before you reach for syntax. The
mechanics live elsewhere: component skeleton, fields, directives, and the
post-edit verification recipe in [core.md](./core.md); the orchestration channels
in [request-response.md](./request-response.md); dynamic bindings (`provide` /
`lookup` / `*x`) in [advanced.md](./advanced.md); task recipes in
[patterns/README.md](./patterns/README.md). This file is a router with judgment
attached — every rule points at its canonical home rather than restating it.
Read it when deciding how to split a feature into components, where a piece of
state should live, how two components should talk, or when reviewing a component
for design smells.

## Decide in this order

Walk these top-down whenever you add or reshape a component:

1. **What single responsibility is this?** If the answer has an "and" in it, split
   it into separate components.
2. **Who owns each piece of state?** The component that reads and mutates a value
   owns it. Put the field there; let others render or message it.
3. **How do these components talk?** Pick the narrowest channel that reaches the
   owner — see the ladder below.
4. **Where does the outside world cross the boundary?** Outbound I/O goes through
   `ctx.request` / `response`; inbound external events go through
   `app.send_at_root` to the root. Keep the logic inside tutuca on both sides.

## Communication decision ladder

This ladder is about *acting across* a component boundary — reaching up,
messaging a target, doing async work, or mutating state someone else owns. It is
**not** about merely *reading* a child's state: an ancestor already holds its
children as immutable field values and can read them directly in any handler
(a `@tutuca.Value` field plus `v.field(...)` / `obj_field` / `obj_item`) — no
channel needed. See [core.md](./core.md) "The value tree".

Reach for the *narrowest* channel that does the job, and only move further down
the ladder when the one above can't express it:

- **The component owns the state needed to respond** → call a **`mutate`**
  entry (or a generated mutator) on itself — stays self-contained. See
  [core.md](./core.md) *Computed values & predicates*.
- **An ancestor owns aggregate state** (a log, a selection, a total) → **`ctx.bubble`**
  up toward the root; the first ancestor with a matching handler runs. See
  [request-response.md](./request-response.md) "When to bubble".
- **You need to reach one known component** → **`ctx.send` / `receive`**, addressing a
  specific path with `ctx.at()` (defaults to self). See
  [request-response.md](./request-response.md) "When to send".
- **The work is async or host-side** (fetch, timer, storage, an external API) →
  **`ctx.request` / `response`**, which goes out to a scope-registered `RequestFn`
  and routes the result back into component state. See
  [request-response.md](./request-response.md).
- **An external event pushes *into* the app** (WebSocket, `postMessage`, …) →
  **`app.send_at_root`**, which lands the inbound event on the root. See
  [request-response.md](./request-response.md) "Integrating with the outside world".
- **A deep descendant needs a value owned far away** and nothing in between should
  know about it → **`provide` / `lookup` (`*name`)** across the tree — the last
  resort. See [advanced.md](./advanced.md).

A compact worked version of the first four (`mutate`, `bubble`, `send`/`receive`,
`request`/`response`) lives in
[patterns/coordinate-components.md](./patterns/coordinate-components.md).

## Do's & Don'ts

- **Do create single-purpose components. Don't pack multiple responsibilities
  into one.** A component that draws its own view from its own fields is the unit
  of reuse and the unit of testing. → [patterns/render-a-child-component.md](./patterns/render-a-child-component.md)

- **Don't add a `kind` / `type` field and branch the view on it. Do make one
  component per kind and render it with `<x render=".item">`.** Conditional-on-kind
  views grow into tangled `@if` chains; a component per kind keeps each view flat
  and each concern isolated. This is also why pathing into nested data is barred —
  model the nested thing as a component instead. → [core.md](./core.md) "Common
  pitfalls" (Paths are not allowed in values) and
  [patterns/render-a-child-component.md](./patterns/render-a-child-component.md).
  (When many kinds dispatch mutually — `json.mbt`'s 8 node types — keep a `reg`
  map of name → `Component` that the constructors close over.)

- **Do keep state in the component that owns and uses it, and lift it only as far
  up the tree as it needs to live. Don't thread a value through every component in
  between** (the "prop drilling" reflex) — let a child render the field it
  needs from its owner. → [patterns/share-state-across-the-tree.md](./patterns/share-state-across-the-tree.md)

- **Do read a child's state directly when an ancestor needs it for an aggregate
  decision.** A parent holds its children as immutable field values, so any
  handler can read them straight off — children don't have to
  `bubble` their state up just to be *read*. **Don't reach for a channel to read
  downward**; `bubble` / `send` are for reaching *up*, messaging a target, or
  mutating — not for inspecting state you already own. (And don't reach in to
  mutate a child around the model — that still goes through the owner returning a
  new state or `ctx.send`.) → [core.md](./core.md) "The value tree" and
  [request-response.md](./request-response.md) "When to bubble"

- **Do reach for `provide` / `lookup` (`*name`) last** — only when a deep
  descendant needs a value owned far away and nothing in between should know about
  it. Dynamic bindings couple a consumer to a producer that may not be in scope.
  → [advanced.md](./advanced.md)

- **Do pick the channel by direction (the ladder above). Don't `bubble` an event
  no ancestor consumes, and don't `send` to self when a plain function call would
  do.** `bubble` emits an *event* any ancestor can observe; `send` delivers a
  *message* to one target. → [request-response.md](./request-response.md) "When to
  bubble" / "When to send"

- **Do keep logic inside the tutuca app when integrating with the outside world.**
  Route outbound work through `ctx.request` / `response` and inbound external
  events through `app.send_at_root` to the root (which forwards deeper with
  `ctx.at()`), so handlers stay the single owner of state changes. **Don't
  overwrite the root state out of band or `addEventListener` outside the model** —
  state changed that way bypasses the immutable return-a-new-self discipline and
  is invisible to the component that owns it. → [request-response.md](./request-response.md)
  "Integrating with the outside world" (and its ⚠️ note)

- **Do handle every DOM event with tutuca's built-in `@on.` handlers — including
  custom events fired by web components.** `@on.click`, `@on.input`,
  `@on.<custom-event>` (the event `detail` surfaces as `value`) keep the event
  inside the model, so it flows through a handler and returns a new state.
  **Don't reach in from the outside with `addEventListener`** — a listener
  attached out of band mutates state the owning component can't see and bypasses
  the transactor. → [core.md](./core.md) "Event Handling" and "Web Components &
  Custom Events"

- **Do put a handler in the right bucket for its needs: `mutate` for pure
  state→state, `compute` for pure reads (both callable from value positions),
  an `update` arm when it needs `ctx`.** The split is enforced by the types
  (`mutate`/`compute` signatures have no ctx parameter), so a `$`-handler
  that wants to `ctx.request` belongs in an `Input` / `Receive` arm of
  `update`. → [core.md](./core.md) "Common pitfalls"

- **Do use inline predicates and auto-generated mutators. Don't hand-write
  `isSelected` / `select` boilerplate.** A single field plus
  `equals? .activeSection 'todo'` / `empty?` and the generated `$setActiveSection`
  / `toggleX` often *is* the whole state machine. → [core.md](./core.md)
  "Computed values & predicates" and "Field Types & Auto-generated API"

- **Do remember a rendered child gets a clean namespace.** Parent `@` bindings
  (`@each`, `@enrich-with`) don't cross a `<x render>` boundary — pass a value
  across it with `*name`, not by assuming the binding leaks in. → [advanced.md](./advanced.md)

- **Do add a decoy view when a margaui class is assembled at runtime.** The margaui
  compiler only scans constant class literals — a class built by interpolation or
  in a `compute` entry emits no CSS and renders unstyled. → the workaround in
  [margaui.md](./margaui.md) "Pitfall: assembled class names are invisible to the
  scanner", and the worked decoy view in `storybook/examples/personal_site.mbt`
  (`_margauiClasses`).

- **Do close the loop after every change** with `tutuca lint` → `moon test` →
  `tutuca render`. → [core.md](./core.md) "Verifying changes"

## Smells & refactors

- **Hand-written `isTodoSelected` / `selectTodo` handlers → predicate +
  generated setter.** Replace `@on.click="selectTodo"` / `@show="$isTodoSelected"`
  with `@on.click="$setActiveSection 'todo'"` / `@show="equals? .activeSection 'todo'"`,
  derive the current value from one field. (See `storybook/examples/composability.mbt`.)
- **A view that `@if`-branches on a `kind` field → one component per kind**, each
  rendered with `<x render>`.
- **A value passed down through three components that don't use it → move the
  state up to the nearest common owner** and let the leaf render it directly; only
  if nothing in between should know it, use `provide` / `lookup`.
- **Host code poking the root state or attaching a listener → an
  `app.send_at_root` handler on the root**, with the mutation expressed as
  `Some({ ..s, ... })` in a `Receive` arm.
- **A `mutate`/`compute` entry that fabricates dispatch (or ignores that it
  can't) → move it to an `update` arm** and let the type give it a real `ctx`.

## See also

- [core.md](./core.md) — component skeleton, fields, directives, predicates, the
  verification recipe, and the "Common pitfalls" list.
- [request-response.md](./request-response.md) — the channels in depth
  (`bubble`, `send`/`receive`, `request`/`response`, `send_at_root`) and
  integrating with the outside world.
- [advanced.md](./advanced.md) — `provide` / `lookup` / `*name` and the
  clean-namespace boundary.
- [patterns/coordinate-components.md](./patterns/coordinate-components.md),
  [patterns/share-state-across-the-tree.md](./patterns/share-state-across-the-tree.md),
  [patterns/render-a-child-component.md](./patterns/render-a-child-component.md) —
  runnable recipes for the rules above.
