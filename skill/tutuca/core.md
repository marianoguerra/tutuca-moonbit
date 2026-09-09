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

1. **Regenerate the views, if you edited a `.tutu`** — the generator is
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

- **`it.name` reads a property; `name(args…)` calls a method.** A field is an
  implicit private property, and an explicit property of the same name wins.
  A zero-argument derivation is a read-only property and is still `it.label`.
  In an event position, `it.name := value` and `it.items.delete_at(key)` are property
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
- **Paths are not allowed in values.** `it.foo` resolves a single property on
  the state — `@(it.foo.bar)`, `~value: it.user.name`,
  `show(it.item.is_open)` all fail. To reach into nested data: render the
  child as a component (`render(it.foo)` then `@(it.bar)` inside),
  add a read-only property (read the nested value off a `@tutuca.Value`
  field with `v.field("name")`), or use `~enrich_with`
  for scope-level derivation. The one exception: a **binding** may read
  exactly one **binding member** — `@(value.title)` inside `each`
  works (any `@`-binding, one level only; `@value.a.b` fails generation
  as `BINDING_MEMBER_TOO_DEEP`, and render targets still reject it).
- **Use `~bind=".field"` only for checked scalar form bindings.** It requires a
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
- **Two conditional attributes on one element** are two independent `if`s,
  each in its own attribute — there is no shared condition to get wrong.
- **A bare unquoted multi-word value is a NAME, not a string.** Either quote
  it (`"flex gap-3"`) or write a template (`@str{flex gap-3 @(it.color)}`).
- **`Receive("init", _)` is a convention, not a lifecycle hook.** Nothing
  dispatches it automatically — the host calls `app.send_at_root("init")`
  or another handler sends it.
- **Example `args` hold instance Values, not plain data.** A
  component-typed slot in an `ExampleDef`'s `args` (or in a `List` field)
  must be built with `comp.make({...})` — which returns the instance as a
  `@tutuca.Value` directly — not a bare `Map`.
- **A view must contain a root element.** A leading newline before the
  first element is trimmed, but a view with only whitespace in it renders
  blank silently.
- **Macro registry keys are lowercased.** `@Card(…)` becomes `@card(…)` —
  see [macros.md](./macros.md).

## Bootstrap

A component is declared in a `.tutu` file — its `spec:`, its `logic:`, its
`view:` and its styles — and `tutuca gen` compiles that into a MoonBit module
beside it. What you write is the code no generator can: the handlers.

`counter.html`:

```tutu
spec:
  Counter:
    field count :: Int

view:
  Counter:
    button(~on_click: inc):
      @(it.count)
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

Adding `~on_click="del"` to the view and regenerating makes that match
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
and can read it for an aggregate decision. The single-level `it.field`
restriction (no `it.foo.bar`) is a **view-template** rule, not a MoonBit
one — it's why a derivation like "the user's name" is written as a
`compute` entry (see *Computed values & predicates*). Reading is free;
**mutating** a child still flows through the model — the owner returns
a new state (`set_in_items_at`, …) or messages the child with `ctx.send`.
Don't reach in to mutate around the handler discipline, and prefer
letting a child own and render its own state — reach down to read only
when the ancestor genuinely needs it. See
[component-design.md](./component-design.md) and "When to send" in
[messages-and-intents.md](./messages-and-intents.md).

**Stack: frames vs scopes.** As the renderer walks the AST it pushes
bind frames. A *frame* is a barrier: name lookups (`@x`) stop at it,
so a child component view sees a clean namespace. A *scope* is
transparent: iteration `key` / `value` and `~enrich_with` binds layer
onto the surrounding frame and remain visible to handlers attached to
the same iteration. `it` (the target of `it.field` reads and `handler()`
calls) is set on both.

| pushed by                           | kind  | shape                                |
| ----------------------------------- | ----- | ------------------------------------ |
| `render(it.f)`, or `render(value)` in a loop | frame | `it` = child, fresh binds |
| `each(…){render(value)}` per iter | frame | `it` = item, binds `{ key }`         |
| `each(…): li(): …` per iter         | scope | `it` = item, binds `{ key, value }`  |
| `@div(~enrich_with: …)` (no loop)   | scope | `it` unchanged, binds = handler result |

For full mechanics see [iteration.md](./iteration.md).
This is why a handler attached to `<div each>` runs against the
*parent* component (the scope is transparent — the surrounding frame
still owns dispatch), while one inside `render(value)` in a loop runs against
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
(seq-access keys like `it.sheets[it.sel_id]` are *pinned* to their
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
value slot — conditions (`show`, a conditional attribute), iteration (`each`,
`each(…){render(value)}`, `~when`), enrichment (`~enrich_with`, `~loop_with`), template
expansion (`{…}`, `:attr`, `@text`) — names a field, handler, or macro
defined on the component (or registered with the scope). Logic lives in
`update` / `compute` and the render buckets (`when` /
`enrich` / `bind_with` / `loop_with`) and is referenced by name; the
template itself only routes data and events.

The one exception is **conditional slots** (`show`, `hide`,
a conditional attribute), which take a whole **expression** — and it is the *same*
expression language a `pred` or a `compute` body is written in, with the
same vocabulary and the same grammar. There is one language, not two that
resemble each other; see [schema.md](./schema.md#the-reading-vocabulary)
for the full table, which serves both halves.

```tutu
spec:
  Conditions:
    field open :: Bool
    field ready :: Bool
    field kind :: String
    field n :: Int
    field items :: List.of(String)

