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
package carries the library, CLI and storybook packages; the demo, playground
and wasm-component guest hosts live in the repo only (see `exclude` in
`moon.mod`).

## What's in it

tutuca is a stack of small packages, each a MoonBit package with its own tests
and formal `spec.mbt`. From the bottom up:

| Layer | Package(s) | What it does |
|---|---|---|
| **Value language** | `core/` — `marianoguerra/tutuca/core` (`value_*.mbt`, `path_*.mbt`) | The tutuca value syntax — parse/tokenize/eval — plus the reactive path/dispatch system (COW spine rebuild, handler dispatch, change sets). |
| **Templates** | `anode/` | Parses the HTML-ish view syntax into an AST: attributes, directives, `x-` ops, macros, whitespace handling, optimization. |
| **Virtual DOM** | `vdom/` (+ `vdom/memdom`, `vdom/browser`, `vdom/wasm`) | Builds and incrementally morphs a VDOM against any DOM implementing the `DomNode` trait. |
| **Render** | `render/` | Turns a parsed view + a value stack into a `@vdom.Vdom` tree (loops, scopes, event-path metas, teleport). |
| **Components / App** | `component/`, `app/` (+ `app/browser`, `app/wasm`), `transactor/` | Typed-state component definitions (a plain `derive(ToJson, FromJson)` struct + one `Dispatch` update match), the app runtime, and the transactor that routes events at the root and settles state. |
| **Tooling** | `lint/`, `inspector/`, `viewgen/`, `cli/` | The linter (parse-issue rules + a WHATWG-tokenizer structural HTML linter), a schema inspector, the ahead-of-time view compiler, and the native `tutuca` CLI. |
| **Testing** | `testing/harness` | A reusable harness to mount and drive a `ModuleDef` on the in-memory DOM. |
| **Demos & docs** | `examples/`, `demo/`, `playground/`, `storybook/` | 32 ported examples, browser/CLI/wasm demo hosts, an in-browser playground, and a compiled storybook gallery. |

The `tutuca` CLI exposes `get` / `list` / `examples` / `show` / `lint` /
`render` / `storybook` / `gen-views` / `install-skill`.

## Ahead-of-time views (`gen-views`)

A component can keep its views in an `.html` file and compile them ahead of
time into a companion MoonBit module, so the view's vocabulary stops being
strings the compiler cannot see:

```sh
moon run --target native cmd/main -- gen-views demo/counterlib/counter.html --name Counter
# -> demo/counterlib/counter_view_gen.mbt (checked in; regenerate, never edit)
```

The file is either one bare view, or several `<template>` elements whose `id`
attributes name them — the one with no `id` is `main`. A `<style>` inside a
template is that view's style; one at file level is the component's common
style, or its global style with `data-global`.

For a component named `Counter` the generated module declares
`counter_main_view` / `counter_views()` (the sources, for `component()`),
`CounterInput` and `CounterMsg` (`@on` handler names, with payload types
inferred from the argument shapes at the call sites, plus
`CounterMsg::of_dispatch`), `CounterMethod` with `counter_mutate` /
`counter_compute` / `counter_swap` (the `$`-callables, as exhaustive matches),
`CounterView` / `CounterId`, and `counter_fields` /
`counter_missing_fields`. The package it lands in must import
`"marianoguerra/tutuca/core" @tutuca`, `"marianoguerra/tutuca/component"` and
`"moonbitlang/core/debug"`.

The payoff is in `update` (see `demo/counterlib/` for the worked example):

```mbt nocheck
update=(s : CounterState, msg, _ctx) => match CounterMsg::of_dispatch(msg) {
  Some(Add(d)) => ...          // `d` is a Double: `@on.click="add 1"`
  Some(SetLabel(l)) => ...     // `l` is a String: `@on.input="setLabel value"`
  Some(ResetCount) => None
  Some(Unknown(_, _)) | None => None
}
```

Adding `@on.click="del 1"` to `counter.html` and regenerating makes that match
non-exhaustive — a compile error naming `Some(Del(_))`, where the old
string-matched `_ => None` arm silently did nothing.

### The compiled tree

`gen-views` also emits `<stem>_view_ir_gen.mbt`: the `@anode.ANode` tree and
event table each view parses into, as MoonBit literals. Pass it as
`compiled_views~` and the template parser never runs at startup:

```moonbit nocheck
@component.component(
  name="Counter",
  compiled_views=counter_compiled_views(),   // instead of view~ / views~
  init=CounterState::{ label: "Counter", count: 0, history: [] },
  update=...,
)
```

There is no serialization format and no decoder: the AST is `pub(all)`, so the
tree is expressed as plain constructor syntax. `@anode.ParseContext::from_ir`
recovers the node table from the tree itself (every registered node carries
its `node_id`), and `View::from_ir` stamps `data-vid` and runs the
constant-subtree optimization at load — `RenderOnce` ids are process-global
renderer memo keys, so they must be minted at load time, not baked in.

A view that calls a macro cannot be compiled ahead of time (macros are
registered from MoonBit at runtime), so the whole file falls back to the
source path; `--no-ir` opts out by hand. Across the ported example library,
306 of 324 views compile to a tree.

Regenerate through the task, not the CLI — `moon fmt` owns the layout of the
generated pair:

```sh
moon run --target native cmd/dev -- gen-views    # generate + fmt
git diff --exit-code                             # drift check
```

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
tooling and testing details, and [examples/README.md](examples/README.md) for
how a JS example becomes a MoonBit one.

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
