# Tutuca — Core (MoonBit port)

Tutuca is an immutable-state web framework: a component is a plain typed
**state struct** plus handler buckets — auto-generated mutators (`setX`,
`pushInX`, …), HTML-template `view`s with `@`-prefixed directives, and one
`update` dispatch match for orchestration. This is the **MoonBit port**
(`marianoguerra/tutuca`): the template language is identical to the JS
original, but everything around the views — component definition, state,
handlers, testing, CLI — is MoonBit. Read this file when authoring or
reviewing `@component.component(...)` definitions, view templates, macros,
or when using the embedded `tutuca` CLI.

> Load the topic files only when the task touches them (the routing
> table in [SKILL.md](./SKILL.md) has the full descriptions):
> [iteration.md](./iteration.md) · [macros.md](./macros.md) ·
> [styles.md](./styles.md) · [request-response.md](./request-response.md) ·
> [component-design.md](./component-design.md) · [testing.md](./testing.md) ·
> [cli.md](./cli.md) · [semantics.md](./semantics.md) ·
> [advanced.md](./advanced.md) · [margaui.md](./margaui.md) ·
> [patterns/README.md](./patterns/README.md).

## Verifying changes

After editing a tutuca module, run these checks before declaring the
edit done:

1. **Lint the module** — catches undefined fields/handlers/macros/events
   (all the `*_NOT_DEFINED` / `*_NOT_REFERENCED` codes):

        tutuca lint
        tutuca lint Button        # scope to one component

   `tutuca` is the project's embedded CLI binary (a `main` calling
   `@cli.plan_with_module` with the project's `ModuleDef` — see
   [cli.md](./cli.md)). Exits `2` on any error-level finding.

2. **Test component behavior** — when the edit changes handlers,
   field coercion, or interaction flows (anything observable beyond a
   single static render), run the test suite:

        moon test                       # the package's test blocks
        moon test -p examples           # one package
        moon test --update              # refresh inspect/debug_inspect snapshots

   There is **no `tutuca test` command** — `moon test` is the runner, and
   component tests are plain `test "..." { ... }` blocks that mount the
   module on the in-memory DOM via the
   `marianoguerra/tutuca/testing/harness` package and assert with
   MoonBit's built-ins. Skip this step when the change is purely
   templates/styling — `render` already covers that. Authoring patterns
   (the harness API, designing handlers for testability, worked test
   blocks) in [testing.md](./testing.md).

3. **Render the example(s) that exercise the feature you changed** —
   confirms the component actually mounts in a headless DOM with the new
   behavior. Pick the example whose `title` matches the feature, or
   filter by component:

        tutuca render --title "Disabled state"
        tutuca render Button

   Exits `3` if a render crashes. If no example covers the feature
   you're adding, add an `ExampleDef` to the `ModuleDef` first — that's
   how the feature becomes verifiable (see
   [patterns/add-an-example.md](./patterns/add-an-example.md)). Add
   `--pretty` when you need to read the emitted HTML to verify structure
   (attributes, nesting, text); omit it when you only care that the
   render didn't crash.

Full reference: [cli.md](./cli.md).

The tutuca CLI only catches tutuca-specific issues. For general MoonBit
problems, pair it with the `moon` toolchain: `moon check` (all targets),
`moon fmt`, and `moon info` to regenerate the `.mbti` interface files.

## Common pitfalls

- **`.name` reads a field, `$name` calls a `$`-handler.** The two are
  distinct prefixes: `.count` reads field `count`, `$inc` calls the
  `mutate`/`compute` entry (or generated mutator) `inc`. Using the wrong
  one is a lint error that tells you to swap the prefix.
- **Handlers that need `ctx` go in `update`, not `mutate`/`compute`.**
  A `mutate` entry is pure — `(s, args) => S` — and a `compute` entry is
  pure — `(s, args) => Value` — because `$`-callables are also evaluated
  in value positions (`@text="$label"`), where no event exists. The
  `update` fn — `(s, msg, ctx) => S?` — gets the `&Ctx` and can
  `ctx.send` / `ctx.request`. The template syntax is unchanged (`$name`
  for `$`-handlers, bare `name` for update-dispatched events).
