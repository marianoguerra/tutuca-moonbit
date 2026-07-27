# Changelog

All notable changes to this project are documented here. The format is based on
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and this project
adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Added

- **A component instance can describe itself.** `@tutuca.Obj` gains
  `obj_schema()`, and with it the whole generic-access layer in `@tutuca`:
  `Value::field_opt` / `item` / `index` / `key` / `entries` / `size` /
  `field_names` / `field_info` / `snapshot` / `call` / `call_field`, the `_opt`
  coercers, total copy-on-write `with_field` / `with_item`, and the
  Path-addressed `at` / `at_opt` / `with_at` with fluent `Path::field` /
  `index` / `key` and a `Show` for `Path`.

  Holding a bare `Value`, you can now ask what fields it has, what type each
  one is, how long a sequence is and what its items are. Before, you could ask
  for a NAMED field and nothing else, and every consumer worked around that
  differently: the inspector took the field names from a `Components` registry
  or a hardcoded literal list, the dyncomp host parsed a
  `__dyncomp_state_json` pseudo-field, `state_json()` returned the `Show`
  rendering and said so in a comment.

  Concretely: the inspector opens a component instance into its fields instead
  of one line of `obj_debug` text; `Value::to_json` projects a described
  instance instead of flattening it to null; `size_of` answers for a custom
  collection; `obj_eq` and `obj_debug` come off the schema rather than being
  hand-written per implementor (`DynObj` had never implemented `obj_eq` at
  all, so two guest instances never compared equal).

### Fixed

- **`.seq[.key]` on a custom collection.** The seq-access evaluator spelled the
  container match out itself and its copy had lost the `Obj` arm, so a
  collection that `@each` iterated fine answered `Null` through seq-access. All
  four copies of that match are one lookup now.

### Changed (BREAKING)

- **`component()` takes `encode`, `decode` and `schema` off the state type, not
  as parameters.** They are the three methods of `@tutuca.Fields`, which the
  state type implements; `component()` is bounded on it and the three
  parameters are gone. `gen-views` writes the impl, so a component with a view
  file changes nothing at its call site — it just stops passing three
  arguments. A hand-written state writes three short methods instead, in a
  place that cannot drift from the type they describe. One consequence is
  deliberate: a schema now belongs to a TYPE, so two components sharing a state
  struct share its description.

- **`FieldKind`, `FieldInfo` and `SchemaInfo` moved to `@tutuca`.** They
  mention only `Value`, and living in `component/` put them out of reach of
  everything that has only a `Value` — which is what `obj_schema` needed. They
  are re-exported, so `@component.SchemaInfo` still resolves; an enum
  CONSTRUCTOR does not travel through a re-export, so `@component.FBool`
  becomes `@tutuca.FBool` or bare `FBool` (the generator writes it bare).
  `SchemaInfo` also gains `name`, which `component()` fills in from its own
  `name~` when a hand-written descriptor leaves it unstated.

- **`instance_snapshot(v, comp)` takes the descriptor as an option**, and
  `instance_args(v, names)` drops its name list: both read the instance now.

- **`component()` requires `schema~`, `encode~` and `decode~`; `for_type()`
  requires `schema~`.** They were optional, and omitting them was the normal
  case — each omission had the runtime do the work instead. There is one
  component shape now, and no shape that specifies less. `gen-views` writes all
  three, so a component with a view file passes them through its generated
  wrapper and nothing changes at the call site; a component built by hand
  supplies them by hand, complete. `SchemaInfo::new` / `FieldInfo::new` default
  the channels a hand-written descriptor does not use.

- **The state struct needs no derives.** `component()` no longer bounds `S` on
  `ToJson + FromJson` — the generated codec does the conversion — so the
  generator stops emitting `derive(ToJson, FromJson)` and a state struct is a
  plain struct. A keyword field no longer needs
  `derive(ToJson(fields(type_(rename="type"))))` either: the codec keys by the
  runtime name.

- **The generated `<C>State` and `<c>_component` are `pub`.** They were
  package-private, which made a generated component unusable from another
  package or from a blackbox test — including the executable guides.