view:
  Conditions:
    show(!it.open):
      div():
        "…"
    show(!it.kind.is_empty()):
      div():
        "…"
    show(it.kind == "a"):
      div():
        "…"
    show(it.items.length() == 1):
      div():
        "…"
    show(it.open && it.ready):
      div():
        "…"
    show((it.n > 0) && it.open):
      div():
        "…"
```

Application is **juxtaposition** (`empty? .items`, `it.title.lower().contains("x")`)
and **parentheses are required wherever precedence would otherwise be
implicit** — so `(.n > 0) and .open` rather than `it.n > 0 && it.open`, and the
error message names the parentheses to add. There is no precedence table to
remember and none to get wrong.

A conditional slot also accepts the plain value forms a hole does — a property
(`show(it.is_open)`), or a loop/scope binding (`show(is_selected)`,
`hide(has_desc)`) — read as a boolean. String literals are `"detail"`, or
`"two words"` for one with spaces.

Two things a *body* can write and a slot cannot, each refused by name: a
nested read (`it.a.b` — render the child as a component, or name it with a
`compute`), and arithmetic.

A macro parameter and `host.config` are ordinary operands here:
`hide(label.is_empty())`, `show(!collapsed)`, `show(host.origin == "x")`.
They are substituted as the value is read, so a parameter still has to expand
to a single token. Going the other way, a `logic:` section can write neither —
it is parsed once for the component, with no macro call site and no host
around it — so read the value in the view and pass it in.

| Form       | Means                                     | Example               |
| ---------- | ----------------------------------------- | --------------------- |
| `it.x`     | property on the component (explicit property before implicit field property) | `it.count`, `it.title` |
| `x(…)`     | a parameterized `compute` call, in a VALUE position only | `format(it.value)` |
| `x`        | a local binding — a loop's, a scope's, or a macro parameter | `key`, `value`, `label` |
| `dyn.x`    | dynamic binding — see [advanced.md](./advanced.md) | `dyn.theme`   |
| `Name`     | component type (PascalCase) — parses, but is in NO value slot: ask for one with `ctx.make("Name", …)` | `Item`, `JsonNull` |
| `"str"`    | string literal                            | `"btn btn-success"`   |
| `@str{…}`  | string template, with `@(…)` holes        | `@str{Hi @(it.name)}` |
| `it.s[k]`  | sequence/map item access                  | `it.by_key[it.current_key]` |
| an expression | anything the reading vocabulary answers | `it.items.is_empty()`, `it.view == "detail"`, `!it.open` |

`it.x` and `x(…)` are not interchangeable: `it.x` reads a property, while
`x(…)` calls a method. `gen` reports a mismatch and names the form to use.

An `~on_<event>: <handler>(<arg>, …)` resolves by position:

- **The handler** — a semantic event name dispatched as `Receive(name, args)`
  to the `update` fn. A property action is written as a write or a collection
  operation instead, for example `it.query := e.value` or
  `it.items.delete_at(key)`.
- **The arguments** — an event read (`e.value`), a state read (`it.field`), or
  a name a loop or an enricher put in scope; anything else is refused.

```tutu
spec:
  Slots:
    message on_add_item(String)