- **`update` returns `S?`; `None` means "no change".** Returning `None`
  leaves the root untouched (a cheap no-op); return `Some(new_state)` to
  commit. The match must be total — always end with `_ => None`.
- **Paths are not allowed in values.** `.foo` resolves a single field on
  the state — `@text=".foo.bar"`, `:value=".user.name"`,
  `@show=".item.isOpen"` all fail. To reach into nested data: render the
  child as a component (`<x render=".foo">` then `@text=".bar"` inside),
  add a `compute` entry (read the nested value off a `@tutuca.Value`
  field with `v.field("name")` — use `$fullName`), or use `@enrich-with`
  for scope-level derivation. The one exception: a **binding** may read
  exactly one **binding member** — `@text="@value.title"` inside `@each`
  works (any `@`-binding, one level only; `@value.a.b` is a lint error,
  and render targets still reject it).
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
  first element is trimmed, but a whitespace-only view renders blank
  silently. Write views as `#|` raw strings starting at the opening tag.
- **Macro registry keys are lowercased.** `<x:Card>` becomes `<x:card>` —
  see [macros.md](./macros.md).

## Bootstrap

A component is a state struct with `derive(ToJson, FromJson)` plus a
plain function returning a `@component.Component`; a module is a
`ModuleDef` value:

```moonbit
priv struct CounterState {
  count : Int
} derive(ToJson, FromJson)

fn counter_comp() -> @component.Component {
  @component.component(
    name="Counter",
    view=(
      #|<button @on.click="$inc" @text=".count"></button>
    ),
    init=CounterState::{ count: 0 },
    mutate={ "inc": (s : CounterState, _args) => { count: s.count + 1 } },
  )
}

pub fn counter_module() -> @component.ModuleDef {
  @component.ModuleDef::new(name="counter", components=[counter_comp()], examples=[
    { component: "Counter", title: "Basic Counter", args: {}, view: None },
  ])
}
```

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
    app.send_at_root("init")
  }
  ```

- **The embedded CLI** — a native `main` calling
  `@cli.plan_with_module(argv, Some(counter_module()))` (see
  [cli.md](./cli.md)).

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
`Obj::obj_field`. Reading *down* the tree is direct and needs no
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
[component-design.md](./component-design.md) and "When to bubble" in
[request-response.md](./request-response.md).

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
verbatim for `ctx.send`, `ctx.bubble`, and `ctx.request` /
response: because it's positional rather than a captured reference, an
async response survives intervening transactions that rebuild the root.
"The right slot" is exact for named fields and for map entries by key
(seq-access keys like `.sheets[.selId]` are *pinned* to their
request-time value by default); a bare list **index** still slides if the
list reordered. See [request-response.md](./request-response.md) for the
dispatch APIs and [semantics.md](./semantics.md) for the path/transaction
model and key pinning.

**Why the render buckets are separate.** The `when` / `enrich` /
`enrich_scope` / `loop_with` buckets are pure, evaluated on every
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
`update` / `mutate` / `compute` and the render buckets (`when` /
`enrich` / `enrich_scope` / `loop_with`) and is referenced by name; the
template itself only routes data and events.

The one exception is **boolean predicates** in conditional slots
(`@show`, `@hide`, `@if.<attr>`): a closed set of operators applied to
a value, written predicate-first like a handler call —
`empty?`, `truthy?`, `falsy?`, `null?`, `equals?`. E.g.
`@hide="empty? .items"`, `@show="truthy? .query"`. A conditional slot
otherwise accepts the same value forms as `@text` — a plain field
(`@show=".isOpen"`), a no-arg `compute` (`@show="$canSubmit"`), or a
loop/scope `@binding` (`@show="@isSelected"`, `@hide="@hasDesc"`) — read
as a boolean.

`equals?` takes two args and is the idiomatic way to show/hide by name,
e.g. `@show="equals? .view 'detail'"`. Predicate args (and handler
args) accept string literals: `'detail'`, or `'two words'` for a
literal with spaces (escape an interior quote as `\'`).

