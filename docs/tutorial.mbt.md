# Using tutuca (MoonBit)

This is the MoonBit companion to the JS
[tutuca tutorial](https://marianoguerra.github.io/tutuca/tutorial.html): the
same framework, driven from MoonBit. Views — the HTML-ish template strings —
port **verbatim** from JS; what changes is the code around them: state is a
plain MoonBit struct, and every handler is compiler-checked against it.

Every code block below tagged `mbt check` is compiled and executed by
`moon test docs`, so this document cannot drift from the API.

## The mental model

Three rules explain everything else:

1. **State is a single immutable value.** The whole app is one tree of
   `Value`s; component instances are nodes in it.
2. **The view is a pure function of the value.** No subscriptions, no stores,
   no watchers — render the value, get a DOM.
3. **Every handler returns a new state.** An update takes the state struct
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
| `$name` | a **`mutate`/`compute`** call (or a generated mutator) |
| `name` | an **update** dispatch (bare lowercase name, `Input` bucket) |
| `@name` | a local **binding** from iteration or scope enrichment |
| `^name` | a **macro parameter** |
| `*name` | a **dynamic binding** (provide/lookup) |
| `.seq[.key]` | sequence/map **item access** |
| `'text'`, `$'a {.b} c'` | string literal, string template |
| `truthy? .x`, `equals? .a .b` | predicates (predicate-first): `empty?` / `truthy?` / `falsy?` / `null?` / `equals?` |

## Your first component

A component is a plain **state struct** plus a call to
`@component.component(...)`: a name, a view (the template string), the
initial state, and typed handler buckets. The MoonBit port of the canonical
counter:

```mbt check
///|
priv struct CounterState {
  count : Int
} derive(ToJson, FromJson)

///|
fn counter() -> @component.Component {
  @component.component(
    views={
      "main": @anode.View::new(
        "main",
        raw_view=(
          #|<div>
          #|  <button class="dec" @on.click="dec">-</button>
          #|  <span class="count" @text=".count"></span>
          #|  <button class="inc" @on.click="$inc">+</button>
          #|</div>
        ),
      ),
    },
    name="Counter",
    init=CounterState::{ count: 0 },
    // views call update by bare name: @on.click="dec"
    update=(s : CounterState, msg, _ctx) => {
      match msg {
        Input("dec", _) => Some({ count: s.count - 1 })
        _ => None
      }
    },
    // views call mutate with a `$` prefix: @on.click="$inc"
    mutate={ "inc": (s : CounterState, _args) => { count: s.count + 1 } },
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

- **The state struct is the fields.** `derive(ToJson, FromJson)` is the whole
  wiring: field names, defaults (from `init`) and kinds all come from the
  struct, and every handler body is compiler-checked — `s.cuont` is a compile
  error, not a silently-Null render.
- **`update` is one pattern match** over every effectful dispatch:
  `Input(name, args)` for view events, plus `Receive`/`Bubble`/`Response`
  (below). It gets a `ctx` to send messages with; returning `None` means
  "no change".
- **`mutate` entries are pure state changes** callable as `$name`; `compute`
  entries (not needed here) return display values for positions like
  `@text="$label"`.
- Nobody wrote a setter: handlers build a **new** struct
  (`{ count: s.count + 1 }`, or `{ ..s, x: v }` to keep the rest); the
  original is untouched.

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

Every state field generates mutators, so you rarely write setters at all.
Views call them like any `$`-handler (`$setCount`, `$toggleIsOpen`):

| Field kind | Generated (on top of `setX` / `updateX` / `resetX` / `xLen`) |
|---|---|
| Bool | `toggleX` |
| List / Map / OMap | `pushInX`, `insertInXAt`, `setInXAt`, `updateInXAt`, `removeInXAt` (alias `deleteInXAt`) |
| Set | `addInX`, `removeInX` (alias `deleteInX`), `hasInX`, `toggleInX` |

The names keep their JS camelCase spelling on purpose — that is what lets
view strings port verbatim (see `component/component.mbt` for the full list).
Field kinds are inferred from the struct (Bool/String/Int/Double/Array/Map);
Set/OMap kinds and child-component slots are declared via the `specs`
parameter (`FieldSpec::set` / `::omap` / `::comp`).

`:attr="value"` binds state into any attribute, and `$'…{.field}…'` is a
string template:

```mbt check
///|
priv struct ProfileState {
  name : String
  waving : Bool
} derive(ToJson, FromJson)

///|
fn profile_module() -> @component.ModuleDef {
  let profile = @component.component(
    views={
      "main": @anode.View::new(
        "main",
        raw_view=(
          #|<section>
          #|  <input class="who" :value=".name" @on.input="$setName value"
          #|    :title="$'Editing {.name}'" />
          #|  <button class="wave" @on.click="$toggleWaving">wave</button>
          #|  <p class="out" @text="$'Hello, {.name}!'"></p>
          #|</section>
        ),
      ),
    },
    name="Profile",
    init=ProfileState::{ name: "world", waving: false },
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
priv struct SearchState {
  draft : String
  sent : String
} derive(ToJson, FromJson)

///|
fn search_module() -> @component.ModuleDef {
  let search = @component.component(
    views={
      "main": @anode.View::new(
        "main",
        raw_view=(
          #|<section>
          #|  <input class="q" :value=".draft"
          #|    @on.input="$setDraft value"
          #|    @on.keydown+send="$setSent value"
          #|    @on.keydown+cancel="$resetDraft" />
          #|  <p class="sent" @text=".sent"></p>
          #|</section>
        ),
      ),
    },
    name="Search",
    init=SearchState::{ draft: "", sent: "" },
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
priv struct ToggleState {
  on : Bool
  message : @tutuca.Value
} derive(ToJson, FromJson)

///|
fn toggle_module() -> @component.ModuleDef {
  let toggle = @component.component(
    views={
      "main": @anode.View::new(
        "main",
        raw_view=(
          #|<section>
          #|  <button class="flip" @on.click="$toggleOn"
          #|    @if.class=".on" @then="'flip is-on'" @else="'flip is-off'">toggle</button>
          #|  <p class="yes" @show=".on">it is ON</p>
          #|  <p class="no" @hide=".on">it is OFF</p>
          #|  <p class="msg" @show="truthy? .message" @text=".message"></p>
          #|</section>
        ),
      ),
    },
    name="Toggle",
    init=ToggleState::{ on: false, message: Null },
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

A field that can hold "anything" (here: `message` starts as Null) is declared
as `@tutuca.Value` — the dynamic escape hatch inside an otherwise typed
struct. That includes fields holding component instances or functions: they
survive state updates untouched.

There are no dotted paths in values — `.user.name` is not a thing. Render a
child component, add a `compute`, or use `@enrich-with` (below) instead.

## Lists

`@each=".items"` repeats its element once per entry, binding `@key` (index or
map key) and `@value`. Each loop directive has its own **typed bucket**:
`@when="name"` filters through the `when` bucket, `@enrich-with` adds
bindings per item through `enrich`, `@loop-with` computes shared per-loop
data once through `loop_with`:

```mbt check
///|
priv struct FruitsState {
  items : Array[String]
} derive(ToJson, FromJson)

///|
fn fruits_module() -> @component.ModuleDef {
  let fruits = @component.component(
    views={
      "main": @anode.View::new(
        "main",
        raw_view=(
          #|<ul>
          #|  <li @each=".items" @when="notTooLong">
          #|    <span class="k" @text="@key"></span>: <x text="@value"></x>
          #|  </li>
          #|</ul>
        ),
      ),
    },
    name="Fruits",
    init=FruitsState::{ items: [] },
    when={
      // (state, key, value, iter_data) -> Bool: true keeps the item
      "notTooLong": (_s : FruitsState, _key, value, _iter) => {
        value.str().length() <= 6
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
  debug_inspect(
    h.texts(".k"),
    content=(
      #|["0", "2"]
    ),
  )
  inspect(h.text("li"), content="0: apple")
}
```

(`<x text="@value">` is the standalone form of `@text` — a text node with no
wrapping element. Loop keys and values arrive as `@tutuca.Value`; the
coercers `.str()`, `.int()`, `.bool()`, `.list()`, `.field("x")` read them.)

The four render-time buckets, by directive:

| Directive | Bucket | Signature |
|---|---|---|
| `@when` | `when` | `(S, key, value, iter_data) -> Bool` |
| `@enrich-with` (with `@each`) | `enrich` | `(S, binds, key, value, iter_data) -> Unit` — mutate `binds` |
| `@enrich-with` (no `@each`) | `enrich_scope` | `(S) -> Map[String, Value]` — the returned keys become `@`-bindings |
| `@loop-with` | `loop_with` | `(S, seq, LoopCtx) -> LoopWith` — `LoopWith::new(start=…, end=…, keys=…, iter_data=…)` |

See `storybook/examples/collections.mbt` for all four in action.

## Composing components

A field can hold another component: a `specs` entry with
`FieldSpec::comp("Name")` resolves the component by name at `make()` time
through the registration scope. `<x render=".field">` renders it;
`as="viewName"` picks one of its named `views`. The child gets a clean
namespace — the parent's bindings do not leak in.

```mbt check
///|
priv struct GreetingState {
  name : String
} derive(ToJson, FromJson)

///|
priv struct NoState {} derive(ToJson, FromJson)

///|
fn page_module() -> @component.ModuleDef {
  let greeting = @component.component(
    views={
      "main": @anode.View::new(
        "main",
        raw_view=(
          #|<p class="hello">Hello, <strong @text=".name"></strong>!</p>
        ),
      ),
      "shout": @anode.View::new(
        "shout",
        raw_view=(
          #|<p class="hello">HELLO, <strong @text=".name"></strong>!!!</p>
        ),
      ),
    },
    name="Greeting",
    init=GreetingState::{ name: "world" },
  )
  let page = @component.component(
    views={
      "main": @anode.View::new(
        "main",
        raw_view=(
          #|<section>
          #|  <x render=".greeting"></x>
          #|  <x render=".greeting" as="shout"></x>
          #|</section>
        ),
      ),
    },
    name="Page",
    init=NoState::{  },
    specs={
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
  debug_inspect(
    h.texts(".hello"),
    content=(
      #|["Hello, reader!", "HELLO, reader!!!"]
    ),
  )
}
```

Child slots declared via `specs` live outside the state struct — the parent
renders and messages them, it does not read them. A parent that must *hold*
child instances in its own logic (a tree of nodes, a list of made children)
declares a `@tutuca.Value` (or `Array[@tutuca.Value]`) field instead.

Related render ops: `<x render-it>` renders the current `@value` inside a
loop, `<x render-each=".items">` is `@each` + `render-it` in one (this is how
recursive components like trees work — see
`storybook/examples/communication.mbt`), and `@push-view=".view"` makes every
descendant `<x render>` prefer that view name.

## Communication: send, bubble, request

Components message each other **by path**, never by reference — and every
incoming message lands in the same `update` match:

- `ctx.send(name, args)` — dispatch `Receive(name, args)` on *self*.
- `ctx.send_at_path(path, name, args)` — dispatch on the component at a path;
  address a child with `ctx.path().concat([FieldStep("field")])` (JS:
  `ctx.at.field("x").send(...)`).
- `ctx.bubble(name, args)` — walk up the ancestors as `Bubble(name, args)`;
  `ctx.stop_propagation()` stops it.
- `ctx.request(name, args, opts)` — fire an async request; the result comes
  back as `Response(name, [result, error])`.

```mbt check
///|
priv struct StatusState {
  message : String
} derive(ToJson, FromJson)

///|
priv struct ChatState {
  draft : String
} derive(ToJson, FromJson)

///|
fn chat_module() -> @component.ModuleDef {
  let status = @component.component(
    views={
      "main": @anode.View::new(
        "main",
        raw_view=(
          #|<p class="status" @show="truthy? .message" @text=".message"></p>
        ),
      ),
    },
    name="Status",
    init=StatusState::{ message: "" },
    update=(_s : StatusState, msg, _ctx) => {
      match msg {
        Receive("flash", [Str(m), ..]) => Some({ message: m })
        _ => None
      }
    },
  )
  let chat = @component.component(
    views={
      "main": @anode.View::new(
        "main",
        raw_view=(
          #|<section>
          #|  <x render=".status"></x>
          #|  <input class="draft" :value=".draft" @on.input="$setDraft value" />
          #|  <button class="send" @on.click="submit">send</button>
          #|</section>
        ),
      ),
    },
    name="Chat",
    init=ChatState::{ draft: "" },
    specs={ "status": @component.FieldSpec::comp("Status") },
    update=(s : ChatState, msg, ctx) => {
      match msg {
        Input("submit", _) => {
          guard s.draft != "" else { None }
          // message the child at .status — the path is the only coupling
          ctx.send_at_path(ctx.path().concat([FieldStep("status")]), "flash", [
            Str(s.draft),
          ])
          Some({ draft: "" })
        }
        _ => None
      }
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
`respond(Ok(v))` or `respond(Err(e))` whenever it is done. The result comes
back as `Response(name, [result, error])` (or route with
`RequestOpts::new(on_ok_name=..., on_error_name=...)`).

Tutuca has no lifecycle hooks: nothing calls "init" for you. The host
dispatches it after start — that is what `send_at_root` is for.

```mbt check
///|
priv struct QuotesState {
  items : Array[String]
  isLoading : Bool
} derive(ToJson, FromJson)

///|
fn quotes_module() -> @component.ModuleDef {
  let quotes = @component.component(
    views={
      "main": @anode.View::new(
        "main",
        raw_view=(
          #|<section>
          #|  <p class="loading" @show=".isLoading">Loading…</p>
          #|  <ul><li @each=".items"><x text="@value"></x></li></ul>
          #|</section>
        ),
      ),
    },
    name="Quotes",
    init=QuotesState::{ items: [], isLoading: false },
    update=(s : QuotesState, msg, ctx) => {
      match msg {
        Receive("init", _) => {
          ctx.request("loadQuotes", [], @tutuca.RequestOpts::new())
          Some({ ..s, isLoading: true })
        }
        Response("loadQuotes", [List(rows), _err]) =>
          Some({ items: rows.map(r => r.str()), isLoading: false })
        _ => None
      }
    },
  )
  @component.ModuleDef::new(name="quotes", components=[quotes], requests={
    "loadQuotes": RequestFn((_args, respond) => {
      respond(Ok(List([Str("less, but better"), Str("fits in your head")])))
    }),
  })
}

///|
test "request round-trip: init → request → response" {
  let h = @harness.mount(quotes_module(), "Quotes")
  h.send_at_root("init") // the host-driven lifecycle
  debug_inspect(
    h.texts("li"),
    content=(
      #|["less, but better", "fits in your head"]
    ),
  )
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
priv struct FeaturesState {
  status : String
} derive(ToJson, FromJson)

///|
fn badge_module() -> @component.ModuleDef {
  let badge : @anode.Macro = {
    defaults: { "label": "'New'" },
    raw_view: "<span class=\"badge\" @text=\"^label\"></span>",
  }
  let features = @component.component(
    views={
      "main": @anode.View::new(
        "main",
        raw_view=(
          #|<div>
          #|  <span>Feature A</span> <x:badge></x:badge>
          #|  <span>Feature B</span> <x:badge label="Beta"></x:badge>
          #|  <span>Feature C</span> <x:badge :label=".status"></x:badge>
          #|</div>
        ),
      ),
    },
    name="Features",
    init=FeaturesState::{ status: "Soon" },
  )
  @component.ModuleDef::new(name="badges", components=[features], macros={
    "badge": badge,
  })
}

///|
test "macros: defaults, static and dynamic parameters" {
  let h = @harness.mount(badge_module(), "Features")
  debug_inspect(
    h.texts(".badge"),
    content=(
      #|["New", "Beta", "Soon"]
    ),
  )
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
  let app = try! @app.App::from_module(
    m,
    "Counter",
    root_node,
    @bdom.opts_for(doc),
  )
  @glue.install(app) // delegated event listeners at the root
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
