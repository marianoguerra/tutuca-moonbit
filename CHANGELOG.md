# Changelog

All notable changes to this project are documented here. The format is based on
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and this project
adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Changed

- **A no-op interaction no longer re-renders.** Writing a component field the
  value it already holds now keeps the instance — and so the root — as the
  SAME object, so the transactor reports no swap and `App::render_now` is
  never reached. Getting there meant preserving identity at three seams that
  were throwing it away on every update: an instance now memoizes its `Value`
  (each `Obj(self)` cast used to allocate a fresh one); `with_state` keeps the
  old object for every encoded field equal to the one it replaces, instead of
  taking whatever the `Json` round trip rebuilt; and `TypedInstance::set`,
  `Value::with_field`/`with_item` and the transactor's root check all
  short-circuit an unchanged write. `patch noop todo 1000` went 8.33 ms → 19.5
  µs (−99.8%); `toggle`, `add+remove`, `move` and the render path are
  unchanged within noise. See `benchmarks/OPTIMIZATIONS.md` #6.
- **The CLI does only what the compiler cannot.** tutuca-mb compiles ahead of
  time, so mimicking the JS CLI's dynamic module inspection was answering
  questions later and more weakly than the build already answers them. The
  module commands (`get`, `list`, `examples`, `show`, `lint`, `render`),
  `plan_with_module`, the component linter behind `lint`, and the
  `demo/counter_cli` embedding demo are all removed — as is the idea that a
  project embeds the CLI. What ships is `gen-views`, `watch`, `storybook`,
  `install-skill`, `feedback`, `agent-context` and `help`: the jobs that
  genuinely happen outside the compiler. View checking runs at GENERATION
  time (a view that would emit a parse issue fails `gen-views`), and
  everything the linter used to report about fields and handlers is a type
  error in the generated view module.
- `agent-context` is `schemaVersion` 5: one command set, no `mode`, no
  `lintCodes`, no `formats`, no per-command `needsModule` / `needsEnv` /
  `defaultFormat`. Its `invocation.note` says where the checks went, so an
  agent reading the schema does not go looking for a `lint` command.
- Global flags are `--json` and `--help`. `--format`, `--output` and
  `--pretty` existed to shape module-command output and are gone with it;
  `--json` now only switches the error envelope. Exit codes are 0 and 1 —
  2 (lint findings) and 3 (render crash) went with their commands.
- The storybook's per-story Lint panel and the inspector's Lint view are
  removed along with the linter that fed them.
- `tutuca storybook` is a static file server and nothing else: `--dry-run` and
  the accepted-but-ignored `--no-margaui` / `--no-check` / `--no-tests` are
  gone. With them went the runtime `cli` → `storybook` dependency, so the
  storybook packages are now excluded from the published archive and stay in
  the repo as demos and as the corpus the view-generation sweep runs over.
- `README.md` is a short repository README rather than a symlink to
  `README.mbt.md`; the detailed guide remains the executable `README.mbt.md`.
- One parameterized guest builder (`guests/build-guest.mjs <name>`) replaces
  the duplicated `guests/{counter,todo}/build.mjs`, and
  `dyncomp/wit/tutuca-component.wit` is the sole WIT: the per-guest copies are
  gone and every guest (including the Rust one) reads that file.

### Added

- `cmd/dev -- gen-guest-bindings`: regenerate both MoonBit guest binding trees
  from the canonical WIT and drift-check them. `wit-bindgen` emits its FFI
  shims in hash order, so `guests/gen-bindings.mjs` normalizes the output —
  which is what makes the checked-in trees reproducible at all.
- `@render.RenderCache::stats` / `::size`: read the hit/miss counters and entry
  counts without clearing the cache, which `evict` cannot do.
- `@tutuca.same_node`: physical identity across the `&PathNode` trait-object
  boxing, which a plain `physical_equal` defeats.

### Removed

- A large amount of public API that nothing outside its own package used:
  `@cli`'s command-dispatch internals (`run_help`, `run_storybook`,
  `render_error`, `did_you_mean`, the command tables …), `@anode`'s AST
  mutators and macro internals, `@core`'s `Pred` accessors and `step_put`,
  `@transactor`'s `Completion` API, `@vdom`'s `morph_node`/`morph_children`
  and namespace URIs, `@viewgen`'s naming helpers, `@inspector`'s per-view
  methods, and `@component`'s `FieldSpec` constructors. The stable CLI error
  codes and `warn_hook` stay public — they are documented extension points.
  `@core.Val::render`, `@core.Value::entries` and `@core.parse_handler_arg`
  were dead and are deleted outright.