| Prefix   | Means                                     | Example               |
| -------- | ----------------------------------------- | --------------------- |
| `.x`     | field on the state (single-level — no `.foo.bar` paths) | `.count`, `.title` |
| `$x`     | a `mutate`/`compute` call (or generated mutator) | `$inc`, `$canSubmit` |
| `@x`     | local binding (loop / scope)              | `@key`, `@value`      |
| `^x`     | macro parameter                           | `^label`              |
| `*x`     | dynamic binding — see [advanced.md](./advanced.md) | `*theme`          |
| `Name`   | component type (PascalCase)               | `Item`, `JsonNull`    |
| `name`   | bare identifier — meaning depends on slot | `dec`, `value`        |
| `'str'`  | string literal                            | `'btn btn-success'`   |
| `$'…'`   | string template (`{expr}` interpolation)  | `$'Hi {.name}'`       |
| `.s[.k]` | sequence/map item access                  | `.byKey[.currentKey]` |
| `pred? .x` | boolean predicate in a conditional slot | `empty? .items`, `equals? .view 'detail'` |

`.x` and `$x` are not interchangeable: `.x` only reads a field, `$x`
only calls a `$`-handler. The linter flags a mismatch and tells you
which prefix to use.

A bare `name` (no prefix) in `@on.<event>="<handler> <arg> <arg>..."`
resolves by slot:

- **First slot** — an event name dispatched as `Input(name, args)` to
  the `update` fn; when no `update` arm claims it, dispatch falls back
  to a `mutate` entry or generated mutator of the same name. Use
  `$name` to call `mutate`/`compute` directly.
- **Subsequent slots** — built-in handler argument name (full list in
  *Event Handling*); anything else triggers a lint warning.

```html
<button @on.click="onAddItem value">+</button>
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
> (see the `dynamic.mbt` example's `onAddItem`).

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
(`@on.click="$setView 'edit'"`); inside a normal MoonBit string you must
escape the double quotes (`"<p :class=\"'flex gap-3'\">x</p>"`). Prefer
`#|` raw strings for multi-line views.

## Component Skeleton

`@component.component(...)` takes a state struct plus labeled arguments —
the **component spec**. The full shape (see `component/pkg.generated.mbti`
for the exact signature):

```moonbit
priv struct MyCompState {
  count : Int
  items : Array[String]
  isLoading : Bool
  selected : @tutuca.Value // "anything" fields are @tutuca.Value
} derive(ToJson, FromJson)

@component.component(
  name="MyComp",
  // default view (registered as "main"); #| raw string starting at the tag
  view=(
    #|<p @text=".count"></p>
  ),
  views={ // additional views, name -> template
    "edit": "<input :value=\".count\" @on.input=\"$setCount valueAsInt\" />",
    "big": "<h1 @text=\".count\"></h1>",
  },
  view_styles={ "big": "h1 { font-size: 4rem; }" }, // per-view scoped CSS
  style="p { color: blue; }",                  // scoped to main view
  common_style="p { font-family: sans-serif; }", // scoped to all views of this component
  global_style="body { margin: 0; }",          // injected globally, no scoping
  // the struct's fields ARE the component's fields; init gives the defaults
  init=MyCompState::{ count: 0, items: [], isLoading: false, selected: Null },
  // ONE effectful dispatch match: (s, msg, ctx) => S?  (None = no change)
  update=(s : MyCompState, msg, ctx) => match msg {
    Input("onClick", _) => Some({ ..s, count: s.count + 1 })
    Receive("init", _) => {
      ctx.request("loadData", [], @tutuca.RequestOpts::new())
      Some({ ..s, isLoading: true })
    }
    Bubble("itemPicked", [item, ..]) => Some({ ..s, selected: item })
    Response("loadData", [List(rows), _err]) =>
      Some({ ..s, items: rows.map(r => r.str()), isLoading: false })
    _ => None // ALWAYS needed
  },
  mutate={ // pure state change, $-callable: (s, args) => S
    "inc": (s : MyCompState, _args) => { ..s, count: s.count + 1 },
  },
  compute={ // pure value read, $-callable: (s, args) => Value
    "label": (s : MyCompState, _args) => Str("n=\{s.count}"),
  },
  when={ // @when filters: (s, key, value, iterData) => Bool
    "filterItem": (s : MyCompState, _key, value, _iter) => value.str() != "",
  },
  // enrich= / enrich_scope= / loop_with= — see iteration.md
  specs={ // Value-level slots & kind overrides — NOT in the struct
    "child": @component.FieldSpec::comp("Item"), // component-typed field
  },
  // provide={ ... }, lookup={ ... }   // see advanced.md
)
```

