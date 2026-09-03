# Tutuca — Core (MoonBit port)

Tutuca is an immutable-state web framework: a component is a plain typed
**state struct** plus properties and handler buckets — direct property actions,
HTML-template `view`s with `@`-prefixed directives, and one
`update` dispatch match for orchestration. This is the **MoonBit port**
(`marianoguerra/tutuca`): the template language is identical to the JS
original, but everything around the views — component definition, state,
handlers, testing, CLI — is MoonBit. Read this file when authoring or
reviewing the **compiled MoonBit path**: `@component.component(...)`
definitions, generated view modules, `ModuleDef` wiring, view templates,
macros, or the embedded `tutuca` CLI. For a single-file Tutucard, begin with
[tutucard.md](./tutucard.md) and return here only for the template notation it
links to.

> Load the topic files only when the task touches them (the routing
> table in [SKILL.md](./SKILL.md) has the full descriptions):
> [schema.md](./schema.md) · [events.md](./events.md) ·
> [iteration.md](./iteration.md) · [macros.md](./macros.md) ·
> [styles.md](./styles.md) · [messages-and-intents.md](./messages-and-intents.md) ·
> [component-design.md](./component-design.md) · [testing.md](./testing.md) ·
> [cli.md](./cli.md) · [semantics.md](./semantics.md) ·
> [advanced.md](./advanced.md) · [margaui.md](./margaui.md) ·
> [playground.md](./playground.md) · [tutucard.md](./tutucard.md) ·
> [patterns/README.md](./patterns/README.md).

## Verifying changes

After editing a tutuca module, run these checks before declaring the
edit done. This is an ahead-of-time port, so the first two are the
compiler. The view rules still run, inside `gen`; what does not
exist is a separate `tutuca lint` command to invoke them with.

1. **Regenerate the views, if you edited an `.html`** — the generator is
   the view checker: a view that would emit a parse issue fails
   generation instead of shipping.

        tutuca gen src/button.html --name Button
        tutuca watch src/                 # …or leave this running

2. **Type-check** — this is the lint step. The generated module gives
   `update` a `ButtonMsg` to match on and `button_fields` for the fields
   the view reads, so an undefined field, an unimplemented `$`-method or
   an `@on` handler nothing handles is a **build error**:

        moon check
        moon check --target native        # and js; each surfaces its own

3. **Test component behavior** — when the edit changes handlers,
   field coercion, or interaction flows (anything observable beyond a
   single static render), run the test suite:

        moon test                       # the package's test blocks
        moon test -p <package>          # one package
        moon test --update              # refresh inspect/debug_inspect snapshots

   There is **no `tutuca test` command** — `moon test` is the runner, and
   component tests are plain `test "..." { ... }` blocks that mount the
   module on the in-memory DOM via the
   `marianoguerra/tutuca/testing/harness` package and assert with
   MoonBit's built-ins. A test that mounts the example covering your
   change is what proves the component mounts, and it lets you assert
   what it rendered. Authoring
   patterns in [testing.md](./testing.md).

4. **Look at it, if it is visual** — mount the module in a browser host, or
   put it in a gallery: `tutuca new-storybook` scaffolds one, and every
   example your modules declare becomes a story
   ([storybook.md](./storybook.md)).

Full reference: [cli.md](./cli.md).

The tutuca CLI only catches tutuca-specific issues. For general MoonBit
problems, pair it with the `moon` toolchain: `moon check` (all targets),
`moon fmt`, and `moon info` to regenerate the `.mbti` interface files.

## Common pitfalls

- **`.name` reads a property; `$name args…` calls a method.** A field is an
  implicit private property, and an explicit property of the same name wins.
  A zero-argument derivation is a read-only property and is still `.label`.
  In an event position, `.name = value` and `.items.removeAt key` are property
  actions; a bare name is a semantic handler.
- **Semantic event handlers go in `update`.** A view names one bare. A
  parameterized `compute` entry is pure — `(s, args, stack) => Value` — and
  exists for `$` calls in value positions. The
  `update` fn — `(s, msg, ctx) => Update[S]` — gets the `&Ctx` and can
  `ctx.send` / `ctx.intent`. Every `@on` handler is written bare,
  whichever bucket serves it; `$` is for value positions only.
- **`update` returns `Update[S]`, which has three cases.** `Next(s2)`
  commits a successor. `Unchanged` says "my arm ran and the state stays as
  it is" — nothing further is tried, which is how a handler VETOES a write.
  `Unhandled` says "no arm claimed this name". Property actions do not enter
  this dispatch. The match must be total — always end with
  `_ => Unhandled`.

  The three are distinct on purpose: a handled no-op is not an unknown name.
- **The bucket enums are closed and view-driven.** With generated views,
  `compute` / `when` / `enrich` / … are functions over enums whose cases
  come from the names the views reference. You cannot pre-declare a
  handler the view doesn't call yet — the constructor doesn't exist and
  the match won't compile. Add the name to the view first, regenerate,
  then write the handler.
- **Paths are not allowed in values.** `.foo` resolves a single property on
  the state — `@text=".foo.bar"`, `:value=".user.name"`,
  `@show=".item.isOpen"` all fail. To reach into nested data: render the
  child as a component (`<x render=".foo">` then `@text=".bar"` inside),
  add a read-only property (read the nested value off a `@tutuca.Value`
  field with `v.field("name")`), or use `@enrich-with`
  for scope-level derivation. The one exception: a **binding** may read
  exactly one **binding member** — `@text="@value.title"` inside `@each`
  works (any `@`-binding, one level only; `@value.a.b` fails generation
  as `BINDING_MEMBER_TOO_DEEP`, and render targets still reject it).