- **Handler buckets are keyed by generated enums, not strings.** `compute`,
  `swap`, `when`, `enrich`, `enrich_scope` and `loop_with` were
  `Map[String, closure]`; each is now a function from an enum generated out of
  the names the views use, so a `$name` or an `@when` added to a view makes the
  author's match non-exhaustive. A bucket the views never use is not a
  parameter at all. `swap` is keyed by the INPUT enum — it answers an Input
  dispatch ahead of `update`, not a `$name`.

- **`Component.schema` is no longer an Option**, and `compute_names`,
  `generated_names` and `has_update` are gone from `Component`.

- **`ObserveMatch::Unknown` is gone** with the `"$unknown"` catch-all it
  reported: dispatch does one lookup, so a miss is a miss.

### Performance

- **An ahead-of-time wasm bundle is 44.9% smaller.** `View::compile` branched
  on an `ir : Bool`, so every program that compiled a view named
  `ANode::parse` — and through it the vendored WHATWG HTML tokenizer — on the
  branch it did not take. A linker cannot prune a runtime `if`. The flag is
  the parse step itself now: only `View::new` names the parser, so a program
  built entirely ahead of time does not link one. `demo/counter_wasm`:
  438,803 → 241,941 bytes. No call site changed.

### Removed

- **The JSON state bridge and its stash.** `encode_state` / `decode_state`
  converted state through `S -> Json -> Value` for a component with no
  generated codec, and `core`'s `with_value_stash` existed solely to smuggle
  `Obj` and `Fn` across that trip as `{"\u{0}tutuca-ref\u{0}": i}` markers.
  Both are deleted, along with the process-global mutable and the "strictly
  synchronous" caveat it carried. It was measured at ~2x slower on encode and
  ~5x on decode; see `benchmarks/OPTIMIZATIONS.md`.

- **`FieldSpec::of_default`**, which read a field's kind off its seed value —
  why `FInt` vs `FFloat` depended on whether a double happened to be integral.

- **The reflected component description** (`summary_from_specs`). The inspector
  reads one source: what the component declares. Field rows show the author's
  WIT spelling rather than a label rebuilt from a runtime kind, and `update`
  lists the names it answers instead of the bare fact that it exists.

- **The `"$unknown"` handler sentinel**, a second string lookup on every
  dispatch miss.

### Added

- **A WIT `func` in the state block declares a `$`-callable.** A method a
  PARENT calls on a component — `contains-text: func(q: string) -> bool;`,
  asked by a list's `@when` of every child regardless of the child's shape —
  appears in no view of the component itself, so the schema is the only place
  it can be named. The parser used to reject `func` outright, on the grounds
  that behaviour lives in the MoonBit `update`; that is right about event
  handlers and wrong about a value a parent reads.

- **`gen-views` drift-checks its own output**, and `ci` runs it. A stale
  `*_view_gen.mbt` type-checks and tests green while no longer describing the
  `.html` beside it, and nothing caught that before.

- **Direct codecs for every schema-backed component**, `record` / `enum` /
  `variant` / `option` / `tuple` included, and for a state with no carried
  fields at all. Previously 79 of 93 components had one and the rest fell back
  to the JSON bridge.