`comp.make({...})` builds an instance from a `Map[String, Value]` of
args and returns it as a `@tutuca.Value` (the `Obj`) — ready to store in
lists, maps, or example args. Missing fields get their defaults from
`init`, and every arg is coerced through its inferred spec (a
wrong-shaped value falls back to the default — silently).
Component-typed fields declared with
`specs={ "child": FieldSpec::comp("Item", args={...}) }` build their
default instance through the registration scope at `make()` time, so
forward references work by name.

> **No statics.** The JS `statics:` block has no MoonBit counterpart —
> nothing in the framework calls statics in either language. Write a
> plain MoonBit `fn` next to the component (e.g. a
> `fn tree_from_data(...) -> @tutuca.Value` factory that calls
> `comp.make(...)`) and call it directly. Likewise, "one component
> object per scope" is natural here: a component definition is a
> `fn my_comp() -> Component`, and each call produces a fresh
> `Component` value (new id, separately compiled CSS) to register into
> a scope.

## Field Types & Auto-generated API

**The state struct is the fields**: names, defaults (from `init`) and
kinds all come from the struct, and every handler body is
compiler-checked against it — `s.cuont` is a compile error, not a
silently-Null render. Set/omap kinds and component slots use explicit
`specs=` entries.

| Declared as                              | Field kind | Extra auto-generated mutators (for field `x`)                                            |
| ---------------------------------------- | ---------- | ---------------------------------------------------------------------------------------- |
| `x : String`                             | text       | —                                                                                        |
| `x : Int` / `x : Double`                 | int / float | —                                                                                       |
| `x : Bool`                               | bool       | `toggleX`                                                                                |
| `x : @tutuca.Value`                      | any        | — (`Null`, instances, `Fn`s, heterogeneous data)                                         |
| `x : Array[...]`                         | list       | `pushInX`, `insertInXAt`, `setInXAt`, `updateInXAt`, `deleteInXAt`/`removeInXAt`         |
| `x : Map[String, ...]`                   | map        | `setInXAt`, `updateInXAt`, `deleteInXAt`/`removeInXAt`                                   |
| `specs={ "x": FieldSpec::omap(default?={...}) }` | omap | same as map (MoonBit `Map` already preserves insertion order) |
| `specs={ "x": FieldSpec::set(members?=[...]) }` | set  | `addInX`, `deleteInX`/`removeInX`, `hasInX`, `toggleInX` (Map-backed: member → `Bool(true)`) |
| `specs={ "x": FieldSpec::comp("Item", args?={...}) }` | comp | — slot field, **not** in the struct (default instance made through the scope at `make` time) |

A `set`/`omap` specs entry works two ways: standing alone it declares a
Value-level slot field (default from the spec), or it **overrides the
kind** of a matching `Map[...]` struct field (e.g. `sel : Map[String,
Bool]` + `specs={ "sel": FieldSpec::set() }` keeps the typed default and
gains the set mutators). `comp` entries are always slots.

**Every** field additionally gets `setX`, `updateX` (takes a `Fn` value —
code-side use), `resetX`, and `xLen` (`Null` for non-sized values). The
generated names keep their **JS camelCase spelling** — that is what makes
views port verbatim: `@on.click="$removeInItemsAt @key"`,
`@on.input="$setQuery value"`, `@on.click="$toggleView"` all call
generated mutators. User-supplied `mutate` entries win over generated
ones of the same name.

A field that can hold "anything" is declared `@tutuca.Value` — the
dynamic escape hatch inside an otherwise typed struct. That includes
fields holding component instances or `Fn` values: they survive state
updates losslessly.