- `@cli.plan_with_module`, `@cli.check_component` and the whole component
  linter (`LintFinding`, `LintRule`, the rule/style tables), `@cli.stub` and
  `CmdImpl`, `CliMode`, and `@inspector`'s lint report components. `GlobalOpts`
  is down to `json` and `help`.

## [0.5.3]

### Added

- `benchmarks/` — three benchmark suites, all target-agnostic (the view corpora
  are embedded as strings and `@memdom` runs everywhere, so they need neither a
  filesystem nor a browser): the **view pipeline** over every view `.html` in
  the repo, both as one file of 108 views and as one enormous view, plus a
  1×/2×/4× probe for costs that are superlinear in a single view's size; the
  **render path** over all 50 usable example modules and over lists of 0 to
  1000 items in four shapes; and **diff/patch**, where each workload is a change
  and the change back applied to an app mounted once, from a no-op through a
  one-row edit to switching views. `benchmarks/report.mjs` collapses `moon
  bench`'s output to one line per benchmark and takes `--save` / `--baseline`
  for A/B runs; `cmd/dev -- bench` and `-- bench-views` drive it, and
  `benchmarks/OPTIMIZATIONS.md` is the log. Repo-only, excluded from
  `moon package`.
- `@viewgen.emit_ir_module_opt`: the companion IR module, or None when the file
  cannot be emitted as compiled trees — `ir_supported` and `emit_ir_module` in
  one pass. `ir_supported` stays for callers that only want the answer.
- `@anode` builders for the AST: `h`, `text`, `dyn_text`, `frag`, `attr` /
  `attr_num` / `dyn_attr` / `if_attr` / `eid`, `show` / `hide` / `each` /
  `render` / `scope`, `on`, and the `const_*` value shorthands. They are the
  parser's own output with the rarely-set fields defaulted — hyperscript-shaped
  constructors, not a new representation — so a hand-written view or test can
  build a tree the renderer cannot tell from a parsed one. `@anode.h` chooses
  ConstAttrs vs DynAttrs through `attrs_of_items`, the rule the attribute
  parser now also calls, so the two paths cannot disagree.

### Changed

- Performance, all measured on `benchmarks/` and all leaving output
  byte-identical (the generated `*_view_gen.mbt` files still regenerate
  unchanged, and the DOM snapshots in the test suite are untouched):
  - `tutuca gen-views` is 16–18% faster. `if ir_supported(file) {
    emit_ir_module(...) }` compiled every view twice, since both halves go
    through the same parse; with `emit_module`'s own pass that made three
    compiles of every view per job. `emit_ir_module_opt` does the check by
    emitting.
  - `@viewgen`'s `split` stage is 6% faster and no longer superlinear in a view
    file's size: recovering a view's source walked its span one character at a
    time and rescanned the whole style-region array at each one. It now copies
    the runs between the regions.
  - Rendering is up to 21% faster and updating up to 34%. Every render site and
    every `@each` iteration emits a `§{…}§` boundary comment, and building it
    meant allocating a `Json` object and stringifying it — ~2000 of them per
    pass for a 1000-row list. Those, and the render cache's per-slot key, are
    now written straight into a `StringBuilder`.
- `@harness.Harness::find` stops at the match it asks for instead of collecting
  every match in the DOM and indexing one. Same semantics; on a long list it is
  the difference between a full-tree walk and a few nodes, which is worth 30–78%
  on the update benchmarks and shows up in any test that drives a large DOM.
- `gen-views` emits the compiled tree with those builders instead of raw
  struct literals: the 26 checked-in `*_view_ir_gen.mbt` files went from 6530
  to 3121 lines, and a `<button class="x">-</button>` from seven lines to one.
  Three things it used to write are now recovered at load: the `NodeEvents`
  ids (an id is the entry's position, so the table is a plain
  `[[on(…)], …]`), the `data-vid` stamp (`View::from_ir` applies it anyway),
  and the ConstAttrs/DynAttrs choice.
- `@anode.View::from_ir` takes the handler table
  (`Array[Array[NodeEvent]]`) instead of a `ParseContext`, and builds the
  context itself — the caller no longer names `root` twice or constructs a
  parse context to hand straight back.