view:
  Slots:
    button(~on_click: on_add_item(e.value)):
      "+"
```

Handler args written in the template arrive in the MoonBit handler's
`args : Array[Value]` in order. The `&Ctx` is **not** an args entry —
the `update` fn receives it as its explicit third parameter, so don't
list `ctx` in the template.

> Port note: the JS docs pass a component **type** as a handler arg
> (`~on_click="onAddItem Item"`). In MoonBit the value language has no
> component-reference value — instead the handler **captures** the
> `Component` in its closure and the view just calls `onAddItem`
> (worked version in [patterns/todo-list.md](./patterns/todo-list.md)).

## Quoting & String Literals

A quoted run is a **literal**: `"flex gap-3"` is those nine characters. A run
that interpolates is written `@str{…}`, with `@(expr)` holes inside it.

| Form                | Example                          | What it is                              |
| ------------------- | -------------------------------- | --------------------------------------- |
| `"string"`          | `~class: "btn ok"`               | a literal, anywhere a value is allowed  |
| `@str{…}`           | `~class: @str{btn @(it.kind)}`   | a template, anywhere a value is allowed |
| bare identifier     | `dec`, `value`                   | a NAME — a handler, a binding, a macro parameter |

```tutu
spec:
  Quoting:
    field color :: String
    field kind :: String

view:
  Quoting:
    p(class: "flex gap-3"):
      "x"
    p(class: @str{flex @(it.color)}):
      "x"
    p(class: @str{btn btn-@(it.kind.lower())}):
      "x"
```

There is no bare-word value: a word with no quotes and no `@` is a NAME, and
it is answered as a handler, a binding or a macro parameter — or refused by
name. That is the whole rule, and it is why `~class: flex gap-3` is not a
class list but two names that answer nothing.

## Derived properties and parameterized computes

A zero-argument derived value is a read-only private property. Declare its type
in the state and implement the getter in `logic:`; every value slot
reads it with `it.name`:

```tutu
spec:
  Form:
    field title :: String

    property label :: String

logic:
  Form:
    property label :: String:
      get: if (it.title == "") | "untitled" | it.title

view:
  Form:
    p():
      @(it.label)
```

A computation that takes arguments remains a method and uses `name(args…)`.

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

```tutu
view:
  Card:
    show(it.can_submit):
      button(class: it.button_class):
        "Save"
    " "
    p(title: @str{Hello, @(it.full_name)}):
      @(it.full_name)
```

The shape predicates (`empty?`, `truthy?`, `null?`) and the operators
cover conditions in a slot directly; reach for a `compute` when the condition
needs derivation, or when naming it makes the view read better.
The handler bodies are typed — no pattern-matching `Value` shapes for
plain struct fields.

Tutuca expressions resolve a **single** name on the state — there is
no path syntax. `@(it.user.name)` does not navigate; it fails. When
the value lives behind a field, your options are:

- **Render the child as a component** — `render(it.user)` then
  `@(it.name)` inside the child's view. Best when the nested thing is
  already (or could be) a component.
- **Add a read-only property** — reading through the value coercers when the
  field is a `@tutuca.Value`:

  ```moonbit nocheck
  // nocheck: a fragment (a match arm or an expression), not a top-level item
  "userName": (s : PageState, _args) => s.user.field("name"),
  ```

  then `@(it.user_name)`. Best for one-off derivations or formatting.
- **Use `~enrich_with`** — exposes computed values as `@`-bindings to a
  subtree without putting them on the component. See *Scope Enrichment*
  in [iteration.md](./iteration.md).

Exceptions: `each` / `each(…){render(value)}` accept `it.field` or `dyn.<name>` only
(not a `handler()` — a computed result has no addressable path for event
dispatch, so `m(…)` is rejected there at parse time), and `render`
expects a component instance — for a derived list, store it in a field
or use `~when` with a `when` entry.

## Text Rendering

```tutu
view:
  Card:
    span():
      @(it.str)
    " "
    comment(): " prepend text into span "
    " "
    @(it.bool)
    " "
    comment(): " text-only, no DOM element "
    " "
    @(it.str_upper)
    " "
    comment(): " derived property "
    " "
    @(value)
    " "
    comment(): " loop binding "