Emptiness / truthiness / null checks are not generated — use
the boolean predicates `empty?`, `truthy?`, `falsy?`, `null?`, `equals?`
in a conditional slot instead (e.g. `@hide="empty? .x"`,
`@show="equals? .view 'detail'"`).

## Computed values & predicates (`compute`)

A no-arg `compute` entry called via `$name` is invoked and its return
value is used. Works anywhere a value is read — `@text`, `:attr`,
`@show` / `@hide`, `@if.<attr>`, and `{…}` interpolation. (`.name` is a
field read and never invokes; `$name` is the call.)

```moonbit
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
<button @show="$canSubmit" :class="$buttonClass">Save</button>
<p :title="$'Hello, {$fullName}'" @text="$fullName"></p>
```

The boolean predicates (`empty?`, `truthy?`, `falsy?`, `null?`,
`equals?`) cover single-field checks in conditional slots; reach for a
`compute` when the condition spans multiple fields or needs derivation.
The handler bodies are typed — no pattern-matching `Value` shapes for
plain struct fields.

Tutuca expressions resolve a **single** name on the state — there is
no path syntax. `@text=".user.name"` does not navigate; it fails. When
the value lives behind a field, your options are:

- **Render the child as a component** — `<x render=".user">` then
  `@text=".name"` inside the child's view. Best when the nested thing is
  already (or could be) a component.
- **Add a `compute`** — reading through the value coercers when the
  field is a `@tutuca.Value`:

  ```moonbit
  "userName": (s : PageState, _args) => s.user.field("name"),
  ```

  then `@text="$userName"`. Best for one-off derivations or formatting.
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
<x text="$getStrUpper"></x>         <!-- $ calls a compute -->
<x text="@value"></x>               <!-- loop binding -->
```

Use `@text` when you already have a host element to put the text in; use
`<x text=…>` for bare text with no wrapping element (e.g. text interleaved with
other inline content, or a loop binding). Both take the same value forms
(`.field`, `$handler`, `@binding`). A `Null` text value renders nothing
(not the string `"null"`).

## Attribute Binding

```html
<input :value=".str" @on.input="$setStr value" />
<a :href=".url" :title="$'Hi {.name}'">link</a>       <!-- string template -->
<button :class="$'btn {.color}'">x</button>
```

Plain attrs are static. `:attr="..."` is a dynamic expression. Boolean
HTML attributes (`disabled`, `checked`, `hidden`, …) are auto-recognized;
pass a boolean field. `style` is a plain string attribute like any other
— there is no style-object form.

A static `class="…"` and a dynamic `:class`/`@if.class` **cannot coexist on the
same element** — setting one attribute two ways is a lint error
(`DUPLICATE_ATTR_DEFINITION`), and at runtime the dynamic value wins and the
static class is dropped. Fold any structural classes into the bound expression,
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
is the slowest kind to debug. **Run `tutuca lint` first**: it catches
several of these. The usual suspects:

- **Unparseable attribute value** → the attribute is silently dropped. A bare
  multi-word value isn't a string — quote it (`:label="'two words'"`) or make it
  a template (`:label="$'{.a} {.b}'"`). Lint flags this as `BAD_VALUE`.
- **camelCase attribute on a custom element** → setter no-op (see the lowercasing
  note above). Use kebab-case attributes. Not lintable — the HTML parser
  lowercases the name before either tutuca or the linter sees it.
- **Forgotten margaui decoy view** → classes assembled in `compute` entries or
  interpolations render unstyled. See [margaui.md](./margaui.md). Not lintable.
- **A whitespace-only view** → blank render. A *leading* newline before the
  root element is fine (the parser trims it); a template with no element at all
  is not.

## Event Handling

```html
<!-- $-handler (`$`) vs update dispatch (no prefix) -->
<button @on.click="$inc">+</button>
<button @on.click="dec">-</button>