- The generated `XMsg::of_dispatch` is now `XMsg::from_dispatch`, matching the
  `from_*` prefix the rest of the codebase and MoonBit core use for named
  source conversions (`View::from_ir`, `Value::from_json`). The suffix stays:
  it names the source type, which is the only place a reader of an `update`
  closure learns that `msg` is a `@component.Dispatch`.
- `@viewgen.compiled_views` is now `@viewgen.build_views`. The old name
  predates 0.5.0, when the component argument was `compiled_views~`; with
  views always being `@anode.View` values there is no compiled-vs-uncompiled
  distinction left to name.
- The `gen-views` task runs `moon fmt` after generating. The CLI emits
  unformatted source, so `gen-views` followed by `git diff --exit-code` — the
  drift check the docs describe — always reported churn before this.
- `marianoguerra/tailwindcss` is now 0.2.0 (was 0.1.3). The two APIs tutuca
  uses are unchanged (`compile_sync` for `demo/margaui`, `collect_imports` for
  `cmd/margaui-bundle`): the compiled margaui CSS and the regenerated
  `demo/assets/margaui.bundle.json` are byte-identical to 0.1.3's.
- The `margaui-bundle` task no longer needs a sibling `../margaui` working
  copy. `scripts/fetch-margaui.mjs` clones margaui from GitHub at a pinned tag
  into the gitignored `_build/margaui`, which is also the tool's new default
  `--base`. The pin is what makes the committed bundle reproducible — anyone
  can now regenerate it and get the same bytes; before, the result depended on
  whatever state the local checkout happened to be in. Bump `MARGAUI_REF` to
  pick up new margaui CSS.

### Fixed

- Every GitHub link on the landing site pointed at `marianoguerra/tutuca`,
  the upstream JS framework, rather than at this port
  (`marianoguerra/tutuca-moonbit`). "What's Next" now links both, and the
  nav / hero / footer link the port.
- The example library's last runtime-built static views (counter,
  personal_site, filter_paginate) are compiled ahead of time. What still
  builds views at runtime does so because it cannot be generated: dyncomp
  guest bundles, macro-using and programmatically-assembled views,
  deliberately-broken lint fixtures, the playground's editable examples, and
  test fixtures.
- Documentation that still described the pre-0.4 view arguments
  (`view~` / `style~` / `view_styles`), the pre-typed-state component API,
  removed generated constants, renamed demo packages, and moved example
  paths.

## [0.5.0]

### Changed — `compiled_views~` renamed to `views~` (breaking)

Now that it is the only view argument, the `compiled_` qualifier was
redundant: `component(...)` and `Component::for_type(...)` take `views~ :
Map[String, @anode.View]`. `tutuca gen-views` emits the builder as
`counter_views()` (was `counter_compiled_views()`), so a component reads
`views=counter_views()`.

The generated types module no longer emits the dead source-string constants
(`counter_main_view`, `counter_views()` returning `Map[String, String]`,
`counter_style`, `counter_view_styles()`) — they existed only for the removed
`view~` / `views~` / `style~` arguments. `counter_common_style` /
`counter_global_style` stay (they back `common_style~` / `global_style~`), and
each view's own style rides inside its `@anode.View`.

## [0.4.0]

### Changed — views are `@anode.View` values, not strings (breaking)

`component(...)` and `Component::for_type(...)` no longer take `view~` /
`views~` / `style~` / `view_styles~`. The view input is now
`compiled_views~ : Map[String, @anode.View]` — a view is a built `@anode.View`,
keyed by name (`"main"` renders by default), each carrying its own per-view
style. Component-level `common_style` / `global_style` stay.

Build the map either way:

- **Ahead of time** (recommended) — `tutuca gen-views counter.html` emits
  `counter_compiled_views()`; pass `compiled_views=counter_compiled_views()`.
- **At runtime** — `@anode.View::new("main", raw_view="…", style~)` for a
  genuinely dynamic view (e.g. the dyncomp guest bundle) or a test fixture.
  This is the same primitive the generated code sits on.

Migration: replace `view="…"` with
`compiled_views={ "main": @anode.View::new("main", raw_view="…") }`, and add
each `views` entry / `style` the same way; or move the views into an `.html`
file and generate the map. The whole repo (examples, docs, inspector, demos)
moved over; the demo shows the gen-views path end to end.

### `tutuca watch`, HTML macros, multi-component files