```

Use `@text` when you already have a host element to put the text in; use
a bare `@(…)` hole for bare text with no wrapping element (e.g. text interleaved with
other inline content, or a loop binding). Both take the same value forms
(`it.property`, `method(args…)`, `~binding`). A `Null` text value renders nothing
(not the string `"null"`).

## Attribute Binding

```tutu
view:
  Card:
    input(value: it.str, ~on_input: it.str := e.value)
    " "
    a(href: it.url, title: @str{Hi @(it.name)}):
      "link"
    " "
    comment(): " string template "
    " "
    button(class: @str{btn @(it.color)}):
      "x"
```

Plain attrs are static. `~attr: …` is a dynamic expression. Boolean
HTML attributes (`disabled`, `checked`, `hidden`, …) are auto-recognized;
pass a boolean field. `style` is a plain string attribute like any other
— there is no style-object form.

A static `class="…"` and a dynamic `:class`/a conditional `~class` **cannot coexist on the
same element**: the dynamic value wins and the static class is silently dropped.
Nothing reports it — they are different attribute names to the HTML parser, so no
duplicate-attribute rule fires. Fold any structural classes into the bound expression,
e.g. `~class: @str{btn @(it.color)}` (note `btn` is part of the template, not a
separate `class="btn"`). The same applies to other attributes.

The HTML parser lowercases attribute names before tutuca sees them, so
`:mapId` arrives as `:mapid` and `@Card(…)` becomes `@card(…)`. Three
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
  multi-word value isn't a string — quote it (`~label: "two words"`) or make it
  a template (`~label: @str{@(it.a) @(it.b)}`). `gen` rejects this as
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

```tutu
spec:
  Events:
    field query :: String
    field items :: List.of(String)

    message inc
    message search(String)
    message resize(Int)
    message pick(String, Bool)

view:
  Events:
    button(~on_click: inc):
      "+"
    input(~on_input: search(e.value))
    input(~on_input: resize(e.valueAsInt))
    each(value, key in it.items):
      button(~on_click: pick(key, e.isAlt)):
        "pick"
    input(~on_input: it.query := e.value)
```

The handler **name** is written bare — a leading `$` is refused in an event
position. Its **arguments** carry a sigil that says where the value comes from:
`e.…` reads the DOM event, `it.field` reads state, `~bind` reads a binding. (A bare
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

```tutu
show(it.is_loading): div(): "Loading..."
hide(it.is_loading): div(): "content"

// an expression; `==` compares against a string literal
show(it.view == "detail"): div(): "detail view"

// show / hide wrap whatever they are given — a hole, a render, a loop —
// with no extra DOM element around it
show(it.is_open): @(it.name)
hide(it.is_hidden): render(value)
show(it.is_open): each(value, key in it.items, ~when: filter): render(value)

// a conditional attribute is an `if` expression in the attribute's own value
button(class: if it.is_active | "btn btn-success" | "btn btn-ghost"): ...

// two of them is two attributes, each with its own condition
button(
  class: if it.is_active | "on" | "off",
  title: if it.is_active | "On" | "Off",
): ...
```

> Each conditional attribute carries its own `if`, so two of them on one
> element are two attributes and there is no shared branch to get wrong.

A branch is an **expression**, so a literal class list needs its quotes:
`"btn btn-primary"`, never a bare `btn btn-primary` — which is two names, and
names answer nothing here.

Note: `show` / `hide` **omit the node from the output** when the
condition says hide — they do not merely toggle CSS visibility.

## List Iteration & Scope Enrichment

```tutu
view:
  Card:
    each(value, key in it.items):
      li():
        span():
          @(key)
        ": "
        @(value)
    " "
    each(value, key in it.items):
      render(value)
```

Auto-bound names inside a loop are `@key` and the loop binder. Iteration
(`each` / `each(…){render(value)}`), filtering (`~when` → the `when` bucket),
item and scope enrichment (`~enrich_with` → `enrich` / `bind_with`),
pagination and the `~loop_with` → `loop_with` return shape, and the
`each` lifecycle: see [iteration.md](./iteration.md).

## Rendering Components

```tutu
spec:
  Rendering:
    field item :: Instance
    field mode :: String
    field by_index :: List.of(Instance)
    field by_key :: Map.of(String, Instance)
    field current_index :: Int
    field current_key :: String
    field items :: List.of(Instance)
    field is_open :: Bool

    lookup active