<!-- pass args by name -->
<input @on.input="$setStr value" />
<input @on.input="$setN valueAsInt" />
<button @on.click="$pick @key isAlt">pick</button>
<button @on.click="loadAnotherWay">load</button>
```

Written args arrive in the handler's `args` array in template order —
pattern-match them directly (`Input("search", [Str(q), ..]) => ...`).
For an `update` arm the `&Ctx` is the explicit third parameter of the
update fn; a `$`-handler gets no ctx (`mutate`/`compute` are pure). So
`$pick @key isAlt` calls the `$`-handler with `args = [key, isAlt]`, and
`loadAnotherWay` dispatches `Input("loadAnotherWay", [])` plus ctx.

Built-in handler argument names: `value`, `valueAsInt`, `valueAsFloat`,
`target`, `event`, `isAlt`, `isShift`, `isCtrl`/`isCmd`, `key`, `keyCode`,
`isUpKey`, `isDownKey`, `isSend`, `isCancel`, `isTabKey`, `ctx`,
`dragInfo`.

The content of `value` depends on the event source:

| Source                      | What `value` resolves to                         |
|-----------------------------|--------------------------------------------------|
| `<input type="checkbox">`   | the checked state (`Bool`)                       |
| `<input type="file">`       | the picked file's metadata as a `Map` (name/size/type/lastModified), `Null` if none |
| `CustomEvent`               | the event's `detail`, mapped to a `Value` (`Map` for objects) |
| anything else               | the input's value (`Str`), or `Null` if absent   |

For numeric inputs, prefer `valueAsInt` / `valueAsFloat` to skip the
string parse.

Ask for the most granular arg the handler actually uses — `value` /
`valueAsInt` / `key`, not the raw `event` — when the specific value is
all you need. An arm that pattern-matches `[Str(q), ..]` off a plain
`value` is trivial to call from a test; one that takes `event` needs an
event-shaped `Map`. (The value layer deliberately exposes no DOM
objects — file inputs and custom events already arrive as plain `Map`
metadata, see the table above.) See [testing.md](./testing.md)
*Designing handlers so tests stay simple*.

### Event Modifiers

`@on.<event>+<mod>+<mod>=...`

- All events: `+ctrl`, `+cmd`/`+meta`, `+alt`
- `keydown` only: `+send` (Enter), `+cancel` (Escape)

```html
<input @on.keydown+send="$submit value" @on.keydown+cancel="$reset" />
<button @on.click+ctrl="$soloOnly">ctrl-click</button>
```

### Web Components & Custom Events

Custom elements just work, and any `CustomEvent` they fire is reachable
via `@on.<event-name>`. The event's `detail` surfaces as `value` — the
glue maps it to a `Value::Map`:

```moonbit
// the host page loads <emoji-picker> (emoji-picker-element) from a CDN;
// the component just hosts the tag and handles its event.
// `current : @tutuca.Value` in the state struct
update=(s : PickerState, msg, _ctx) => match msg {
  Input("onEmojiClick", [Map(detail), ..]) =>
    Some({ ..s, current: detail.get("unicode").unwrap_or(Null) })
  _ => None
},
```

```html
<section @on.emoji-click="onEmojiClick value">
  <emoji-picker @show=".isPickerVisible"></emoji-picker>
</section>
```

(Worked example: `examples/web_component.mbt`.)

Handle these events declaratively with `@on.<event-name>` in the view —
don't grab the node from host/glue code and `addEventListener` on it. A
listener attached from outside the component runs outside the handler
model: no new-state return, no transactor batching, and the mutation
is invisible to the component that owns the state. For any event with a
real element in the tree, `@on.` is the only entry point you need.
Genuinely external inbound sources (WebSocket, `postMessage`, timers)
have no element to bind — route those through `app.send_at_root` instead
(see [request-response.md](./request-response.md)).

Pitfall: binding a camelCase JS property on a custom element silently
fails — see the lowercasing rules in *Attribute Binding* above.

## Conditional Display

```html
<div @show=".isLoading">Loading...</div>
<div @hide=".isLoading">content</div>

<!-- boolean predicates; equals? compares against a string literal -->
<div @show="equals? .view 'detail'">detail view</div>

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

Note: `@show` / `@hide` **omit the node from the output** when the
condition says hide — they do not merely toggle CSS visibility.

## List Iteration & Scope Enrichment

