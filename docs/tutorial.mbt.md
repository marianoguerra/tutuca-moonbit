# Using tutuca (MoonBit)

This is the MoonBit companion to the JS
[tutuca tutorial](https://marianoguerra.github.io/tutuca/tutorial.html): the
same framework, driven from MoonBit. Views — the HTML-ish template strings —
port **verbatim** from JS; what changes is the code around them.

Every code block below tagged `mbt check` is compiled and executed by
`moon test docs`, so this document cannot drift from the API.

## The mental model

Three rules explain everything else:

1. **State is a single immutable value.** The whole app is one tree of
   `Value`s; component instances are nodes in it.
2. **The view is a pure function of the value.** No subscriptions, no stores,
   no watchers — render the value, get a DOM.
3. **Every handler returns a new self.** An event handler takes the instance
   and returns a replacement; the framework swaps it into the tree
   (copy-on-write, so untouched siblings keep their identity) and re-renders
   once per interaction.

Components never hold references to each other — they communicate by **path**
(`send`, `bubble`, `request`), and events are not wired as DOM listeners:
they are delegated at the root and routed back through the tree.

## Notation reference

The template language uses one-character sigils, each mapping to one way of
resolving a name:

| Syntax | Meaning |
|---|---|
| `.name` | a component **field** (single level — no dotted paths) |
| `$name` | a **method** call (or a generated mutator) |
| `name` | an **input handler** (bare lowercase name) |
| `@name` | a local **binding** from iteration or scope enrichment |
| `^name` | a **macro parameter** |
| `*name` | a **dynamic binding** (provide/lookup) |
| `.seq[.key]` | sequence/map **item access** |
| `'text'`, `$'a {.b} c'` | string literal, string template |
| `truthy? .x`, `equals? .a .b` | predicates (predicate-first): `empty?` / `truthy?` / `falsy?` / `null?` / `equals?` |

## Your first component

A component is built with `@component.component(...)`: a name, a view (the
template string), typed fields, and handler buckets. The MoonBit port of the
canonical counter:

```mbt check
///|
fn counter() -> @component.Component {
  @component.component(
    name="Counter",
    view=(
      #|<div>
      #|  <button class="dec" @on.click="dec">-</button>
      #|  <span class="count" @text=".count"></span>
      #|  <button class="inc" @on.click="$inc">+</button>
      #|</div>
    ),
    fields={ "count": @component.FieldSpec::of_default(Num(0)) },
    methods={
      // views call methods with a `$` prefix: @on.click="$inc"
      "inc": (inst, _args) => {
        match inst.get("count") {
          Num(n) => inst.set("count", Num(n + 1)).to_value()
          _ => inst.to_value()
        }
      },
    },
    input={
      // views call input handlers by bare name: @on.click="dec"
      "dec": (inst, _args, _ctx) => {
        match inst.get("count") {
          Num(n) => Some(inst.set("count", Num(n - 1)))
          _ => None
        }
      },
    },
  )
}

///|
/// A ModuleDef bundles components (+ macros + request handlers + examples).
/// One ModuleDef value drives the tests, the storybook gallery and the CLI.
fn counter_module() -> @component.ModuleDef {
  @component.ModuleDef::new(name="counter", components=[counter()])
}
```

Things to notice:

- **Fields are typed by their default.** `FieldSpec::of_default(Num(0))`
  infers a number field; `Str`, `Bool`, `List`, `Map`, `Null` work the same
  way (`Null` = any).
- **`methods` are pure**: `(Instance, Array[Value]) -> Value`. They are also
  evaluated in *value* positions (`@text="$label"`), where no event exists.
- **`input` handlers are effectful**: `(Instance, Array[Value], &Ctx) ->
  Instance?`. They get a `ctx` to send messages with; returning `None` means
  "no change". A handler that needs `ctx` goes in `input`, not `methods`.
- Nobody wrote a setter: `inst.set` returns a **new** instance; the original
  is untouched.

## Test it as you write it

`@harness.mount` runs a module as a live app on the in-memory DOM. `click`,
`type_into`, `key_down` dispatch *real* events through the whole pipeline
(event routing, transactor, re-render), and `text`/`attr`/`html` query the
resulting DOM by CSS selector:

```mbt check
///|
test "counter: clicks flow through the whole framework" {
  let h = @harness.mount(counter_module(), "Counter")
  inspect(h.text(".count"), content="0")
  h.click(".inc") // @on.click="$inc"
  inspect(h.text(".count"), content="1")
  h.click(".dec") // @on.click="dec"
  h.click(".dec")
  inspect(h.text(".count"), content="-1")
}

///|
test "counter: one re-render per interaction (batching)" {
  let h = @harness.mount(counter_module(), "Counter", args={ "count": Num(10) })
  let before = h.render_count()
  h.click(".inc")
  inspect(h.text(".count"), content="11")
  assert_eq(h.render_count(), before + 1)
}
```

The `args` map overrides field defaults at mount time — the same mechanism the
storybook uses to show one component in several states.

## Fields and generated mutators

Every field generates mutators, so you rarely write setters by hand. Views
call them like any method (`$setCount`, `$toggleIsOpen`):

| Field kind | Generated (on top of `setX` / `updateX` / `resetX` / `xLen`) |
|---|---|
| Bool | `toggleX` |
| List / Map / OMap | `pushInX`, `insertInXAt`, `setInXAt`, `updateInXAt`, `removeInXAt` (alias `deleteInXAt`) |
| Set | `addInX`, `removeInX` (alias `deleteInX`), `hasInX`, `toggleInX` |

The names keep their JS camelCase spelling on purpose — that is what lets
view strings port verbatim (see `component/component.mbt` for the full list).

`:attr="value"` binds state into any attribute, and `$'…{.field}…'` is a
string template:

```mbt check
///|
fn profile_module() -> @component.ModuleDef {
  let profile = @component.component(
    name="Profile",
    view=(
      #|<section>
      #|  <input class="who" :value=".name" @on.input="$setName value"
      #|    :title="$'Editing {.name}'" />
      #|  <button class="wave" @on.click="$toggleWaving">wave</button>
      #|  <p class="out" @text="$'Hello, {.name}!'"></p>
      #|</section>
    ),
    fields={
      "name": @component.FieldSpec::of_default(Str("world")),
      "waving": @component.FieldSpec::of_default(Bool(false)),
    },
  )
  @component.ModuleDef::new(name="profile", components=[profile])
}

///|
test "generated mutators: setName and toggleWaving exist unwritten" {
  let h = @harness.mount(profile_module(), "Profile")
  h.type_into(".who", "tutuca") // fires @on.input → $setName value
  inspect(h.text(".out"), content="Hello, tutuca!")
  inspect(h.attr(".who", "title").unwrap_or(""), content="Editing tutuca")
}
```

`value` in `@on.input="$setName value"` is an event-supplied argument: the
input's current value. Other event names available in handler-argument
position include `key`, `isCtrl`, `isShift`, and (for drag & drop)
`dragInfo`.

## Event modifiers

`@on.<event>+<modifier>` gates when the handler fires: `+send` means Enter,
`+cancel` means Escape, `+ctrl` / `+cmd` / `+meta` / `+alt` require the
matching modifier key. They combine with `+`:

```mbt check
///|
fn search_module() -> @component.ModuleDef {
  let search = @component.component(
    name="Search",
    view=(
      #|<section>
      #|  <input class="q" :value=".draft"
      #|    @on.input="$setDraft value"
      #|    @on.keydown+send="$setSent value"
      #|    @on.keydown+cancel="$resetDraft" />
      #|  <p class="sent" @text=".sent"></p>
      #|</section>
    ),
    fields={
      "draft": @component.FieldSpec::of_default(Str("")),
      "sent": @component.FieldSpec::of_default(Str("")),
    },
  )
  @component.ModuleDef::new(name="search", components=[search])
}

///|
test "modifiers: Enter sends, Escape clears" {
  let h = @harness.mount(search_module(), "Search")
  h.type_into(".q", "hello")
  h.key_down(".q", "Enter", value=Str("hello")) // +send fires only on Enter
  inspect(h.text(".sent"), content="hello")
  h.key_down(".q", "Escape") // +cancel resets draft to its default
  inspect(h.value_of(".q"), content="")
}
```

## Conditional display and attributes

`@show` keeps its element only when the value is truthy, `@hide` only when it
is falsy. **The node is removed from the output entirely**, not hidden with
CSS. Any value works, including predicates. `@if.<attr>` / `@then` / `@else`
choose between two attribute values:

```mbt check
///|
fn toggle_module() -> @component.ModuleDef {
  let toggle = @component.component(
    name="Toggle",
    view=(
      #|<section>
      #|  <button class="flip" @on.click="$toggleOn"
      #|    @if.class=".on" @then="'flip is-on'" @else="'flip is-off'">toggle</button>
      #|  <p class="yes" @show=".on">it is ON</p>
      #|  <p class="no" @hide=".on">it is OFF</p>
      #|  <p class="msg" @show="truthy? .message" @text=".message"></p>
      #|</section>
    ),
    fields={
      "on": @component.FieldSpec::of_default(Bool(false)),
      "message": @component.FieldSpec::of_default(Null),
    },
  )
  @component.ModuleDef::new(name="toggle", components=[toggle])
}

///|
test "@show/@hide remove the node; @if picks the attribute" {
  let h = @harness.mount(toggle_module(), "Toggle")
  inspect(h.find_all(".yes").length(), content="0") // gone, not display:none
  inspect(h.text(".no"), content="it is OFF")
  inspect(h.attr(".flip", "class").unwrap_or(""), content="flip is-off")
  h.click(".flip")
  inspect(h.text(".yes"), content="it is ON")
  inspect(h.find_all(".no").length(), content="0")
  inspect(h.attr(".flip", "class").unwrap_or(""), content="flip is-on")
}
```

There are no dotted paths in values — `.user.name` is not a thing. Render a
child component, add a method, or use `@enrich-with` (below) instead.

## Lists

`@each=".items"` repeats its element once per entry, binding `@key` (index or
map key) and `@value`. `@when="handlerName"` filters with an `alter` handler,
`@enrich-with` adds bindings per item, `@loop-with` computes shared per-loop
data once:

```mbt check
///|
fn fruits_module() -> @component.ModuleDef {
  let fruits = @component.component(
    name="Fruits",
    view=(
      #|<ul>
      #|  <li @each=".items" @when="notTooLong">
      #|    <span class="k" @text="@key"></span>: <x text="@value"></x>
      #|  </li>
      #|</ul>
    ),
    fields={ "items": @component.FieldSpec::of_default(List([])) },
    alter={
      // @when args: [key, value, iterData] — truthy keeps the item
      "notTooLong": (_inst, args) => {
        match args {
          [_key, Str(s), ..] => Bool(s.length() <= 6)
          _ => Bool(true)
        }
      },
    },
  )
  @component.ModuleDef::new(name="fruits", components=[fruits])
}

///|
test "@each iterates, @when filters" {
  let h = @harness.mount(fruits_module(), "Fruits", args={
    "items": List([Str("apple"), Str("watermelon"), Str("plum")]),
  })
  debug_inspect(h.texts(".k"), content=(
    #|["0", "2"]
  ))
  inspect(h.text("li"), content="0: apple")
}
```

(`<x text="@value">` is the standalone form of `@text` — a text node with no
wrapping element.)

The `alter` bucket holds pure helpers callable from these loop positions; the
renderer calls them with fixed argument shapes (see
`storybook/examples/collections.mbt` for `@enrich-with` and `@loop-with` in
action, including the scope form of `@enrich-with` — on an element *without*
`@each`, it returns a map whose keys become `@`-bindings for the subtree).

## Composing components

A field can hold another component: `FieldSpec::comp("Name")` resolves the
component by name at `make()` time through the registration scope. `<x
render=".field">` renders it; `as="viewName"` picks one of its named `views`.
The child gets a clean namespace — the parent's bindings do not leak in.

```mbt check
///|
fn page_module() -> @component.ModuleDef {
  let greeting = @component.component(
    name="Greeting",
    view=(
      #|<p class="hello">Hello, <strong @text=".name"></strong>!</p>
    ),
    views={
      "shout": (
        #|<p class="hello">HELLO, <strong @text=".name"></strong>!!!</p>
      ),
    },
    fields={ "name": @component.FieldSpec::of_default(Str("world")) },
  )
  let page = @component.component(
    name="Page",
    view=(
      #|<section>
      #|  <x render=".greeting"></x>
      #|  <x render=".greeting" as="shout"></x>
      #|</section>
    ),
    fields={
      "greeting": @component.FieldSpec::comp("Greeting", args={
        "name": Str("reader"),
      }),
    },
  )
  @component.ModuleDef::new(name="page", components=[page, greeting])
}

///|
test "one child value, two views of it" {
  let h = @harness.mount(page_module(), "Page")
  debug_inspect(h.texts(".hello"), content=(
    #|["Hello, reader!", "HELLO, reader!!!"]
  ))
}
```

Related render ops: `<x render-it>` renders the current `@value` inside a
loop, `<x render-each=".items">` is `@each` + `render-it` in one (this is how
recursive components like trees work — see
`storybook/examples/communication.mbt`), and `@push-view=".view"` makes every
descendant `<x render>` prefer that view name.

## Communication: send, bubble, request

Components message each other **by path**, never by reference:

- `ctx.send(name, args)` — dispatch a `receive` handler on *self*.
- `ctx.send_at_path(path, name, args)` — dispatch on the component at a path;
  address a child with `ctx.path().concat([FieldStep("field")])` (JS:
  `ctx.at.field("x").send(...)`).
- `ctx.bubble(name, args)` — walk up the ancestors' `bubble` buckets;
  `ctx.stop_propagation()` stops it.
- `ctx.request(name, args, opts)` — fire an async request; the result comes
  back through the `response` bucket.

```mbt check
///|
fn chat_module() -> @component.ModuleDef {
  let status = @component.component(
    name="Status",
    view=(
      #|<p class="status" @show="truthy? .message" @text=".message"></p>
    ),
    fields={ "message": @component.FieldSpec::of_default(Str("")) },
    receive={
      "flash": (inst, args, _ctx) => {
        match args {
          [Str(msg), ..] => Some(inst.set("message", Str(msg)))
          _ => None
        }
      },
    },
  )
  let chat = @component.component(
    name="Chat",
    view=(
      #|<section>
      #|  <x render=".status"></x>
      #|  <input class="draft" :value=".draft" @on.input="$setDraft value" />
      #|  <button class="send" @on.click="submit">send</button>
      #|</section>
    ),
    fields={
      "status": @component.FieldSpec::comp("Status"),
      "draft": @component.FieldSpec::of_default(Str("")),
    },
    input={
      "submit": (inst, _args, ctx) => {
        guard inst.get("draft") is Str(text) && text != "" else { None }
        // message the child at .status — the path is the only coupling
        ctx.send_at_path(ctx.path().concat([FieldStep("status")]), "flash", [
          Str(text),
        ])
        Some(inst.set("draft", Str("")))
      },
    },
  )
  @component.ModuleDef::new(name="chat", components=[chat, status])
}

///|
test "send_at_path messages a sibling-owned child" {
  let h = @harness.mount(chat_module(), "Chat")
  h.type_into(".draft", "hi there")
  h.click(".send")
  inspect(h.text(".status"), content="hi there")
  inspect(h.value_of(".draft"), content="")
}
```

### Async requests

A request handler lives *outside* the component, registered on the module —
so the same component runs against a real fetch in production and a fixture
in tests. `RequestFn` is callback-style: `(args, respond) -> Unit`, calling
`respond(Ok(v))` or `respond(Err(e))` whenever it is done. The `response`
bucket named like the request receives `[result, error]` (or route with
`RequestOpts::new(on_ok_name=..., on_error_name=...)`).

Tutuca has no lifecycle hooks: nothing calls "init" for you. The host
dispatches it after start — that is what `send_at_root` is for.

```mbt check
///|
fn quotes_module() -> @component.ModuleDef {
  let quotes = @component.component(
    name="Quotes",
    view=(
      #|<section>
      #|  <p class="loading" @show=".isLoading">Loading…</p>
      #|  <ul><li @each=".items"><x text="@value"></x></li></ul>
      #|</section>
    ),
    fields={
      "items": @component.FieldSpec::of_default(List([])),
      "isLoading": @component.FieldSpec::of_default(Bool(false)),
    },
    receive={
      "init": (inst, _args, ctx) => {
        ctx.request("loadQuotes", [], @tutuca.RequestOpts::new())
        Some(inst.set("isLoading", Bool(true)))
      },
    },
    response={
      "loadQuotes": (inst, args, _ctx) => {
        match args {
          [List(rows), _err] =>
            Some(inst.set("items", List(rows)).set("isLoading", Bool(false)))
          _ => None
        }
      },
    },
  )
  @component.ModuleDef::new(
    name="quotes",
    components=[quotes],
    requests={
      "loadQuotes": RequestFn((_args, respond) => respond(
        Ok(List([Str("less, but better"), Str("fits in your head")])),
      )),
    },
  )
}

///|
test "request round-trip: init → request → response" {
  let h = @harness.mount(quotes_module(), "Quotes")
  h.send_at_root("init") // the host-driven lifecycle
  debug_inspect(h.texts("li"), content=(
    #|["less, but better", "fits in your head"]
  ))
  inspect(h.find_all(".loading").length(), content="0")
}
```

## Macros

A macro is pure template expansion — no state, no handlers of its own. In
MoonBit it is the record `@anode.Macro::{ defaults, raw_view }`; `defaults`
maps a parameter name to its default *source text* (a string default keeps
its quotes: `"'New'"`). Call it as `<x:name>`; read parameters with `^name`;
`<x:slot>` marks where the call's children land. Handlers used inside a macro
run against the component the macro expands into.

```mbt check
///|
fn badge_module() -> @component.ModuleDef {
  let badge : @anode.Macro = {
    defaults: { "label": "'New'" },
    raw_view: "<span class=\"badge\" @text=\"^label\"></span>",
  }
  let features = @component.component(
    name="Features",
    view=(
      #|<div>
      #|  <span>Feature A</span> <x:badge></x:badge>
      #|  <span>Feature B</span> <x:badge label="Beta"></x:badge>
      #|  <span>Feature C</span> <x:badge :label=".status"></x:badge>
      #|</div>
    ),
    fields={ "status": @component.FieldSpec::of_default(Str("Soon")) },
  )
  @component.ModuleDef::new(name="badges", components=[features], macros={
    "badge": badge,
  })
}

///|
test "macros: defaults, static and dynamic parameters" {
  let h = @harness.mount(badge_module(), "Features")
  debug_inspect(h.texts(".badge"), content=(
    #|["New", "Beta", "Soon"]
  ))
}
```

A plain attribute (`label="Beta"`) passes a static string; a `:`-prefixed one
(`:label=".status"`) passes an expression. See
`storybook/examples/macros.mbt` for slots and named slots.

## Running it for real

Everything above ran on the in-memory DOM. The same `ModuleDef` mounts in a
browser (js backend) via `App::from_module` plus the glue that installs the
delegated event listeners:

```mbt nocheck
///|
fn main {
  let m = counter_module()
  let doc = @dom.window().document()
  guard doc.getElementById("app") is Some(root_el) else { return }
  let root_node = @bdom.BrowserNode::from_element(root_el)
  let app = try! @app.App::from_module(m, "Counter", root_node, @bdom.opts_for(doc))
  @glue.install(app)          // delegated event listeners at the root
  @glue.install_styles(app, @bdom.BrowserNode::from_document(doc))
}
```

(`@bdom` = `vdom/browser`, `@glue` = `app/browser`; see `demo/counter` for
the full package. `demo/counter_wasm` + `app/wasm` is the wasm-gc twin.)

The native CLI works on modules too:

```sh
moon run --target native cmd/main -- render <example>   # render to HTML
moon run --target native cmd/main -- lint <view>        # lint a view
moon run --target native cmd/dev -- dist                # build demos + storybook
```

## Where to go next

- `storybook/examples/` — 40 ported modules in tutorial order (drag & drop,
  provide/lookup dynamic bindings, SVG, big apps), each with interaction
  tests; `storybook/examples/README.md` documents the JS→MoonBit porting
  rules.
- [`first_principles.mbt.md`](first_principles.mbt.md) — the same framework
  rebuilt layer by layer, if you want to know *why* it works.
- `testing/harness` — the full harness API (`fire`, `drag`, `check`, `prop`,
  `styles`, …).