Also in this release (were staged as 0.3.1): `tutuca watch` regenerates view
modules on save; macros are declared in the view file
(`<template id="macro:…">`) and expanded at generation time; one view file
names several components with `id="Counter:main"`; the structural-HTML and
parse-issue lint rules run at generation time; the lint package renders its
own findings.

## [0.3.1]

### Added — ahead-of-time view compilation (`tutuca gen-views`)

An optional AOT step: an `.html` file of views compiles into a companion
MoonBit module of typed view surfaces, so a view's vocabulary stops being
strings the compiler cannot see. This is **additive** — `component(view~)`
still works unchanged; a component opts in by passing `compiled_views~`.

- `tutuca gen-views <file.html>` emits two modules: the types
  (`CounterInput` / `CounterMsg` with `of_dispatch`, whose payload types are
  inferred from the `@on` call sites; `CounterMethod` bucket builders;
  `CounterView` / `CounterId`; the field list) and the already-compiled
  `@anode` tree (`counter_compiled_views()`), which lets `compiled_views~`
  skip template parsing at startup. Adding an `@on` handler to the view and
  regenerating turns the component's `update` match non-exhaustive — a
  compile error where the string-matched `_ => None` arm used to do nothing.
- One view file per module, naming several components with
  `id="Counter:main"`. Macros are declared in the file
  (`<template id="macro:icon">`) and expanded at generation time, so a macro
  view compiles to a tree too.
- `tutuca watch [path…]` regenerates managed view files on every save
  (mizchi/fswatch).
- The structural-HTML and parse-issue lint rules now also run at generation
  time, and the lint package renders its own findings (message rendering
  moved from `cli`).
- The in-browser playground gains a View tab that generates the module the
  Component tab imports, live.

### Changed — typed-state components (breaking)

The dynamic component API was replaced by a typed-state model (inspired by
[rabbita](https://github.com/moonbit-community/rabbita)'s TEA shape):

- State is a plain struct with `derive(ToJson, FromJson)`; `component(...)`
  takes `init~` instead of `fields=` and every handler is compiler-checked
  against the struct. `Instance`, `InstanceHandler` and `MethodFn` are gone;
  `Component::make` returns the instance as a `@tutuca.Value`.
- The four effectful buckets (`input`/`receive`/`bubble`/`response`) fold
  into ONE `update : (S, Dispatch, &Ctx) -> S?` pattern match over the new
  `Dispatch` enum. `methods` splits into `mutate` (pure state changes,
  `$name`) and `compute` (value reads, `$label`).
- `alter` splits into four typed render-time buckets matching the directive
  call conventions: `when : (S, key, value, iter) -> Bool`,
  `enrich : (S, binds, key, value, iter) -> Unit`,
  `enrich_scope : (S) -> Map[String, Value]`, and
  `loop_with : (S, seq, LoopCtx) -> LoopWith`.
- Child-component slots and Set/OMap kinds are declared via `specs=`
  (`FieldSpec::comp` / `::set` / `::omap`); fields of type `@tutuca.Value`
  (or collections of it) carry instances/functions losslessly through state
  updates via a core value stash (`with_value_stash` + `ToJson`/`FromJson`
  impls for `Value`).
- Core gains coercing accessors on `Value`: `int` / `num` / `str` / `bool` /
  `list` / `entries` / `field`.
- The inspector's component summary now reports the typed buckets (fields /
  methods / update flag / alter / views).

## [0.1.0]

Initial public release: a MoonBit port of the
[tutuca](https://github.com/marianoguerra/tutuca) UI framework.

- Value language (parse / tokenize / eval) and reactive path/dispatch system.
- `anode` template parser, `render` layer, `component`/`app`/`transactor`
  runtime.
- Virtual DOM (`vdom`) with in-memory, js (real DOM), and wasm-gc backends.
- `lint` (parse-issue rules + structural HTML linter) and `inspector`.
- Native `tutuca` CLI (`get` / `list` / `examples` / `show` / `lint` /
  `render` / `storybook` / `install-skill`).
- 32 ported examples, browser/CLI/wasm demos, an in-browser playground, and a
  compiled storybook gallery.

[Unreleased]: https://github.com/marianoguerra/tutuca-moonbit/compare/v0.1.0...HEAD
[0.1.0]: https://github.com/marianoguerra/tutuca-moonbit/releases/tag/v0.1.0