```html
<li @each=".items"><span @text="@key"></span>: <x text="@value"></x></li>
<x render-each=".items"></x>
```

Auto-bound names inside a loop are `@key` and `@value`. Iteration
(`@each` / `render-each`), filtering (`@when` → the `when` bucket),
item and scope enrichment (`@enrich-with` → `enrich` / `enrich_scope`),
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

The top-level `view=` is registered under `"main"` (the default); extras
go under `views={ "name": "..." }`. `as` selects which view of the
rendered component to use, falling back to `main` if absent. It accepts the
same dynamic values as `@push-view` (a literal name like `edit`, or `.field`,
`*dyn`, `@bind`, `$handler`, `$'…{x}…'`), evaluated against the **host**
component at render time. `as` only applies to the **direct** component — for
whole-subtree control, use `@push-view` (next section). For `render-each` the
selector is evaluated once against the host, so every item gets the same view.

## Multiple Views & View Stack

```moonbit
priv struct NoteState {
  title : String
} derive(ToJson, FromJson)

@component.component(
  name="Note",
  view="<p @text=\".title\"></p>", // "main"
  views={
    "edit": "<input :value=\".title\" @on.input=\"$setTitle value\" />",
  },
  init=NoteState::{ title: "" },
)
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

`style` is scoped to the main view, `common_style` to all views of the
component, `global_style` is injected unscoped, and `view_styles` maps a
view name to its per-view scoped CSS (see the *Component Skeleton*
above). Scoping mechanics, styling the root element with bare
declarations, and the at-rules that must live in `global_style`: see
[styles.md](./styles.md). Tailwind / MargaUI utility classes:
[margaui.md](./margaui.md).

## Triggers and Handlers

Tutuca has four orchestration channels. Each maps a trigger to one arm
of the **same `update` match**:

| Triggered by                                | `update` arm            | Use for                                             |
| ------------------------------------------- | ----------------------- | --------------------------------------------------- |
| DOM event (`click`, `input`, …)             | `Input(name, args)`     | the component handling its own events               |
| `ctx.bubble(name, args)` — event up the tree | `Bubble(name, args)`   | aggregate state an ancestor owns (logs, selections) |
| `ctx.send(name, args)` — message to a target path | `Receive(name, args)` | addressing one known component (or self)        |
| `ctx.request(name, args, opts)` — async request | `Response(name, args)` | fetch / timer / storage, result routed back      |

The `update` fn — `(s, msg : Dispatch, ctx : &@tutuca.Ctx) => S?` — is
one pattern match over all four; the framework swaps the returned state
into the dispatch path (`None` = no change). `Input` dispatch that no
`update` arm claims falls back to a `mutate` entry or generated mutator
of the same name. The three channels beyond `Input` — plus `ctx.at()`,
catch-all arms, per-call handler-name overrides, error handling, and
`RequestFn` registration — are in
[request-response.md](./request-response.md); worked snippets in
[patterns/coordinate-components.md](./patterns/coordinate-components.md).

The render buckets (`when` / `enrich` / `enrich_scope` / `loop_with`)
aren't event-triggered — the renderer invokes them to filter iterations
and produce binds, not state changes (see *Mental model*, and *Scope
Enrichment* in [iteration.md](./iteration.md)).

## Macros

Pure template expansion — `@anode.Macro` values (`{ defaults, raw_view }`)
called as `<x:name>`, with `^param` references, slots, and named slots:
see [macros.md](./macros.md). Registry keys are lowercased —
`<x:Card>` resolves as `<x:card>`.

## Raw HTML (escape hatch)

```html
<div @dangerouslysetinnerhtml=".trustedHtml"></div>
```

Bypasses all escaping; children of the element are ignored when active.

## State values: the `Value` enum

Underneath the typed structs, all state is the `@tutuca.Value` enum —
there is no immutable.js layer in this port:

```moonbit
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

- The state struct is encoded to / decoded from this layer (that is what
  `derive(ToJson, FromJson)` wires up); `Obj`/`Fn` values held in
  `@tutuca.Value` struct fields survive the round-trip losslessly.