view:
  Rendering:
    render(it.item)
    render(it.item, ~as: "edit")
    render(it.item, ~as: it.mode)
    render(it.by_index[it.current_index])
    render(it.by_key[it.current_key])
    each(value, key in it.items):
      render(value)
    render(dyn.active)
    show(it.is_open):
      render(it.item)
```

A component's views come in through `views=` (a
`Map[String, @anode.View]`), keyed by name — `"main"` is the one rendered by
default. Author them in a `.tutu` file and generate the map with
`tutuca gen` (see [cli.md](./cli.md)). A view whose SOURCE only exists at
run time — a guest bundle, markup a MoonBit function assembles — uses
`@anode.View::new("main", raw_view="…")`, which builds the same `@anode.View`;
its component still declares a schema and a codec like any other. `as` selects
which view of the
rendered component to use, falling back to `main` if absent. It accepts the
same dynamic values as `~push_view` (a literal name like `edit`, or `it.field`,
`dyn.<name>`, `~bind`, `handler()`, `@str{…@(x)…}`), evaluated against the **host**
component at render time. `as` only applies to the **direct** component — for
whole-subtree control, use `~push_view` (next section). For `each(…){render(value)}` the
selector is evaluated once against the host, so every item gets the same view.

## Multiple Views & View Stack

Named views are `Comp.name:` in `view:` entries in the view file:

```tutu
view:
  Note:
    p():
      @(it.title)

  Note.edit:
    input(value: it.title, ~on_input: it.title := e.value)
```

```moonbit nocheck
// nocheck: one expression, shown to make the point that nothing else is needed
note_component() // the wrapper passes both views
```

```tutu
view:
  Card:
    comment(): " ~push_view pushes a name onto the rendering stack; descendants resolve to first matching view, falling back to \"main\" "
    " "
    div(~push_view: it.view):
      each(value, key in it.items):
        render(value)
```

| Directive          | Scope                                                                    |
|--------------------|--------------------------------------------------------------------------|
| `~as: "edit"` / `~as: it.mode` | One `render` element only. Literal or dynamic (like `~push_view`), evaluated against the host. |
| `~push_view=".v"`  | Every component rendered recursively under the host (children + descendants). Each picks the first stack entry it has a matching view for; falls back to `"main"`. Inner `~push_view`s nest, extending the outer ones. |

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

1. a **property action** — `it.x := value`, `it.x := default`, or a collection
   operation such as `it.items.push(value)`. No message name is generated.
2. a **declaration in one of the two blocks** — `receive`, `intent`,
   `compute`, `enrich`, `bindWith` and the `send` / `send(…, ~to: …)` / `intent` /
   `forward` effects in `logic:`; `pred` and `invariant`
   in `spec:`, beside the state they are about. A name a
   block answers is dropped from the generated enum, so the two halves can
   never both claim one handler.
3. a **bucket entry**, for what neither of those says: building a child
   component instance, `~loop_with`, a fold over a whole sequence, a payload
   unpacked out of an `Any` — and anything `gen` prints a
   `script-refusal` for. The block's own reference, and the list of what the
   ahead-of-time backend refuses, are in
   [schema.md](./schema.md#what-the-ahead-of-time-backend-refuses).

| Bucket | Signature | Answers |
| ------ | --------- | ------- |
| `update` | `(S, Dispatch, &Ctx) -> Update[S]` | every event, message and intent; one match over all the channels |
| `compute` | `(S, Array[Value], &Stack) -> Value` | a `name(…)` in a **value** position — pure, no ctx |
| `when` | `(S, key, value, iterData, &Stack) -> Bool` | `~when` iteration filters |
| `enrich` | `(S, binds, key, value, iterData, &Stack) -> Unit` | `~enrich_with` per-item binds |
| `bind_with` | `(S, &Stack) -> Map[String, Value]` | scope-level derived binds |
| `loop_with` | `(S, seq, LoopCtx) -> LoopWith` | `~loop_with` slicing / filtering / key lists |

The four render-time buckets — `compute`, `when`, `enrich`, `bind_with` —
take a trailing `&@tutuca.Stack`: the render position the body is being asked
from. `stack.lookup_dynamic(name)` is what answers a `dyn.<name>` inside one, and it
is the same lookup the card runtime performs for a `dyn.<name>` in a slot beside it, so a
`pred` and the `show` that reads it agree. A body that asks nothing of it
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
views reference, plus the `compute` names `logic:` declares and the
`pred` / `invariant` names `spec:` declares — minus the ones a block
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
answers — `<name>_ok` / `<name>_failed` / `<name>_unhandled` — come back as
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

```tutu
view:
  Card:
    button(~on_click: it.title := "x"):
      "rename"
    " "
    input(~on_input: it.query := e.value)
    " "
    button(~on_click: it.is_open := !it.is_open):
      "toggle"
    " "
    button(~on_click: it.count := default):
      "reset"