- **Use `@bind=".field"` only for checked scalar form bindings.** It requires a
  state schema and supports `String` text controls/single selects, `Bool`
  checkboxes, integer number/range inputs, and `Double` number/range inputs.
  The generator rejects dynamic input types, nested/loop targets and competing
  attributes or event handlers; invalid numeric edits leave state unchanged.
  See [events.md](./events.md#two-way-scalar-fields-with-bind) for the matrix.
- **`make()` / example args are coerced by shape, silently.** Each arg is
  coerced through the field's inferred spec: a value whose shape doesn't
  match the field kind **falls back to the default** (no error). The
  value layer's one number type is `Num(Double)`; an `Int` state field
  that could receive a fractional `Num` at runtime breaks decode —
  declare it `Double` and `.to_int()` at use.
- **Multiple `@if.<attr>` on one element.** Every `@then`/`@else` after
  the first must name the attr (`@then.title`, `@else.title`) — HTML
  disallows duplicate attrs, so the second `@then=` is dropped silently.
- **Bare unquoted multi-word strings return `null`.** Either quote
  (`'flex gap-3'`) or use a `$'…'` string template (`$'flex gap-3 {.color}'`).
- **`<x>` is stripped inside `<select>` / `<table>` / `<tr>`.** Use the
  `@x` pseudo-x trick (see [advanced.md](./advanced.md)).
- **`Receive("init", _)` is a convention, not a lifecycle hook.** Nothing
  dispatches it automatically — the host calls `app.send_at_root("init")`
  or another handler sends it.
- **Example `args` hold instance Values, not plain data.** A
  component-typed slot in an `ExampleDef`'s `args` (or in a `List` field)
  must be built with `comp.make({...})` — which returns the instance as a
  `@tutuca.Value` directly — not a bare `Map`.
- **Views must contain a root element.** A leading newline before the
  first element is trimmed, but a whitespace-only `<template>` renders blank
  silently.
- **Macro registry keys are lowercased.** `<x:Card>` becomes `<x:card>` —
  see [macros.md](./macros.md).

## Bootstrap

A component is declared in an `.html` view file — its state, its templates,
its styles — and `tutuca gen` compiles that into a MoonBit module beside
it. What you write is the code no generator can: the handlers.

`counter.html`:

```html
<script type="tutuca/spec">
  state Counter { count: Int }
</script>

<template>
  <button @on.click="inc" @text=".count"></button>
</template>
```

`counter.mbt`:

```moonbit
///|
fn counter_comp() -> @component.Component {
  // `counter_component` is generated: it passes the name, the compiled views,
  // the styles, the schema and the state <-> Value codec. `CounterState` and
  // `CounterMsg` are generated too.
  counter_component(update=(s, msg, _ctx) => match CounterMsg::from_dispatch(msg) {
    Some(Inc) => Next({ count: s.count + 1 })
    Some(Unknown(_, _)) | None => Unhandled
  })
}

pub fn counter_module() -> @component.ModuleDef {
  @component.ModuleDef::new(name="counter", components=[counter_comp()], examples=[
    { component: "Counter", title: "Basic Counter", args: {}, view: None },
  ])
}
```

Then regenerate (`tutuca gen counter.html --name Counter`) and run
`moon fmt`, so the checked-in pair stays reproducible.

Adding `@on.click="del"` to the view and regenerating makes that match
non-exhaustive: a compile error naming `Some(Del)`, where a string-keyed
handler map would have left a name nobody answers.

The same `ModuleDef` value drives three hosts:

- **Headless tests** — `@harness.mount(counter_module(), "Counter")` on
  the in-memory DOM (see [testing.md](./testing.md)).
- **The browser** (js or wasm-gc target) — mount via
  `@app.App::from_module` plus the glue package
  (`marianoguerra/tutuca/app/browser` as `@glue`,
  `marianoguerra/tutuca/vdom/browser` as `@bdom`):

  ```moonbit
  fn main {
    let doc = @dom.window().document()
    guard doc.getElementById("app") is Some(root_el) else { return }
    let app = try! @app.App::from_module(
      counter_module(),
      "Counter", // root component name; args? seeds the root instance
      @bdom.BrowserNode::from_element(root_el),
      @bdom.opts_for(doc),
    )
    @glue.install(app) // wire DOM events into the transactor
    @glue.install_styles(app, @bdom.BrowserNode::from_document(doc))
    // tutuca has no lifecycle: the HOST dispatches `init` if the root wants one
    app.send_at_root("init") |> ignore
  }
  ```

- **The storybook gallery** — `@sb.stories_of_modules([...])` projects one
  story per declared example and `@sbw.mount` puts the whole set on a page as
  one app, each story in its own child scope. See
  [storybook.md](./storybook.md), and
  [patterns/add-an-example.md](./patterns/add-an-example.md) for the example
  itself.

### Observing and tearing down an app

The mounted `App` is what a host reaches for when it needs to persist state, log
transactions, or remount:

| Call | Gives |
| ---- | ----- |
| `app.root_value()` | the current root `Value` — snapshot it to persist |
| `app.render_count` | renders so far (assert batching) |
| `app.event_names()` | every event name the compiled views listen for |
| `app.transactor.observe(fn)` | every committed transaction; returns an **unsubscribe** closure |
| `app.destroy()` | unmount and release listeners |
| `app.start()` | (re)start rendering |

`observe` is the hook for persistence and logging — there is no `onChange`
callback on the app itself. Each `ObserveRecord` carries `kind`, `name`, `args`,
`path`, `path_keys`, `target_path`, `matched`, `seq`, `before`, `after` and a
`to_json()`. Mounting in a loop without `destroy()` leaks listeners.

## Mental model

Tutuca rests on three invariants: the application state is a single
immutable root value; the view is a pure function of it; every handler
takes the old state and returns a new state. The transactor swaps the
root atomically. Structure sharing, cheap change detection, and the
entire dispatch model fall out of these three properties.

**The value tree.** State is the `@tutuca.Value` enum; component
instances are `Obj` values wrapping a typed instance — the component's
state struct is the source of truth, encoded to a fields map for the
render/path seams. Children live in fields — a `List` of `Item`
instances, a `Map` of `User`s, a scalar `count`. "Updating a deep child"
means producing a new root that shares structure with the old one along
the unchanged spine. Every instance reports which component it belongs
to through `Obj::component_id()`, so the runtime never needs runtime
type checks — it asks the value what it is.

Because children are just immutable values held in fields, **handlers
have full read access to nested child state** — a parent that holds
child instances in a `@tutuca.Value` (or `Array[@tutuca.Value]`) field
reads them with the value coercers (`v.field("name")`, `v.list()`) or
`Obj::member`. Reading *down* the tree is direct and needs no
channel: an ancestor that owns a list already holds every child's state
and can read it for an aggregate decision. The single-level `.field`
restriction (no `.foo.bar`) is a **view-template** rule, not a MoonBit
one — it's why a derivation like "the user's name" is written as a
`compute` entry (see *Computed values & predicates*). Reading is free;
**mutating** a child still flows through the model — the owner returns
a new state (`setInItemsAt`, …) or messages the child with `ctx.send`.
Don't reach in to mutate around the handler discipline, and prefer
letting a child own and render its own state — reach down to read only
when the ancestor genuinely needs it. See
[component-design.md](./component-design.md) and "When to send" in
[messages-and-intents.md](./messages-and-intents.md).

**Stack: frames vs scopes.** As the renderer walks the AST it pushes
bind frames. A *frame* is a barrier: name lookups (`@x`) stop at it,
so a child component view sees a clean namespace. A *scope* is
transparent: iteration `key` / `value` and `@enrich-with` binds layer
onto the surrounding frame and remain visible to handlers attached to
the same iteration. `it` (the target of `.field` reads and `$handler`
calls) is set on both.

| pushed by                           | kind  | shape                                |
| ----------------------------------- | ----- | ------------------------------------ |
| `<x render=".f">` / `<x render-it>` | frame | `it` = child, fresh binds            |
| `<x render-each>` per iter          | frame | `it` = item, binds `{ key }`         |
| `<div @each>` per iter              | scope | `it` = item, binds `{ key, value }`  |
| `<div @enrich-with=…>` (no `@each`) | scope | `it` unchanged, binds = handler result |

For full mechanics see [iteration.md](./iteration.md).
This is why a handler attached to `<div @each>` runs against the
*parent* component (the scope is transparent — the surrounding frame
still owns dispatch), while one inside `<x render-it>` runs against
the *item* (render-it pushed a fresh frame for the child).

**Paths, not references.** The DOM is the only thing that survives
between render and click, so the renderer leaves breadcrumbs:
`data-cid` / `data-nid` / `data-eid` on rendered elements, and `§…§`
HTML comments adjacent to iteration entries. On a DOM event the
runtime walks from the target up to the root, reads those breadcrumbs,
and rebuilds a *positional* path — an array of `Step`s from the root
to the value the handler should run against. The same path is reused
verbatim for `ctx.send` and for `ctx.intent` and its answer: because
it's positional rather than a captured reference, an async answer
survives intervening transactions that rebuild the root.
"The right slot" is exact for named fields and for map entries by key
(seq-access keys like `.sheets[.selId]` are *pinned* to their
dispatch-time value by default); a bare list **index** still slides if the
list reordered. See [messages-and-intents.md](./messages-and-intents.md) for the
dispatch APIs and [semantics.md](./semantics.md) for the path/transaction
model and key pinning.

**Why the render buckets are separate.** The `when` / `enrich` /
`bind_with` / `loop_with` buckets are pure, evaluated on every
render, and produce filter decisions and binds (no state change) — like
`compute` entries. `update` is transactional and produces a new state.
Same name-resolution mechanism from the template, different contracts —
keep them separate.

## Notation Reference

Views are name-based: there is no arithmetic expression syntax in
values, and no Vue- or Mustache-style `{{ … }}` placeholders. Every
value slot — conditions (`@show`, `@if`), iteration (`@each`,
`render-each`, `@when`), enrichment (`@enrich-with`, `@loop-with`), template
expansion (`{…}`, `:attr`, `@text`) — names a field, handler, or macro
defined on the component (or registered with the scope). Logic lives in
`update` / `compute` and the render buckets (`when` /
`enrich` / `bind_with` / `loop_with`) and is referenced by name; the
template itself only routes data and events.

The one exception is **conditional slots** (`@show`, `@hide`,
`@if.<attr>`), which take a whole **expression** — and it is the *same*
expression language a `pred` or a `compute` body is written in, with the
same vocabulary and the same grammar. There is one language, not two that
resemble each other; see [schema.md](./schema.md#the-reading-vocabulary)
for the full table, which serves both halves.

```html
<div @show="not .open">…</div>
<div @show="not (empty? .kind)">…</div>
<div @show=".kind is 'a'">…</div>
<div @show="(len .items) is 1">…</div>
<div @show=".open and .ready">…</div>
<div @show="(.n > 0) and .open">…</div>
```

Application is **juxtaposition** (`empty? .items`, `contains (lower .title) 'x'`)
and **parentheses are required wherever precedence would otherwise be
implicit** — so `(.n > 0) and .open` rather than `.n > 0 and .open`, and the
error message names the parentheses to add. There is no precedence table to
remember and none to get wrong.

A conditional slot also accepts the plain value forms `@text` does — a property
(`@show=".isOpen"`), or a
loop/scope `@binding` (`@show="@isSelected"`, `@hide="@hasDesc"`) — read as a
boolean. String literals are `'detail'`, or `'two words'` for one with spaces
(escape an interior quote as `\'`).

Four things a *body* can write and a slot cannot, each refused by name: a
nested read (`.a.b` — render the child as a component, or name it with a
`compute`), an `if` expression (`@show`/`@hide` **are** the choice; a value
that picks between two is `@if.<attr>` with `@then`/`@else`), arithmetic, and a
bare parameter.

`^macro` and `host.config` are ordinary operands here: `@hide="empty? ^label"`,
`@show="not ^collapsed"`, `@show="host.origin is 'x'"`. They are substituted as
the value is read, so a `^name` still has to expand to a single token. Going
the other way, a `<script type="tutuca/script">` block cannot write either one
— a block is parsed once for the component, with no macro call site and no host
around it — so read the value in the view and pass it in.

| Prefix   | Means                                     | Example               |
| -------- | ----------------------------------------- | --------------------- |
| `.x`     | property on the component (explicit property before implicit field property) | `.count`, `.title` |
| `$x`     | a parameterized `compute` call, in a VALUE position only | `$format .value` |
| `@x`     | local binding (loop / scope)              | `@key`, `@value`      |
| `^x`     | macro parameter                           | `^label`              |
| `*x`     | dynamic binding — see [advanced.md](./advanced.md) | `*theme`          |
| `Name`   | component type (PascalCase) — parses, but is in NO value slot: ask for one with `ctx.make("Name", …)` | `Item`, `JsonNull` |
| `name`   | bare identifier — meaning depends on slot | `dec`, `value`        |
| `'str'`  | string literal                            | `'btn btn-success'`   |
| `$'…'`   | string template (`{expr}` interpolation)  | `$'Hi {.name}'`       |
| `.s[.k]` | sequence/map item access                  | `.byKey[.currentKey]` |
| `pred? .x` | an expression in a conditional slot | `empty? .items`, `.view is 'detail'`, `not .open` |

`.x` and `$x` are not interchangeable: `.x` reads a property, while `$x`
calls a method. `gen` reports a mismatch and names the prefix to use.

A bare `name` (no prefix) in `@on.<event>="<handler> <arg> <arg>..."`
resolves by slot:

- **First slot** — a semantic event name dispatched as `Receive(name, args)`
  to the `update` fn. A property action instead begins with `.`, for example
  `.query = e.value` or `.items.removeAt @key`.
- **Subsequent slots** — built-in handler argument name (full list in
  *Event Handling*); anything else triggers a lint warning.

```html
<button @on.click="onAddItem e.value">+</button>
<!--                ↑ handler  ↑ arg -->
```

Handler args written in the template arrive in the MoonBit handler's
`args : Array[Value]` in order. The `&Ctx` is **not** an args entry —
the `update` fn receives it as its explicit third parameter, so don't
list `ctx` in the template.

> Port note: the JS docs pass a component **type** as a handler arg
> (`@on.click="onAddItem Item"`). In MoonBit the value language has no
> component-reference value — instead the handler **captures** the
> `Component` in its closure and the view just calls `onAddItem`
> (worked version in [patterns/todo-list.md](./patterns/todo-list.md)).

## Quoting & String Literals

A string template is written `$'…'` — a single-quoted run with a leading
`$`, holding `{expr}` interpolations. `:attr=` and other text slots accept
`$'…'` templates; `@if`, `@each`, `<x render=>` do not.

| Form                | Example                   | Where it works                                   |
| ------------------- | ------------------------- | ------------------------------------------------ |
| `'string'`          | `@then="'btn ok'"`        | anywhere a value is allowed                      |
| `$'…'` template     | `:class="$'btn {.kind}'"` | `:attr=`, `@text`, `@title`, macro dynamic attrs |
| Bare without quotes | `flex gap-3`              | **never** — returns `null`                       |
| Bare identifier     | `dec`, `value`            | name slots only (handler/arg, not as a value)    |

```html
<!-- ✅ -->
<p :class="'flex gap-3'">x</p>
<p :class="$'flex {.color}'">x</p>         <!-- $'…' string template -->

<!-- ❌ -->
<p :class="flex gap-3">x</p>               <!-- null: no quotes -->
<p :class="flex {.color}">x</p>            <!-- null: unquoted {…} is not a template -->
<x render="'foo bar'"></x>                 <!-- @render rejects string templates -->
```

MoonBit note: inside `#|` raw strings, template quoting is written as-is
(`@on.click="setView 'edit'"`); inside a normal MoonBit string you must
escape the double quotes (`"<p :class=\"'flex gap-3'\">x</p>"`). Prefer
`#|` raw strings for multi-line views.

## Component Skeleton

What you write is the handlers; everything else the view file states. The
wrapper `gen` emits is typed on the state struct, so lambda parameters
need no annotation:

```moonbit nocheck
// nocheck: the wrapper's parameter list, annotated — not a compilable item
my_comp_component(
  // `init` defaults to MyCompState::zero() — pass it only for what differs
  initial={ ..MyCompState::zero(), count: 0 },
  // ONE effectful dispatch match: (s, msg, ctx) => Update[S]
  // (Next = successor, Unchanged = mine and no, Unhandled = not mine)
  update=(s, msg, ctx) => match msg {
    Receive("onClick", _) => Next({ ..s, count: s.count + 1 })
    Receive("init", _) => {
      ctx.intent("loadData", [], @tutuca.IntentOpts::new(route=[Lex]))
      Some({ ..s, isLoading: true })
    }
    Intent("itemPicked", [item, ..]) => Next({ ..s, selected: item })
    Receive("loadDataOk", [List(rows), ..]) =>
      Some({ ..s, items: rows.map(r => r.str()), isLoading: false })
    _ => Unhandled // ALWAYS needed
  },
  // Each bucket is keyed by an enum generated from the names the views use,
  // so the match is exhaustive over them and a name added to a view is a
  // build error. The enum is a CLOSED set: an entry for a name no view
  // references does not compile (no such constructor), so handlers cannot
  // be pre-declared "for later". A bucket the views never use is not a
  // parameter at all.
  compute=m => match m { // pure value read, $name: (s, args, stack) => Value
    Label => Some((s, _args, _stack) => Str("n=\{s.count}"))
  },
  when=w => match w { // @when filters: (s, key, value, iterData, stack) => Bool
    FilterItem => Some((s, _key, value, _iter, _stack) => value.str() != "")
  },
  // enrich= / bind_with= / loop_with= — see iteration.md
  // `Replace(v)` in an update arm — supersede this node with another
  // instance; see Replacing a node with a different component
  slot_args={ // the ONE thing no type can state: a child's ctor arguments
    "child": { "label": Str("pick one") },
  },
  // provide={ ... }, lookup=[ ... ]   // see advanced.md,
)
```

`name`, `views`, `common_style` and `global_style` are not written here: the
view file states them and the wrapper passes them. Do **not** restate them —
that is how a fact the generator learns fails to reach the component. They are
still parameters, so override one when a component genuinely differs.

The codec and the schema are not parameters of anything: `MyCompState`
implements `@component.Fields` (`schema` / `encode` / `decode`), which
`component()` is bounded on and reads off the type. The generator writes that
impl. Note the consequence — a schema belongs to a TYPE, so two components
sharing a state struct share its description.

`init` defaults to `MyCompState::zero()` — omit it when the zero state is what
you want, and pass a `tutuca/fixtures` fixture (`MyCompState::fresh()`) or a
literal otherwise.

Call `@component.component(...)` directly only when there is no wrapper —
views built in MoonBit, so there is nothing to default `views~` to. The state
type still has to implement `@component.Fields`; a component that declares
less does not get a runtime that infers the difference.

> **Two bucket spellings, by call target.** The generated wrapper takes an
> enum match, the raw `@component.component(...)` call takes a string-keyed
> map, and they are not interchangeable. The full rule — plus which bucket
> answers which name, and the dispatch precedence between them — is
> [The handler buckets](#the-handler-buckets).

`comp.make({...})` builds an instance from a `Map[String, Value]` of
args and returns it as a `@tutuca.Value` (the `Obj`) — ready to store in
lists, maps, or example args. Missing fields get their defaults from
`init`, and every arg is coerced through its DECLARED kind (a wrong-shaped
value falls back to the default — silently).
A component-typed field (a **slot**) builds its default instance through the
registration scope at `make()` time, so forward references work by name. The
schema names the component; `slot_args={ "child": {...} }` supplies the
arguments it is built with — see [schema.md](./schema.md#slots).

> **No statics.** The JS `statics:` block has no MoonBit counterpart —
> nothing in the framework calls statics in either language. Write a
> plain MoonBit `fn` next to the component (e.g. a
> `fn tree_from_data(...) -> @tutuca.Value` factory that calls
> `comp.make(...)`) and call it directly. Likewise, "one component
> object per scope" is natural here: a component definition is a
> `fn my_comp() -> Component`, and each call produces a fresh
> `Component` value (new id, separately compiled CSS) to register into
> a scope.

## Fields

**The schema is the fields.** Names, types and kinds are declared in the view
file's `<script type="tutuca/spec">` block; `gen` writes the struct, and
every handler body is compiler-checked against it — `s.cuont` is a compile
error, not a silently-Null render.

How a field's type is spelled, and which property operations its kind admits,
is one table in [schema.md](./schema.md#property-actions-in-views). Two consequences worth
carrying here:

- Views write the receiver directly: `@on.click=".items.removeAt @key"`,
  `@on.input=".query = e.value"`, and `@on.click=".view = not .view"`.
- Emptiness / truthiness / null checks are **not** generated — use the shape
  predicates `empty?`, `truthy?`, `null?` in a conditional slot instead (e.g.
  `@hide="empty? .x"`, `@show=".view is 'detail'"`).

A field that can hold "anything" is declared `any` (MoonBit `@tutuca.Value`) —
the dynamic escape hatch inside an otherwise typed struct. That includes fields
holding component instances or `Fn` values: they survive state updates
losslessly.

## Derived properties and parameterized computes

A zero-argument derived value is a read-only private property. Declare its type
in the state and implement the getter in the script block; every value slot
reads it with `.name`:

```html
<script type="tutuca/spec">
  state Form {
    title: String
    property { label: String { get } }
  }
</script>
<script type="tutuca/script">
  get label { if state.title is '' { 'untitled' } else { state.title } }
</script>
<p @text=".label"></p>
```

A computation that takes arguments remains a method and uses `$name args…`.

The map form below is the raw `@component.component(...)` spelling; a
generated wrapper takes the enum-match form instead, with one `Some(...)` arm
per name in place of each map entry — see
[The handler buckets](#the-handler-buckets):

```moonbit nocheck
// nocheck: a bucket argument, not a top-level item
compute={
  "canSubmit": (s : FormState, _args) => Bool(s.title.length() > 0 && !s.isLoading),
  "buttonClass": (s : FormState, _args) => if s.isActive {
    Str("btn btn-primary")
  } else {
    Str("btn")
  },
  "fullName": (s : FormState, _args) => Str("\{s.first} \{s.last}"),
}
```

```html
<button @show=".canSubmit" :class=".buttonClass">Save</button>
<p :title="$'Hello, {.fullName}'" @text=".fullName"></p>
```

The shape predicates (`empty?`, `truthy?`, `null?`) and the operators
cover conditions in a slot directly; reach for a `compute` when the condition
needs derivation, or when naming it makes the view read better.
The handler bodies are typed — no pattern-matching `Value` shapes for
plain struct fields.

Tutuca expressions resolve a **single** name on the state — there is
no path syntax. `@text=".user.name"` does not navigate; it fails. When
the value lives behind a field, your options are:

- **Render the child as a component** — `<x render=".user">` then
  `@text=".name"` inside the child's view. Best when the nested thing is
  already (or could be) a component.
- **Add a read-only property** — reading through the value coercers when the
  field is a `@tutuca.Value`:

  ```moonbit nocheck
  // nocheck: a fragment (a match arm or an expression), not a top-level item
  "userName": (s : PageState, _args) => s.user.field("name"),
  ```

  then `@text=".userName"`. Best for one-off derivations or formatting.
- **Use `@enrich-with`** — exposes computed values as `@`-bindings to a
  subtree without putting them on the component. See *Scope Enrichment*
  in [iteration.md](./iteration.md).

Exceptions: `@each` / `render-each` accept `.field` or `*dynamic` only
(not a `$handler` — a computed result has no addressable path for event
dispatch, so `$m` is rejected there at parse time), and `<x render>`
expects a component instance — for a derived list, store it in a field
or use `@when` with a `when` entry.

## Text Rendering

```html
<span @text=".str"></span>          <!-- prepend text into span -->
<x text=".bool"></x>                <!-- text-only, no DOM element -->
<x text=".strUpper"></x>            <!-- derived property -->
<x text="@value"></x>               <!-- loop binding -->
```

Use `@text` when you already have a host element to put the text in; use
`<x text=…>` for bare text with no wrapping element (e.g. text interleaved with
other inline content, or a loop binding). Both take the same value forms
(`.property`, `$method args…`, `@binding`). A `Null` text value renders nothing
(not the string `"null"`).

## Attribute Binding

```html
<input :value=".str" @on.input=".str = e.value" />
<a :href=".url" :title="$'Hi {.name}'">link</a>       <!-- string template -->
<button :class="$'btn {.color}'">x</button>
```

Plain attrs are static. `:attr="..."` is a dynamic expression. Boolean
HTML attributes (`disabled`, `checked`, `hidden`, …) are auto-recognized;
pass a boolean field. `style` is a plain string attribute like any other
— there is no style-object form.

A static `class="…"` and a dynamic `:class`/`@if.class` **cannot coexist on the
same element**: the dynamic value wins and the static class is silently dropped.
Nothing reports it — they are different attribute names to the HTML parser, so no
duplicate-attribute rule fires. Fold any structural classes into the bound expression,
e.g. `:class="$'btn {.color}'"` (note `btn` is part of the template, not a
separate `class="btn"`). The same applies to other attributes.

The HTML parser lowercases attribute names before tutuca sees them, so
`:mapId` arrives as `:mapid` and `<x:Card>` becomes `<x:card>`. Three
consequences:

- SVG attributes are case-sensitive. Tutuca special-cases `:viewbox` →
  `viewBox` so SVG roots work; for other camelCased SVG attrs, wrap them
  in components that emit raw markup.
- Custom-element property setters defined in camelCase **will not fire**.
  `:mapId=".mapId"` sets `mapid`; if the element defined `set mapId(...)`,
  the lookup misses silently — no error, no warning, the bound state stays
  null. Author custom elements with kebab-case attributes plus lowercased
  property setters (or aliases), and bind via `:kebab-name` from tutuca
  templates.
- Macro registry keys are lowercased on insert for the same reason
  (see [macros.md](./macros.md)).

Tutuca auto-namespaces by subtree: elements inside `<svg>` get the SVG
namespace and elements inside `<math>` get MathML, with spec-cased local
names preserved (`linearGradient`, `viewBox`). A `<foreignObject>` switches
its children back to the HTML namespace. Customised built-in elements work
via `is="..."` (e.g. `<button is="x-fancy">`); `is` is applied when the
element is created, so it must be a static attribute — setting it later
does not upgrade the element.

### When nothing renders (or renders unstyled)

A few mistakes fail quietly — no error, just a blank or unstyled result, which
is the slowest kind to debug. **Regenerate the views and run `moon check`
first**: several of these become build errors that way. The usual suspects:

- **Unparseable attribute value** → the attribute is silently dropped. A bare
  multi-word value isn't a string — quote it (`:label="'two words'"`) or make it
  a template (`:label="$'{.a} {.b}'"`). `gen` rejects this as
  `BAD_VALUE` rather than generating a module for it.
- **camelCase attribute on a custom element** → setter no-op (see the lowercasing
  note above). Use kebab-case attributes. Not detectable — the HTML parser
  lowercases the name before either tutuca or the generator sees it.
- **Forgotten margaui decoy view** → classes assembled in `compute` entries or
  interpolations render unstyled. See [margaui.md](./margaui.md). Not lintable.
- **A whitespace-only view** → blank render. A *leading* newline before the
  root element is fine (the parser trims it); a template with no element at all
  is not.

## Event Handling

```html
<!-- a bare name dispatches a `Receive` arm of `update` -->
<button @on.click="inc">+</button>

<!-- pass args by name -->
<input @on.input="setStr e.value" />
<input @on.input="setN e.valueAsInt" />
<button @on.click="pick @key e.isAlt">pick</button>
```

The handler **name** is written bare — a leading `$` is refused in an event
position. Its **arguments** carry a sigil that says where the value comes from:
`e.…` reads the DOM event, `.field` reads state, `@bind` reads a binding. (A bare
argument name says none of the three, so `gen` refuses it and names them.)
Written args arrive in the handler's `args` array in template order, so an arm
pattern-matches them directly
(`Receive("search", [Str(q), ..]) => ...`). With generated views each `@on` name
becomes a case of `<Comp>Msg`, its payload type inferred from what the call site
writes.

The accessors the glue computes (`e.value`, `e.valueAsInt`, `e.key`, `e.isCtrl`,
…), the allowlisted property walk behind `e.target.dataset.x` / `e.detail.x`, the
`<Comp>Msg` payload-type table, event modifiers, and custom-element events are all
in **[events.md](./events.md)**. Two things worth knowing before you get there:

- There is **no `event` or `ctx` argument** — a DOM object is not a `Value`, so
  `event` resolves to `Null` and the handler silently receives nothing. Reach the
  event through `e.` instead.
- Modifiers come in two kinds: **guards** (`+send`, `+cancel`, `+ctrl`, …, on
  `keydown` and `click`) and **effects** — `+prevent` calls `preventDefault`,
  `+stop` calls `stopPropagation`, when the handler runs. Details in
  [events.md](./events.md#event-modifiers).

## Conditional Display

```html
<div @show=".isLoading">Loading...</div>
<div @hide=".isLoading">content</div>

<!-- an expression; `is` compares against a string literal -->
<div @show=".view is 'detail'">detail view</div>

<!-- @show / @hide also work as directives on `<x>` render ops:
     wraps the produced node, no extra DOM element. Allowed on
     text / render / render-it / render-each. First attr in
     source order becomes the outermost wrapper. -->
<x text=".name" @show=".isOpen"></x>
<x render-it @hide=".isHidden"></x>
<x render-each=".items" @when="filter" @show=".isOpen"></x>

<!-- Single @if: shorthand @then/@else (attr inferred) -->
<button @if.class=".isActive" @then="'btn btn-success'" @else="'btn btn-ghost'">
  ...
</button>

<!-- Multiple @if on same element: name the attr explicitly -->
<button
  @if.class=".isActive"
  @then="'on'"
  @else="'off'"
  @if.title=".isActive"
  @then.title="'On'"
  @else.title="'Off'"
>
  ...
</button>
```

> HTML disallows duplicate attrs, so with multiple `@if.<attr>` on one
> element every `@then`/`@else` after the first **must** include the attr
> name — otherwise the parser drops it before tutuca sees it.

A branch is an **expression**, so a literal class list needs its quotes:
`@then="'btn btn-primary'"`, never `@then="btn btn-primary"`. An unquoted one
fails `gen` with `bad value '…' in directive 'then'`.

Note: `@show` / `@hide` **omit the node from the output** when the
condition says hide — they do not merely toggle CSS visibility.

## List Iteration & Scope Enrichment

```html
<li @each=".items"><span @text="@key"></span>: <x text="@value"></x></li>
<x render-each=".items"></x>
```

Auto-bound names inside a loop are `@key` and `@value`. Iteration
(`@each` / `render-each`), filtering (`@when` → the `when` bucket),
item and scope enrichment (`@enrich-with` → `enrich` / `bind_with`),
pagination and the `@loop-with` → `loop_with` return shape, and the
`@each` lifecycle: see [iteration.md](./iteration.md).

## Rendering Components

```html
<x render=".item"></x>                          <!-- default ("main") view -->
<x render=".item" as="edit"></x>                <!-- specific view (literal) -->
<x render=".item" as=".mode"></x>               <!-- view chosen by a field at runtime -->
<x render-it></x>                               <!-- only inside @each / render-each -->
<x render=".byIndex[.currentIndex]"></x>        <!-- list item access -->
<x render=".byKey[.currentKey]"></x>            <!-- map item access -->
<x render="*active"></x>                        <!-- dynamic binding — see advanced.md -->
<x render=".item" @show=".isOpen"></x>          <!-- conditional wrap, see "Conditional Display" -->
```

A component's views come in through `views=` (a
`Map[String, @anode.View]`), keyed by name — `"main"` is the one rendered by
default. Author them in an `.html` file and generate the map with
`tutuca gen` (see [cli.md](./cli.md)). A view whose SOURCE only exists at
run time — a guest bundle, markup a MoonBit function assembles — uses
`@anode.View::new("main", raw_view="…")`, which builds the same `@anode.View`;
its component still declares a schema and a codec like any other. `as` selects
which view of the
rendered component to use, falling back to `main` if absent. It accepts the
same dynamic values as `@push-view` (a literal name like `edit`, or `.field`,
`*dyn`, `@bind`, `$handler`, `$'…{x}…'`), evaluated against the **host**
component at render time. `as` only applies to the **direct** component — for
whole-subtree control, use `@push-view` (next section). For `render-each` the
selector is evaluated once against the host, so every item gets the same view.

## Multiple Views & View Stack

Named views are `<template id="Comp:name">` entries in the view file:

```html
<template id="Note"><p @text=".title"></p></template>
<template id="Note:edit">
  <input :value=".title" @on.input=".title = e.value">
</template>
```

```moonbit nocheck
// nocheck: one expression, shown to make the point that nothing else is needed
note_component() // the wrapper passes both views
```

```html
<!-- @push-view pushes a name onto the rendering stack;
     descendants resolve to first matching view, falling back to "main" -->
<div @push-view=".view"><x render-each=".items"></x></div>
```

| Directive          | Scope                                                                    |
|--------------------|--------------------------------------------------------------------------|
| `as="edit"` / `as=".mode"` | One `<x render>` element only. Literal or dynamic (like `@push-view`), evaluated against the host. |
| `@push-view=".v"`  | Every component rendered recursively under the host (children + descendants). Each picks the first stack entry it has a matching view for; falls back to `"main"`. Inner `@push-view`s nest, extending the outer ones. |

## Styles

Each view carries its own `style`, scoped to that view; `common_style` is
scoped to all views of the component, and `global_style` is injected
unscoped (see the *Component Skeleton*
above). Scoping mechanics, styling the root element with bare
declarations, and the at-rules that must live in `global_style`: see
[styles.md](./styles.md). Tailwind / MargaUI utility classes:
[margaui.md](./margaui.md).

## The handler buckets

Everything you write **in MoonBit** beside a generated view goes in one of
these. This is the canonical list; other files link here rather than restating
it.

Reach for a bucket after the declarative forms. A source operation is answered
by the first applicable layer:

1. a **property action** — `.x = value`, `.x = default`, or a collection
   operation such as `.items.push value`. No message name is generated.
2. a **declaration in one of the two blocks** — `receive`, `intent`,
   `compute`, `enrich`, `bindWith` and the `send` / `sendAt` / `intent` /
   `forward` effects in `<script type="tutuca/script">`; `pred` and `invariant`
   in `<script type="tutuca/spec">`, beside the state they are about. A name a
   block answers is dropped from the generated enum, so the two halves can
   never both claim one handler.
3. a **bucket entry**, for what neither of those says: building a child
   component instance, `@loop-with`, a fold over a whole sequence, a payload
   unpacked out of an `Any` — and anything `gen` prints a
   `script-refusal` for. The block's own reference, and the list of what the
   ahead-of-time backend refuses, are in
   [schema.md](./schema.md#what-the-ahead-of-time-backend-refuses).

| Bucket | Signature | Answers |
| ------ | --------- | ------- |
| `update` | `(S, Dispatch, &Ctx) -> Update[S]` | every event, message and intent; one match over all the channels |
| `compute` | `(S, Array[Value], &Stack) -> Value` | a `$name` in a **value** position — pure, no ctx |
| `when` | `(S, key, value, iterData, &Stack) -> Bool` | `@when` iteration filters |
| `enrich` | `(S, binds, key, value, iterData, &Stack) -> Unit` | `@enrich-with` per-item binds |
| `bind_with` | `(S, &Stack) -> Map[String, Value]` | scope-level derived binds |
| `loop_with` | `(S, seq, LoopCtx) -> LoopWith` | `@loop-with` slicing / filtering / key lists |

The four render-time buckets — `compute`, `when`, `enrich`, `bind_with` —
take a trailing `&@tutuca.Stack`: the render position the body is being asked
from. `stack.lookup_dynamic(name)` is what answers a `*name` inside one, and it
is the same lookup the card runtime performs for a `*name` in a slot beside it, so a
`pred` and the `@show` that reads it agree. A body that asks nothing of it
names the parameter `_stack`; `gen` writes that for you. `loop_with`
takes neither.

### Two spellings, by call target

The **generated wrapper** (`my_comp_component(...)`) types each bucket as a
function from a generated enum returning the handler as an `Option`:

```moonbit nocheck
// nocheck: one bucket argument, not a compilable item
compute=m => match m { Label => Some((s, _args, _stack) => Str("n=\{s.count}")) }
```

Return `None` for a case to leave it unanswered. (That is the bucket's own
`Option`, not `update`'s three-case `Update` — a bucket entry either exists
or does not.) The raw
`@component.component(...)` call instead takes a **string-keyed map**:

```moonbit nocheck
// nocheck: one bucket argument, not a compilable item
compute={ "label": (s, _args, _stack) => Str("n=\{s.count}") }
```

Snippets in this skill showing the map form are showing the raw call. With a
generated wrapper, translate them to the enum match — the wrapper's parameter
type will not accept a map.

The enums are **closed and view-driven**: their cases come from the names the
views reference, plus the `compute` names the script block declares and the
`pred` / `invariant` names the spec block declares — minus the ones a block
ANSWERS, which need no arm. An `invariant` is the one exception to
"view-driven": it gets a body whether or not a view names it, because the
runtime asks it after every dispatch. You cannot pre-declare a
handler no view calls yet — the constructor doesn't exist. Add the name to the
view first, regenerate, then write the handler. A bucket the views never use is
not a parameter at all.

### The channels

Each maps a trigger to one arm of the **same `update` match**:

| Triggered by                                      | `update` arm          | Use for                                            |
| ------------------------------------------------- | --------------------- | -------------------------------------------------- |
| DOM event (`click`, `input`, …)                   | `Receive(name, args)` | the component handling its own events              |
| `ctx.send(name, args)` — message to a target path | `Receive(name, args)` | addressing one known component (or self)           |
| `ctx.intent(name, args, opts)` — a routed walk    | `Intent(name, args)`  | work the sender does not address: an ancestor's job (`dyn`) or the scope's (`lex`) |

The first two rows are the **same arm** on purpose: a message is addressed at
one component, and a view is addressed at the component it belongs to. There is
no arm that tells you a name arrived from a click rather than from a parent's
`ctx.send`. Splitting them would let a component answer its own view one way and
an identical `ctx.send` another, which is a component you can neither drive from
a test nor reuse under a parent that drives it.

The `update` fn is one pattern match over all of them; the framework swaps the
returned state into the dispatch path (`Next(s)` = the successor, `Unchanged` =
this arm answered and nothing moved, `Replace(v)` = this node is superseded by
another value entirely, `Refused(r)` = this arm turned the dispatch down and
says why, `Unhandled` = try the next answerer). An intent's three
answers — `<name>Ok` / `<name>Failed` / `<name>Unhandled` — come back as
ordinary `Receive` arms. The channels — plus `ctx.at()`,
routes and legs, `forward` / `reply` / `fail`, catch-all arms, and `IntentFn`
registration — are in
[messages-and-intents.md](./messages-and-intents.md); worked snippets in
[patterns/coordinate-components.md](./patterns/coordinate-components.md).

### A name is answered, or it is refused

A `Receive` name is offered to **`update`**, and to nothing else. An arm that
claims the name answers `Next`, `Unchanged`, `Replace` or `Refused`; an arm that
does not answers `Unhandled`, and a name nothing answers is refused with
`NoHandler` — it is not quietly routed somewhere the author did not write.

There is no fallback to a setter the field implies. A view that wants to write a
field writes it, in the view, as a **property action**:

```html
<button @on.click=".title = 'x'">rename</button>
<input @on.input=".query = e.value">
<button @on.click=".isOpen = not .isOpen">toggle</button>
<button @on.click=".count = default">reset</button>
```

That is a write, and it reads as one. A name in an event position — `@on.click="rename"`
— is a **message**, and a message needs an answerer. The two used to be the same
thing when the name happened to be `setTitle`, which meant a typo'd handler
silently became a field write and a real handler could be shadowed by the field
beside it.

Writing a property from a view goes through the same door a parent's write goes
through: the domain and the invariants both get asked, and a rejected write comes
back as a `Refusal` (see [schema.md](./schema.md)).

### Replacing a node with a different component

`update` normally returns a new **state struct**, so it can only produce another
instance of the same component. `Replace(v)` returns a bare `Value` instead,
which means the node is superseded by something else entirely — most usefully
*another component's instance*:

```moonbit nocheck
// nocheck: one update arm, not a compilable item
// `@on.click="becomeEditor"` — supersede this node with an Editor instance
Receive("becomeEditor", _) => Replace(editor.make({ "text": Str(s.text) }))
```

Reach for `Replace` only for a genuine change of identity; a view that merely
looks different wants `@push-view` or an `as=` view (see *Multiple Views & View
Stack*).

### The render buckets

`when` / `enrich` / `bind_with` / `loop_with` aren't event-triggered — the
renderer invokes them to filter iterations and produce binds, not state changes
(see *Mental model*, and *Scope Enrichment* in
[iteration.md](./iteration.md)).

## Macros

Pure template expansion, called as `<x:name>`, with `^param` references, slots
and named slots: see [macros.md](./macros.md). Declare one in the view file as
`<template id="macro:card" data-title="'Untitled'">` and it is expanded when
the views are generated. `@anode.Macro` values (`{ defaults, raw_view }`)
registered on a `ModuleDef` are the runtime form, for a body a MoonBit
function builds — a file using those cannot be compiled ahead of time.
Registry keys are lowercased — `<x:Card>` resolves as `<x:card>`.

## Raw HTML (escape hatch)

```html
<div @dangerouslysetinnerhtml=".trustedHtml"></div>
```

Bypasses all escaping; children of the element are ignored when active.

**Only for markup you wrote.** For content that came from a user, an API or a
model, reach for `@setinnerhtml`, `@setinnersvg` or `@setinnermd` below instead
— all three are the same shape without the escape hatch.

You almost never want this one. Its single remaining use is markup you need to
reach the DOM *unaltered* — a deliberate `javascript:` URL, an inline `<style>`
— and it costs you a permission (`SanitizerConfig.raw_markup`) and a filter to
get it.

## Markdown (`@setinnermd`)

```html
<article @setinnermd=".body"></article>
```

Takes a markdown SOURCE string and replaces the element's children with the
nodes it parses to. CommonMark plus GFM — tables, task lists, strikethrough,
footnotes — with no flag to turn any of it on.

It is safe by construction rather than by permission, so unlike
`@dangerouslysetinnerhtml` there is nothing to grant: the markdown never becomes
an HTML string, and every element and attribute value it produces is judged by
the app's own `@sanitize.Sanitizer` on the way out. `<script>`, `<iframe>`,
`on*` handlers and `javascript:` URLs are gone; a denied URL drops the
*attribute*, not the element, so a bad link keeps its words and loses its
destination. Raw HTML inside the markdown goes through the same sanitizer.

`App::new` installs the filter that does this, so it works with no setup, and
there is no way to turn it off: `App::set_sanitizer` changes WHICH policy the
chain enforces, and `App::add_filter` adds a rule of your own behind it.

Two behaviours worth knowing before you use it: inline HTML tags (`<span>x</span>`
inside a paragraph) render as literal text rather than as markup, and an
unbalanced HTML block does not adopt the markdown that follows it as children.

`.body` is an ordinary text field, bound like any other; the directive re-parses
it on every render. A worked example — editor on the left, live preview on the
right, and a second half showing what gets refused — is on the landing site
(`playground/site/examples/markdown.{mbt,html}`).

## HTML and SVG (`@setinnerhtml`, `@setinnersvg`)

```html
<article @setinnerhtml=".body"></article>
<svg viewBox="0 0 100 100" @setinnersvg=".chart"></svg>
```

`@setinnermd`'s siblings, for a payload that is already markup — a CMS body, a
server-rendered fragment, a chart some other program drew. Same promise, same
mechanism: the payload is parsed ONCE, walked into described nodes, and every
element and attribute value is judged by the app's own `@sanitize.Sanitizer` on
the way out. No HTML string is ever handed to the browser, so there is no second
parse to disagree with the first.

Gone from a payload, whatever the config says: `<script>` in either namespace,
`<iframe>`, `<object>`, `<base>`, SVG `<use>`, the four SMIL elements
(`<animate>`, `<animateMotion>`, `<animateTransform>`, `<set>` — they rewrite an
attribute *after* every check has run), `on*` handlers, and `javascript:` URLs.
A denied URL drops the *attribute*, not the element.

Also gone, and only from these two: `style` attributes and `<style>` elements.
CSS is not script, but `url(…)` is a request to an origin the payload chose and
`position:fixed` over your page is a click somebody thought they were giving to
something else — and nothing here parses CSS to tell the difference. Style the
payload's container with classes instead.

`@setinnersvg` differs from `@setinnerhtml` in one thing: the payload is parsed
in SVG context. A bare `<circle/>` fragment works with no `<svg>` root of its
own, and the payload cannot leave the SVG namespace except through
`<foreignObject>`, whose contents are then judged as HTML. Put it on an element
that is itself SVG.

Neither needs a permission and neither is refused at registration — unlike
`@dangerouslysetinnerhtml`, there is no unchecked path to permit. `App::new`
installs the filter, so both work with no setup, and no call takes it away. A
host that wants less says which elements it will have, with a `SanitizerConfig`
through `App::set_sanitizer`, the same way it does for every other node in the
tree.

One exception, in `tgc`: an **untrusted** guest may not use any of the three
runtime-markup directives. That refusal is not about XSS — the sanitizer handles
that — but about egress: an `<img src>` the sanitizer is perfectly happy with is
still a request to an origin the guest chose, from the host's page.

## State values: the `Value` enum

Underneath the typed structs, all state is the `@tutuca.Value` enum —
there is no immutable.js layer in this port:

```moonbit nocheck
// nocheck: reproduces core's own declaration for reference; `&Obj` only
// resolves inside the package that declares it
pub(all) enum Value {
  Null
  Bool(Bool)
  Num(Double)              // the one number type (JS semantics)
  Str(String)
  List(Array[Value])
  Map(Map[String, Value])  // MoonBit Map iterates in insertion order
  Fn((Array[Value]) -> Value)
  Obj(&Obj)                // component instances & custom collections
}
```

- The state struct is encoded to / decoded from this layer by its generated
  `@component.Fields` impl, field by field. A `@tutuca.Value` field is
  passed straight through, which is why an `Obj` or an `Fn` held in one
  survives — a JSON round trip could not carry either.
- `Value` derives `Eq` (deep structural equality) and `Debug`, so
  `assert_eq` and `debug_inspect` work on values directly.
- `v.is_truthy()` gives JS-style truthiness; `v.to_display_string()`
  the display form. The coercers `v.int()`, `v.num()`, `v.str()`,
  `v.bool()`, `v.list()`, `v.map()`, `v.entries()`, `v.item(key)` /
  `v.index(i)` / `v.key(k)`, `v.size()`, `v.call_field(name, args)`, and
  `v.field("name")` (works on `Map` **and** `Obj`) read `Value`s in handler
  args and
  `@tutuca.Value` fields.
- **Immutability is by discipline**: `Array` / `Map` payloads are
  ordinary mutable containers — handlers must **copy before changing**
  (`s.items.copy()` then `push`) and return a **new** struct
  (`Some({ ..s, items: next })`), never mutate in place.
- Sets are modeled as a `Map` keyed by member (value `Bool(true)`), declared
  `Set[String]` or `Set[Enum]` in the schema; ordered maps are plain `Map`s,
  declared `Map[String, V]`. See [schema.md](./schema.md#field-types).
- Custom collections implement the `@tutuca.Obj` trait (notably
  `seq_entries` for `@each`) — see [iteration.md](./iteration.md)
  *Custom collections*.

## The ModuleDef convention

The JS `getComponents()` / `getMacros()` / `getRequestHandlers()` /
`getExamples()` ES-module contract becomes one **value**: a
`@component.ModuleDef`. A native binary cannot load user code, so
modules are built programmatically and handed to tooling:

```moonbit nocheck
// nocheck: the comps, macros and intent fns are the reader's own
pub fn my_module() -> @component.ModuleDef {
  @component.ModuleDef::new(
    name="my-module",
    components=[root_comp(), item_comp()], // EVERY component, helpers included
    macros={ "badge": badge_macro() },     // optional
    intents={ "loadData": [load_data_fn] }, // optional, Array[IntentFn] per name
    examples=[                             // optional, Array[ExampleDef]
      { component: "Root", title: "Default", args: {}, view: None },
      {
        component: "Root",
        title: "Loaded",
        args: { "items": List([item.make({})]) }, // make() returns a Value
        view: None, // or Some("edit") to render a named view
      },
    ],
  )
}
```

One `ModuleDef` drives the headless tests (`@harness.mount`), the
browser hosts (`App::from_module`) and the storybook gallery — a passing
test and a working page are the same artifact.

**Per-example intent mocking**: parameterize the module function with
an optional `intents?` argument, defaulting to the real handlers, and
build the module with a fixture map in tests/demos:

```moonbit nocheck
// nocheck: the real handlers and comps are the reader's own
pub fn request_module(
  intents? : Map[String, Array[@component.IntentFn]] = real_intent_handlers(),
) -> @component.ModuleDef {
  ...
}
```

Best practice: have `components` list **every** component the module
defines — child and helper components included — and give each one at
least one `ExampleDef`. A component left out of `components` cannot be
resolved by name at render time (`<x render=".child">` finds nothing), and
its examples never reach the storybook or a harness test.

## See also

- [schema.md](./schema.md) — the `<script type="tutuca/spec">` language: field
  spellings, the mutators each kind generates, slots, message buckets,
  `tutuca/fixtures` fixtures, and the `pred` / `invariant` rules a component keeps
  with the `format` each says when it fails — plus what the
  `<script type="tutuca/script">` block beside it declares: `$`-callables,
  `new` / `cur` value building, the `requires` / `ensures` clauses that attach
  a rule to a transition, and the refusal channel that carries a failure.
- [events.md](./events.md) — handler argument names, generated `<Comp>Msg`
  payload types, event modifiers, and custom-element events.
- [iteration.md](./iteration.md) — `@each` / `render-each`, `@when`,
  `@enrich-with`, `@loop-with` pagination, and the loop lifecycle.
- [macros.md](./macros.md) — `Macro` definitions, `<x:name>` calls,
  slots, and registration.
- [styles.md](./styles.md) — `style` / `common_style` / `global_style`
  scoping mechanics and pitfalls.
- [component-design.md](./component-design.md) — design judgment for shaping a
  feature into components: responsibilities, where state lives, which channel to
  reach for, and a curated do's & don'ts list.
- [messages-and-intents.md](./messages-and-intents.md) — the `Receive` /
  `Intent` channels, routes and legs, `ctx.at()`, catch-all arms, and
  `IntentFn` registration.
- [advanced.md](./advanced.md) — dynamic bindings (`*x`), pseudo-`@x` for
  `<select>` / `<table>` / `<tr>`, drag & drop, custom collections.
- [margaui.md](./margaui.md) — setting up MargaUI styling:
  `collect_classes()`, the MoonBit compile step, and `inject_style`.
- [semantics.md](./semantics.md) — runtime semantics: path steps, the
  transaction lifecycle, resumed render paths, and async key pinning
  (`live_path`).
- [testing.md](./testing.md) — `moon test` blocks and the `@harness`
  mount/drive/read API.
- [cli.md](./cli.md) — the embedded CLI: commands, flags, exit codes, and
  every diagnostic `gen` can report.
- [playground.md](./playground.md) — authoring in an in-browser playground:
  same generated names, the view+code pair convention, verifying without
  `moon`.
- [patterns/README.md](./patterns/README.md) — task-oriented recipes ("how do I
  iterate / filter / paginate / show-hide / build tabs / share state / …"),
  including a complete todo-list pairing.