- **A component's state can be declared in the view file, in a subset of WIT,
  and is then generated.** A `<script type="tutuca/state">` block holds one
  `interface` per component and one `record state` in each; `gen-views` emits
  the struct, a `zero()`, a `Field` table whose `kind()` is *declared*, the
  state <-> Value codec, and the `specs~` map. Sets, ordered maps and
  child slots — the three kinds a struct could never express, and which had to
  be threaded by hand through `specs~` and `missing_fields(extra~)` — are now
  written in the schema and derived from it.

  It rides in a `<script>` and not a `<template>` because script content is raw
  text to an HTML parser while template content is markup: `list<s32>` inside a
  template parses as an `<s32>` element.

  Parsed with `mizchi/wit`. WIT rather than a bespoke DSL because tutuca
  already speaks it at the dyncomp boundary and because its type lattice maps
  almost exactly onto `FieldKind`. What WIT genuinely cannot spell — an open
  type, an ordered map (WIT's own `map` is unordered by definition), a child
  component — arrives as a marker name (`any`, `text-set`, `value-omap`, or a
  sibling interface's name).
- **Named initial states**, in a `<script type="tutuca/init">` block of their
  own, because a default is a value and not a type. Each is checked against the
  schema at generation time — a fixture setting a field the schema dropped, or
  writing `2.5` into an `s32`, fails the build instead of being coerced away at
  runtime — and becomes `State::fresh()` plus a public `<v>_init_args("fresh")`
  for a `ModuleDef` example.
- **Typed `Receive` / `Bubble` / `Response` buckets.** These names are raised
  from MoonBit rather than written in a view, so the views could never type
  them; the schema can. Each declared bucket gets an enum, a bucket-scoped
  `from_dispatch`, and a `to_dispatch` plus sender, so a message name is
  written once instead of twice as a matching pair of string literals. An
  integer payload is integrality- and range-checked rather than truncated.
- **Direct state <-> Value codecs, generated from the schema.** The runtime
  bridged typed state to the Value world through `Json` — `S -> Json -> Value`
  and back, once per state write, inside `with_value_stash` because `Obj` and
  `Fn` cannot survive JSON at all. With the schema in hand the conversion is
  written field by field, and a field that already holds a `Value` is passed
  straight through instead of being rescued from a round trip it never needed
  to take. `component()` takes them as `encode~`/`decode~`; a component with no
  schema still uses the JSON bridge. Adopted only after measuring, because it
  is a second encoder to keep in step with the derived one: **encode ~2x,
  decode ~5x** in isolation (`benchmarks/codec_bench_test.mbt`), and an
  interleaved A/B on the render path puts `patch counter` at 19.0/19.5 µs
  against 20.3 µs — a few percent, which is what a bridge that is not the
  bottleneck should look like.
- **The generator exports a static description, and the inspector reads it.**
  `gen-views` emits `<v>_schema()`, a `@component.SchemaInfo` carrying the
  field types with their element types and a `flags` set's members, the `@on`
  names the views raise, the declared message buckets, the constant element
  ids, the view names and the named fixtures. A component passes it as
  `schema~`.

  The headline is `update`. At runtime it is one opaque pattern match, so
  introspection could only ever report THAT an update exists — the component
  inspector literally rendered `["update"]`. The schema knows every name it
  answers, and the panel now lists them. Receive / Bubble / Response appear at
  all for the first time: those names are raised from MoonBit, never written
  in a view, so nothing at runtime could recover them.

  Passing `schema~` also stops `component()` inferring field kinds from the
  encoded init value — the guess that made `FInt` vs `FFloat` depend on
  whether a seed double happened to be integral. Two sources of truth for the
  same fact is worse than either alone, so the declared kind simply wins. A
  component with no schema keeps the reflection path unchanged, which is what
  every unmigrated one still uses.

  This supersedes the generated `<v>_specs()` helper, which was emitted but
  never passed by anything — the runtime was guessing kinds it had already
  been told. Removed. Net cost to a generated module: ~700 bytes.

- **Schema-only view files.** A file may carry a `tutuca/state` block and no
  `<template>`, which is how a component whose views are built in MoonBit
  still gets a generated state type — the schema lives in a view file, so it
  needs one even with no views. One file may also mix the two: templates for
  some components, state alone for others. An interface with no template is
  reported as a hint rather than an error, because it is also what a mistyped
  interface name looks like.
- **`gen-views --wit`** writes the schema back out as a self-contained `.wit`
  document for `wit-bindgen`, with the markers lowered; `<v>_schema_fingerprint`
  is its structural identity, over shape rather than over source text.

### Fixed

- **The benchmark view corpora had become unparseable, and nothing noticed.**
  `moon test` does not execute a `bench` body, so a corpus that no longer
  splits fails only under `moon bench`. Once view files started carrying
  schema blocks, `all_views` — every view file concatenated into one —
  collected 36 of them, which `split_file` rightly refuses; and a
  `<template>` written inside a schema *comment* was taken for an opening
  tag, unbalancing `one_big_view`. The corpus builder now strips schema
  blocks before anything scans for tags, and a plain test asserts both
  corpora split.

- **`@push-view` and `@enrich-with` were treated as opening a new state
  scope.** `@push-view` pushes a view NAME onto the render stack
  (`render/render.mbt`, `push_view_name`) and `@enrich-with` pushes binds;
  neither changes what `.field` addresses. Found by the new view checker while
  migrating `storybook/examples/rendering`.
- **The embedded Tailwind stylesheets were a minor version behind the compiler
  reading them.** `theme.css` / `preflight.css` came from margaui's `tw/`
  directory, which margaui's own README calls a manual mirror — at v0.5606.3 it
  was still missing the `mauve`, `olive`, `mist` and `taupe` palettes upstream
  added in **4.3.2**, on top of 4.3.3's `--font-sans` change and the
  `oklch(… 0 none)` achromatic form for `zinc-50` and `neutral-50…950` (at
  v0.5704.0 the palettes and the font stack are still behind).
  Meanwhile `marianoguerra/tailwindcss` is ported from **v4.3.3** exactly. The
  `css-bundle` task now takes those three files from the `tailwindcss` npm
  tarball pinned to the port's own `UPSTREAM.md` tag, and
  `scripts/fetch-tailwind.mjs` fails the build if the two pins drift apart;
  margaui's copies are dropped from its bundle (`--skip-prefix tw/`) and its
  `./tw/*` imports resolve against the good ones. The wasm demos gain the four
  palettes and a different default `--font-sans` stack.

### Changed

- **The `mutate` bucket is removed (breaking).** With `$` refused at an `@on`
  site, `mutate` had no job left that `update` does not do: both are reached
  by the same bare name and the same dispatch, `update` is strictly more
  capable (it gets a `ctx`), and nothing internal used the bucket — the
  generated setters live in their own table. Its one remaining claim was
  purity-by-signature, which is not worth a second place for a handler to
  live.

  `component()` loses the `mutate~` parameter, `TypedSpec` loses the field
  and its three dispatch reads, and `gen-views` stops emitting the
  `<v>_mutate` builder. All 41 call sites across 24 files are migrated by
  hand: 21 were a rename, 8 genuinely transformed (an untyped `Array[Value]`
  becomes the typed payload of a `<C>Msg` variant), and the shared inspector
  paging bucket became a `composite_update` helper that a component's own
  `update` delegates to from its fallback arm.

  `compute` and `swap` stay. `compute` answers a `$name` in a VALUE position
  (`@text="$label"`), where there is no event and no ctx and an `update` arm
  cannot reach; `swap` returns a `Value`, so it can replace a node with a
  different component's instance, which `update` — returning `S?` — cannot.

- **A `$name` in an `@on` handler position is now a generation error.** It
  was never a second mechanism: `app/app.mbt` collapses `HandlerName` and
  `Method` into one string and hands both to `push_input`, so `@on.click="$inc"`
  and `@on.click="inc"` are the *same dispatch* — verified for user buckets
  and for the generated mutators, which answer to either spelling. The sigil
  therefore claimed a distinction that does not exist, and readers reasonably
  inferred one. `$` keeps its meaning where it has one: a value position
  (`@text="$label"`, `@show="$canSubmit"`), where there is no event and no
  `ctx` and an input handler cannot go.

  All 338 call sites across 33 view files are rewritten to bare names. A name
  that moves from `$` to bare moves from `<C>Method` into `<C>Msg`, so six
  `update` matches gained a fall-through arm returning `None` — which is how
  a handler served by a generated mutator was always meant to read.

- **Views are now type-checked against the state schema (breaking for any
  component that adopts one).** An unknown `.field` is a generation failure
  naming the near miss, where it used to render as `null` in the browser. The
  check reaches **inside `@each` bodies** — with the element type in hand,
  `@value.titel` in a loop is caught, where before it was not merely unchecked
  but not even looked at. Also checked: `@each` over a non-collection, and
  `<x render>` on something that is not a component. Unknown is never wrong — a
  `$method` result, an `any` field and a child component's fields all open an
  opaque scope that silences the checks inside it.
- **`<v>_fields` / `<v>_missing_fields` are no longer emitted for a
  schema-backed component.** They existed because the generator could not check
  a read: they listed the names and left you to assert, in a test you had to
  remember to write, that the state carried them — and they only ever covered a
  view's root scope. A component with no schema block still gets them, and
  generates exactly what it generated before.
- **Every example with a view file now declares its schema**: all 26 view files
  across `demo/` and `storybook/examples`, 70 components in total. The five
  example files that build their views at runtime (`macros`, `visual_wasm`,
  `lint_errors`, `svg_more`, `todo_macros`) have no view file to hold a block
  and keep their hand-written structs — the schema lives in the view file, so a
  component without one has no schema.
- **margaui bumped to v0.5704.0** (from v0.5606.3). `MARGAUI_REF` in
  `scripts/fetch-margaui.mjs` moves and `css/margaui_bundle_gen.mbt` +
  `css/assets/margaui.bundle.json` are regenerated from that tag — same 80
  files, no utility renamed or removed, so no view needs changing. New:
  `menu-paged`, a menu whose open submenu replaces the panel instead of
  expanding in place, with its `summary` turning into a "Back" row
  (`aria-label` overrides the label). Fixes across `avatar` (centred
  `align-self`), `calendar` (hover no longer washes out today/selected),
  `fieldset`, `indicator` (start/end offsets default to `auto`), `input`
  (LTR fields align by `text-align`, pixel-exact affix insets), `kbd` and
  `radial-progress` (`flex-shrink: 0`), `menu` (`[disabled]` styled like
  `menu-disabled`), `modal` (child-scoped `.modal-box`, RTL slide), `otp`
  (forced LTR), `select` (subtle placeholder colour no longer leaks to a
  wrapper's other children), and `tab` (indicator width from `--tab-p`).
  `loading` and `progress` now treat reduced motion as the default and put
  the fast animation behind `prefers-reduced-motion: no-preference`. margaui's
  own `tw/*.css` is still skipped — the stock Tailwind stylesheets keep coming
  from the pinned npm tarball.
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

- **`tutuca gen-tailwind-css` and `tutuca gen-margaui-css`** — build-time CSS
  from a project's views. tutuca already knows which classes a view uses; these
  run that same collection over the view *files* and compile the result, so an
  ahead-of-time project can ship a static stylesheet holding exactly the
  utilities it uses, with no Node, no CDN and no margaui checkout. Paths follow
  `watch`'s rule (a directory contributes the `.html` files that already have a
  generated sibling), defaulting to the current directory. `gen-margaui-css`
  output is a superset of `gen-tailwind-css` for the same views. Flags:
  `-o/--out`, `--entry` (compile your own CSS entry, resolving its `@import`s
  from disk), `--polyfills`, and — for the literal-only limit the runtime
  collector also has — `--print-classes` to see what was collected and
  `--classes <file>` to add back the names a view assembles at run time.
- `tutuca watch --tailwind-css <file>` / `--margaui-css <file>` — keep a
  stylesheet current alongside the view modules, so the authoring loop is one
  process again. Rebuilt over every watched view once per settled batch (a
  stylesheet is a whole-project artifact, and compiling is the expensive half),
  and `WatchPlan` carries a whole `CssPlan` so watch runs the very same
  collect/compile/write path the one-shot commands do. `--css-entry` and
  `--css-classes` forward to their `--entry` / `--classes`.
- `css/` — a published, target-agnostic package holding the stylesheet bundles
  and `compile_tailwind` / `compile_margaui`. It replaces `demo/margaui`, which
  was wasm-gc-only and excluded from the published archive; the wasm demo hosts
  and the playground now compile through it, as does the CLI.
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
