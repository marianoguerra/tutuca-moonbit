# marianoguerra/tutuca

A [MoonBit](https://docs.moonbitlang.com) port of
[tutuca](https://github.com/marianoguerra/tutuca), a small UI framework built
around a reactive value language, HTML-ish templates, and a virtual DOM.

It runs on all three MoonBit backends: **wasm-gc** (the default, for
target-agnostic logic and the browser demos), **js** (the real-DOM adapter, via
[mizchi/js](https://github.com/mizchi/js.mbt)), and **native** (the CLI).

Live demos, playground and storybook:
<https://marianoguerra.github.io/tutuca-moonbit/> — source:
<https://github.com/marianoguerra/tutuca-moonbit>. The published mooncakes
package carries the library packages, the universal core (`dyncomp/`) and the
CLI; the storybook, the demo and playground hosts and the sample guests live in
the repo only (see `exclude` in `moon.mod`).

## What's in it

tutuca is a stack of small packages, each a MoonBit package with its own tests
and formal `spec.mbt`. From the bottom up:

| Layer | Package(s) | What it does |
|---|---|---|
| **Value language** | `core/` — `marianoguerra/tutuca/core` (`value_*.mbt`, `path_*.mbt`) | The tutuca value syntax — parse/tokenize/eval — plus the reactive path/dispatch system (COW spine rebuild, handler dispatch, change sets). |
| **Templates** | `anode/` | Parses the HTML-ish view syntax into an AST: attributes, directives, `x-` ops, macros, whitespace handling, optimization. |
| **Virtual DOM** | `vdom/` (+ `vdom/memdom`, `vdom/browser`, `vdom/wasm`) | Builds and incrementally morphs a VDOM against any DOM implementing the `DomNode` trait. |
| **Render** | `render/` | Turns a parsed view + a value stack into a `@vdom.Vdom` tree (loops, scopes, event-path metas, teleport). |
| **Components / App** | `component/`, `app/` (+ `app/browser`, `app/wasm`), `transactor/` | Typed-state component definitions (a plain struct + one `Dispatch` update match), the app runtime, and the transactor that routes events at the root and settles state. |
| **Tooling** | `lint/`, `inspector/`, `statedef/`, `viewgen/`, `cli/` | The linter (parse-issue rules + a WHATWG-tokenizer structural HTML linter), a schema inspector, the state schema language, the ahead-of-time view compiler, and the native `tutuca` CLI. |
| **Testing** | `testing/harness` | A reusable harness to mount and drive a `ModuleDef` on the in-memory DOM. |
| **Universal core** | `dyncomp/` — `wit/` (the `tutuca:component` contract), `host/` (+ `host/wasm`), `policy/`, `registry/`, `jsonschema/`, `persist/` (+ `persist/wasm`) | Loading a WebAssembly component from anywhere into a *running* app: the contract it implements, the host that wraps it as an ordinary `&Obj`, what a bundle from a stranger is allowed to do, the searchable catalog of everything loaded, and the schema ⇄ JSON Schema projection both a form and an agent's tool read. See [`dyncomp/DESIGN.md`](dyncomp/DESIGN.md). |
| **Universal UI** | `dyncomp/ui/` (+ `dyncomp/ui/std`, `dyncomp/ui/wasm`) | The page a person arranges out of that catalog. The component tree IS the layout — `Universal`, `Stack`, `Grid`, `Tabs` are ordinary tutuca components, and a loaded guest is decorated exactly like a standard one. The editor is backend-agnostic, so `moon test` drives the whole thing on the in-memory DOM; `ui/wasm` is the half that cannot be — the bundle bridge, the session store, and `mount()`. See [`docs/dynamic-components.md`](docs/dynamic-components.md). |
| **Demos & docs** | `demo/`, `playground/`, `storybook/`, `guests/` | 51 ported examples (`storybook/examples/`), browser/CLI/wasm demo hosts, an in-browser playground, a compiled storybook gallery, and six sample `tutuca:component` guests (five MoonBit, one Rust). |

The `tutuca` CLI does the work that happens outside the compiler:
`gen-views`, `watch`, `storybook`, `install-skill`, `feedback`,
`agent-context` and `help`. It does not inspect, document, lint or render
components — this is an ahead-of-time port, so those questions belong to
`gen-views` (which makes a bad field reference or an unhandled `@on` handler a
*build* error), to `moon check`, and to `moon test` over
`testing/harness`. There is no module path and no way to point the binary at
one.

## Views (`views~` + `gen-views`)

`component(...)` takes its views as `views~ : Map[String,
@anode.View]` — a view is a built `@anode.View`, never a raw string. There is
one component shape, and two ways to arrive at it.

**Ahead of time**, with `tutuca gen-views`: the view file states the component,
and the generated module hands `component()` its name, views, styles, schema
and codec. This is the default and what the rest of this section describes.

**Late-bound**, with `@anode.View::new("main", raw_view="…")`, for a view whose
SOURCE only exists at run time: a dyncomp guest bundle arriving over the wire,
a macro body a MoonBit function builds per call, markup assembled from a value
the program computes. Being late is not being under-described — such a
component still declares its schema and its codec, because `component()`
requires both of every caller. There is no shape that specifies less and makes
the runtime infer the difference.

That requirement is also why `View::new` is the only function in `anode` that
names the parser: a program built entirely ahead of time never calls it, so it
does not link an HTML parser it cannot reach. Worth 44% of the counter demo's
wasm bundle — see `benchmarks/OPTIMIZATIONS.md`.

A component keeps its views in an `.html` file and compiles them ahead of time
into a companion MoonBit module, so the view's vocabulary stops being strings
the compiler cannot see:

```sh
moon run --target native cmd/main -- gen-views demo/counterlib/counter.html --name Counter
# -> demo/counterlib/counter_view_gen.mbt      (the view vocabulary as types)
# -> demo/counterlib/counter_view_ir_gen.mbt   (the compiled views + the wrapper)
# both checked in; regenerate, never edit

```

The file is either one bare view, or several `<template>` elements whose `id`
attributes name them — the one with no `id` is `main`. A `<style>` inside a
template is that view's style; one at file level is the component's common
style, or its global style with `data-global`.

For a component named `Counter` the generated module declares
`counter_views()` (the built views, for `views~`) and — with a schema —
`counter_component()`, the wrapper that passes them,
`CounterInput` and `CounterMsg` (`@on` handler names, with payload types
inferred from the argument shapes at the call sites, plus
`CounterMsg::from_dispatch`), `CounterMethod` with `counter_compute` /
`counter_swap` (the `$`-callables, as exhaustive matches).
The package it lands in must import
`"marianoguerra/tutuca/core" @tutuca`, `"marianoguerra/tutuca/component"` and
`"moonbitlang/core/debug"`.

A view file may also declare its component's data contract, in a small language
that spells its types the way MoonBit does, next to the templates that read it:

```html
<script type="tutuca/state">
  state Counter { label: String, count: Int, history: Array[Int] }
  receive Counter { ResetTo(Int) }
</script>
```

Then `CounterState` itself is generated — a plain struct with no derives, a
`zero()`, a direct state↔Value codec, and one `SchemaInfo` carrying the whole
contract as static metadata: every field with the kind the schema DECLARES
rather than one guessed from the seed value, plus the handler names, the view
names, the element ids and the fixture names. That descriptor is what an
instance answers `obj_schema()` with, so the inspector and the state editor
build themselves from it with no component registry in hand. And every
`.field` a view reads is checked against it, inside an `@each` body as well as
at the root. A misspelt field is a
generation failure naming the near miss, where before it rendered as null.
The `receive` / `bubble` / `response` buckets get typed enums too: those
names are raised from MoonBit rather than written in a view, so the schema is
the only place they can be declared.

The payoff is in `update` (see `demo/counterlib/` for the worked example):

```mbt nocheck
update=(s : CounterState, msg, _ctx) => match CounterMsg::from_dispatch(msg) {
  Some(Add(d)) => ...          // `d` is a Double: `@on.click="add 1"`
  Some(SetLabel(l)) => ...     // `l` is a String: `@on.input="setLabel value"`
  Some(ResetCount) => None
  Some(Unknown(_, _)) | None => None
}
```

Adding `@on.click="del 1"` to `counter.html` and regenerating makes that match
non-exhaustive — a compile error naming `Some(Del(_))`, where the old
string-matched `_ => None` arm silently did nothing.

### Several components, and macros

A view file belongs to a MoonBit module, not to a single component — template
ids say what each one is:

| id | |
|---|---|
| *(none)* | the single unnamed component's `main` view |
| `row` | …its `row` view |
| `Counter:main` | the `Counter` component's `main` view |
| `Counter` | shorthand for `Counter:main` |
| `macro:icon` | a macro shared by every component in the file |

A component name is Uppercase-initial, which is what tells `Counter` (a
component) from `row` (a view). A file either names its components or does
not; mixing the two is an error.

A macro's `data-*` attributes are the defaults for the `^var` references in
its body, and the generator expands every call ahead of time — which is why
macros belong in the view file rather than being registered from MoonBit:

```html
<template id="macro:icon" data-size="'24'" data-color="'currentColor'">
  <svg :width="^size" :height="^size" :stroke="^color"><path :d="^path"></path></svg>
</template>
<template id="Gallery">
  <x:icon :size=".size" :path=".heart"></x:icon>
</template>
```

### The compiled tree

`gen-views` also emits `<stem>_view_ir_gen.mbt`: the `@anode.ANode` tree and
event table each view parses into, as MoonBit code, so the template parser
never runs at startup. A component that declares a schema gets one more thing
there — `counter_component`, a wrapper over `component()` with everything the
view file already states filled in:

```moonbit nocheck
counter_component(
  init=CounterState::fresh(),
  update=(s, msg, _ctx) => ...,
)
```

Its name, its views, its styles, its direct codec and its schema are not
arguments — the view file states them, and restating them is how a fact the
generator learns fails to reach the component that needs it. Each is still a
parameter, so `views=counter_views_with_extra()` or `name="Root"` overrides
one when a component genuinely differs; only the handlers have nowhere else to
come from. Being typed on `CounterState` rather than on a type variable, the
wrapper is also what lets `update` be written `(s, msg, _ctx)` with no
annotation.

A component whose views are built in MoonBit has no `views~` to default and so
gets no wrapper; it calls `@component.component(...)` directly, passing the
`encode`, `decode` and `schema` its view file's state block still generates.

There is no serialization format and no decoder: the AST is `pub(all)`, and the
tree is written with anode's builders — plain constructors with the rarely-set
fields defaulted, which a hand-written view or test can use just as well:

```moonbit nocheck
@anode.View::from_ir(
  "main",
  @anode.h("div", [@anode.attr("class", "stat")], [
    @anode.h("button", [@anode.attr("class", "btn"), @anode.eid(0)], [
      @anode.text("+"),
    ]),
    @anode.dyn_text(Field("count")),
  ]),
  [[@anode.on("click", Method("inc"))]],
)
```

`@anode.h` decides ConstAttrs vs DynAttrs with the rule the parser applies
(`attrs_of_items`), so the two paths cannot disagree. What the file does NOT
carry is anything the load can recover: `View::from_ir` rebuilds the node table
from the tree itself (every registered node carries its `node_id`), gives each
handler list the id that is its position, stamps `data-vid` and runs the
constant-subtree optimization — `RenderOnce` ids are process-global renderer
memo keys, so they must be minted at load time, not baked in.

A macro declared in the view file (`<template id="macro:badge" data-label="'New'">`)
is expanded when the views are generated, so a view that calls one compiles to
a tree like any other. A macro REGISTERED from MoonBit cannot be — its body is
a runtime value — so a file using those keeps the source path; `--no-ir` opts
out by hand.

Regenerate through the task, not the CLI — `moon fmt` owns the layout of the
generated pair:

```sh
moon run --target native cmd/dev -- gen-views    # generate + fmt
git diff --exit-code                             # drift check
```

While authoring, `tutuca watch` removes the regenerate step entirely:

```sh
tutuca watch demo/counterlib      # or a file, or bare for the whole project
```

It generates every managed view once, then again on each save, so the types
are always current and the MoonBit compiler is what tells you a view and a
component have drifted apart. A directory contributes the `.html` files that
already have a generated sibling — that is what distinguishes a view file
from a page like `index.html`. A view that fails to generate prints and the
watch keeps going; the next save is expected to fix it.

### In the playground

The [playground](https://marianoguerra.github.io/tutuca-moonbit/playground/)
runs the same generator in the browser. Its left pane has three tabs:

| Tab | |
|---|---|
| **Component** | the MoonBit you write |
| **View** | the `.html` its views live in (name the component with `<!-- name: Counter -->`) |
| **Generated** | read-only: what `gen-views` makes of the View tab, updating as you type |

The generated modules are compiled as extra files of *your* package, so the
Component tab names `counter_views()` / `CounterMsg` / `CounterInput`
with no import — and adding an `@on` handler in the View tab fails the build
with `Partial match … Some(Del(_))` until the Component tab handles it. Load
the "Counter (view tab)" example to see it.

The generator reaches the browser as `viewgen/` compiled to js
(`playground/viewgen_js`), which publishes `globalThis.__tutucaViewgen`;
`playground/build/check-viewgen-tab.mjs` drives that whole path headlessly
(generate → compile → link) as part of the `playground` task.

## vdom

The virtual DOM (`src/vdom.js` in the original): `Vdom` trees built with
`h`/`text`/`comment`/`fragment`, rendered and incrementally morphed against any
DOM that implements the `DomNode` trait.

- `vdom/` — core types and algorithms (`h`, `to_dom`, `diff_props`,
  `morph_node`, `morph_children`, `render`, `unmount`), backend-agnostic.
- `vdom/memdom/` — in-memory DOM. Runs on every backend; the primary test
  substrate (unit suites ported from the JS tests plus quickcheck
  properties: morph ≡ fresh render, keyed-reorder identity preservation,
  diff_props roundtrip).
- `vdom/browser/` — js-backend adapter over the real DOM via
  [mizchi/js](https://github.com/mizchi/js.mbt) (`supported_targets = "js"`).

```mbt check
///|
test "render a tree into memdom" {
  let doc = @memdom.document()
  let container = @vdom.DomNode::create_element(doc, "DIV", None, None)
  let opts = @vdom.RenderOpts::new(doc)
  let prev = @vdom.render(
    @vdom.h("ul", attrs={ "className": Str("list") }, childs=[
      @vdom.h("li", key="a", childs=[@vdom.text("one")]),
      @vdom.h("li", key="b", childs=[@vdom.text("two")]),
    ]),
    container,
    opts,
  )
  // incremental re-render: morphs in place, preserves keyed nodes
  let _ = @vdom.render(
    @vdom.h("ul", attrs={ "className": Str("list") }, childs=[
      @vdom.h("li", key="b", childs=[@vdom.text("two")]),
      @vdom.h("li", key="a", childs=[@vdom.text("one!")]),
    ]),
    container,
    opts,
    prev~,
  )
  inspect(
    container.to_html(),
    content=(
      #|<div><ul class="list"><li>two</li><li>one!</li></ul></div>
    ),
  )
}
```

In a browser (js backend):

```mbt nocheck
///|
let opts = @browser.window_opts()

///|
let container = @browser.BrowserNode::from_element(
  @dom.window().document().getElementById("app").unwrap(),
)

///|
let prev = @vdom.render(view(state), container, opts)
```

### Differences from the JS vdom

- Attribute values are a closed enum (`Str`/`Num`/`Bool`/`Html`);
  `dangerouslySetInnerHTML: { __html }` is spelled `Html("...")`.
- Namespaces are an enum (`Svg`/`MathMl`/`Other(uri)`, `None` = HTML), only
  converted to URI strings at the DOM boundary.
- `h()` takes `childs : Array[Vdom]` — the JS iterable-flattening and
  primitive→text coercion don't apply; `text()` is explicit. Fragment
  children are still spliced.
- `key`/`namespace` are labeled arguments (`key="a"`, `ns=Svg`), though
  `"key"`/`"namespace"` entries in the attrs map are also honored.
- Object/array-valued custom-element properties are spelled
  `Data(json)` (the JS `h(tag, { items: [1, 2, 3] })` case); they always
  take the property path and diff by VALUE, so an equal-content new object
  does not re-invoke the element's setter (JS compares by reference).
- Out of scope: event handlers (tutuca delegates events at the root; vdom
  never routed them).
- `Double::to_string` matches JS `String(n)` for attribute-realistic values;
  extremes like `1e21` format differently.

## Building, testing, running

Common workflows live in a MoonBit task runner (`cmd/dev`) rather than loose
commands:

```sh
moon run --target native cmd/dev -- setup   # npm install (happy-dom) + enable git hooks
moon run --target native cmd/dev -- check    # moon check across wasm-gc, js, native
moon run --target native cmd/dev -- test     # moon test across the three targets
moon run --target native cmd/dev -- build    # moon build wasm-gc + native CLI + js
moon run --target native cmd/dev -- dist     # assemble a self-contained dist/
```

Run `cmd/dev` with no task to print the full list. The raw `moon` commands the
tasks run underneath still work directly. See [AGENTS.md](AGENTS.md) for the
tooling and testing details, and
[storybook/examples/README.md](storybook/examples/README.md) for how a JS
example becomes a MoonBit one.

`dist` produces `dist/index.html` (a landing page), the js and wasm-gc demos,
the storybook gallery, and the native `tutuca` binary — serve it with any
static file server (`cd dist && python3 -m http.server`) or
`dist/cli/tutuca storybook`. The wasm pages need a browser with the JS String
Builtins proposal (e.g. Chrome).

## Targets

`preferred_target` is `wasm-gc`, so a bare `moon check` / `moon test` covers
only the target-agnostic packages. Full coverage needs all three:
`moon test` (wasm-gc), `moon test --target js` (the browser adapters, happy-dom
based) and `moon test --target native` (the CLI shells). The `check` / `test`
dev tasks run all three for you.

## License

MIT — see [LICENSE](LICENSE). This is a port of the MIT-licensed
[tutuca](https://github.com/marianoguerra/tutuca) by the same author.