```

That is a write, and it reads as one. A name in an event position —
`~on_click="rename"` — is a **message**, and a message needs an answerer. Keeping
the two spellings apart is what stops a typo'd handler named `setTitle` from
silently becoming a field write, and stops a real handler from being shadowed by
the field beside it.

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
// `~on_click: become_editor` — supersede this node with an Editor instance
Receive("becomeEditor", _) => Replace(editor.make({ "text": Str(s.text) }))
```

Reach for `Replace` only for a genuine change of identity; a view that merely
looks different wants `~push_view` or an `~as:` view (see *Multiple Views & View
Stack*).

### The render buckets

`when` / `enrich` / `bind_with` / `loop_with` aren't event-triggered — the
renderer invokes them to filter iterations and produce binds, not state changes
(see *Mental model*, and *Scope Enrichment* in
[iteration.md](./iteration.md)).

## Macros

Pure template expansion, called as `@name(…)`, with a macro parameter references, slots
and named slots: see [macros.md](./macros.md). Declare one in the view file as
`macro card(~title: "Untitled"):` and it is expanded when
the views are generated. `@anode.Macro` values (`{ defaults, raw_view }`)
registered on a `ModuleDef` are the runtime form, for a body a MoonBit
function builds — a file using those cannot be compiled ahead of time.
Registry keys are lowercased — `@Card(…)` resolves as `@card(…)`.

## Raw HTML (escape hatch)

```tutu
view:
  Card:
    div(dangerously_inner_html: it.trusted_html)
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

```tutu
view:
  Card:
    article(inner_md: it.body)
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

Import `marianoguerra/tutuca/vdom/filter/markdown` as `@markdown` and pass
`markdown_filter=@markdown.make_filter` to `App::new`, `App::from_module`,
`app/wasm.mount_in`, or `testing/harness.mount`. The gallery and playground
hosts enable it. Apps that omit it do not link the parser; a Markdown directive
renders empty content and reports the missing configuration.

`App::set_sanitizer` rebuilds the Markdown filter with the new policy.
The mandatory markup and baseline filters remain installed in either case.

Two behaviours worth knowing before you use it: inline HTML tags (`<span>x</span>`
inside a paragraph) render as literal text rather than as markup, and an
unbalanced HTML block does not adopt the markdown that follows it as children.

`it.body` is an ordinary text field, bound like any other; the directive re-parses
it on every render. A worked example — editor on the left, live preview on the
right, and a second half showing what gets refused — is on the landing site
(`playground/site/examples/markdown.{mbt,html}`).

## HTML and SVG (`@setinnerhtml`, `@setinnersvg`)

```tutu
view:
  Card:
    article(inner_html: it.body)
    " "
    svg(viewBox: "0 0 100 100", inner_svg: it.chart)
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

Underneath the typed structs, all state is the `@tutuca.Value` enum — no
persistent-collection library underneath it, just the enum:

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
  `seq_entries` for `each`) — see [iteration.md](./iteration.md)
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
resolved by name at render time (`render(it.child)` finds nothing), and
its examples never reach the storybook or a harness test.

## See also

- [schema.md](./schema.md) — the `spec:` language: field
  spellings, the mutators each kind generates, slots, message buckets,
  `fixtures:` fixtures, and the `pred` / `invariant` rules a component keeps
  with the `format` each says when it fails — plus what the
  `logic:` section beside it declares: `$`-callables,
  `new` / `cur` value building, the `requires` / `ensures` clauses that attach
  a rule to a transition, and the refusal channel that carries a failure.
- [events.md](./events.md) — handler argument names, generated `<Comp>Msg`
  payload types, event modifiers, and custom-element events.
- [iteration.md](./iteration.md) — `each` / `each(…){render(value)}`, `~when`,
  `~enrich_with`, `~loop_with` pagination, and the loop lifecycle.
- [macros.md](./macros.md) — `Macro` definitions, `@name(…)` calls,
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