- `Value` derives `Eq` (deep structural equality) and `Debug`, so
  `assert_eq` and `debug_inspect` work on values directly.
- `v.is_truthy()` gives JS-style truthiness; `v.to_display_string()`
  the display form. The coercers `v.int()`, `v.num()`, `v.str()`,
  `v.bool()`, `v.list()`, `v.entries()`, and `v.field("name")` (works on
  `Map` **and** `Obj`) read `Value`s in handler args and
  `@tutuca.Value` fields.
- **Immutability is by discipline**: `Array` / `Map` payloads are
  ordinary mutable containers — handlers must **copy before changing**
  (`s.items.copy()` then `push`) and return a **new** struct
  (`Some({ ..s, items: next })`), never mutate in place.
- Sets are modeled as a `Map` keyed by member (value `Bool(true)`) via
  `specs=` + `FieldSpec::set`; ordered maps are plain `Map`s via
  `FieldSpec::omap`.
- Custom collections implement the `@tutuca.Obj` trait (notably
  `obj_seq_entries` for `@each`) — see [iteration.md](./iteration.md)
  *Custom collections* and `examples/custom_collection.mbt`.

## The ModuleDef convention

The JS `getComponents()` / `getMacros()` / `getRequestHandlers()` /
`getExamples()` ES-module contract becomes one **value**: a
`@component.ModuleDef`. A native binary cannot load user code, so
modules are built programmatically and handed to tooling:

```moonbit
pub fn my_module() -> @component.ModuleDef {
  @component.ModuleDef::new(
    name="my-module",
    components=[root_comp(), item_comp()], // EVERY component, helpers included
    macros={ "badge": badge_macro() },     // optional
    requests={ "loadData": load_data_fn }, // optional, RequestFn values
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
browser hosts (`App::from_module`), and the embedded CLI
(`@cli.plan_with_module`) — a passing test and a working page are the
same artifact.

**Per-example request mocking**: parameterize the module function with
an optional `requests?` argument, defaulting to the real handlers, and
build the module with a fixture map in tests/demos (the pattern in
`examples/request.mbt`):

```moonbit
pub fn request_module(
  requests? : Map[String, @component.RequestFn] = real_request_handlers(),
) -> @component.ModuleDef {
  ...
}
```

Best practice: have `components` list **every** component the module
defines — child and helper components included — and give each one at
least one `ExampleDef`. A component left out of `components` is invisible
to `tutuca lint`/`render`/`show`, so it silently loses linting and render
coverage.

## See also

- [iteration.md](./iteration.md) — `@each` / `render-each`, `@when`,
  `@enrich-with`, `@loop-with` pagination, and the loop lifecycle.
- [macros.md](./macros.md) — `Macro` definitions, `<x:name>` calls,
  slots, and registration.
- [styles.md](./styles.md) — `style` / `common_style` / `global_style`
  scoping mechanics and pitfalls.
- [component-design.md](./component-design.md) — design judgment for shaping a
  feature into components: responsibilities, where state lives, which channel to
  reach for, and a curated do's & don'ts list.
- [request-response.md](./request-response.md) — the `Bubble` /
  `Receive` / `Response` channels, `ctx.at()`, catch-all arms, and
  `RequestFn` registration.
- [advanced.md](./advanced.md) — dynamic bindings (`*x`), pseudo-`@x` for
  `<select>` / `<table>` / `<tr>`, drag & drop, custom collections.
- [margaui.md](./margaui.md) — setting up MargaUI styling:
  `collect_classes()`, the CDN compile step, and `inject_style`.
- [semantics.md](./semantics.md) — runtime semantics: path steps, the
  transaction lifecycle, dyn-var teleporting, and async key pinning
  (`live_path`).
- [testing.md](./testing.md) — `moon test` blocks and the `@harness`
  mount/drive/read API.
- [cli.md](./cli.md) — the embedded CLI: commands, flags, exit codes, and
  the linter rules.
- [patterns/README.md](./patterns/README.md) — task-oriented recipes ("how do I
  iterate / filter / paginate / show-hide / build tabs / share state / …"),
  each linking back here and to a runnable example.
