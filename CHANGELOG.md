# Changelog

All notable changes to this project are documented here. The format is based on
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and this project
adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Added

- **A component can outlive the page it was on.** `tutuca:component` is
  `0.4.0` (manifest `api-version: 4`): an instance answers `persist()` with
  bytes ONLY IT reads, and `[static]instance.restore(component, bytes)` builds
  one back. The host stores them and never looks inside, which is what lets a
  guest keep what its declared fields do not name — which tab was open, a
  sentence half-typed. Empty bytes mean "I do not persist" and are a decision
  rather than a failure: the host can already project the declared fields and
  construct from them, so a component whose state is exactly its fields should
  say nothing and let the framework do it. A `restore` that refuses (a format
  the guest no longer reads) falls back to the same projection.

- **`dyncomp/persist`** — a `Snapshot` (what a stored component IS: the guest's
  bytes, the declared-field projection, and what it is called) and a `Store`
  (somewhere to put it). Text-shaped on purpose, with the bytes base64 inside
  the JSON, because every store worth having on a page is string-shaped and
  otherwise every implementation would invent the same encoding. Everything
  read back out is treated as untrusted input — a store is shared with whoever
  else writes to the origin. `MemStore` for a host with no browser storage;
  **`dyncomp/persist/wasm`** is `localStorage`, four calls wide, swallowing
  what a browser throws in private mode or at a full quota.

- **`Obj::obj_persist_id`** — what an instance is CALLED across sessions, which
  `obj_identity` deliberately is not (that one is a handle and a revision, both
  facts about this run). None means "do not store me" rather than "store me
  under something invented". `Bundle::make_instance` mints one when the caller
  has no better name, and `with_persist_id` takes the better name when there is
  one — a slot in a saved document, a row in a list.

- **TodoMVC, as a guest bundle** (`guests/todomvc`): add, toggle, toggle-all,
  edit in place, delete, the three filters, count-left and clear-completed.
  It is here for the split it demonstrates — `items` and `filter` are DECLARED
  (so the host owns `setFilter`, the projection, equality and migration) while
  the draft, the row being edited and its text are the guest's own, invisible to
  the host and kept anyway because `persist` writes them. Filtering is a
  `@when` the guest answers, so a filtered row still carries its index in the
  whole list and every per-row handler keeps working.

- **A universal editor over whatever is loaded: `dyncomp/ui`.** Search the
  catalog, fill in a form generated from a component's declared arguments, and
  arrange what you placed — seven ordinary tutuca components, backend-agnostic
  and driven by `moon test` on the in-memory DOM. The state it edits is the
  surface DOCUMENT, and every change (add a stack, retarget a grid's tracks,
  remove a subtree, place a component) is a `SurfaceOp` batch applied to it,
  with the rendered tree rebuilt afterwards; that ordering is what makes a
  button and a tool call the same operation rather than two that agree for now.
  Instances live BESIDE the document — it holds references and the host builds
  what they name — so a rebuild keeps their state, and an import gives the
  layout back with its slots empty rather than showing someone else's.
  `demo/universal_wasm` is the shell around it now: a drop target, a status
  line, and the bridge that turns a `ComponentRef` into a live guest instance.

- **`dyncomp/jsonschema`** — the declared schema to JSON Schema (draft 2020-12)
  and back. ONE projection with two consumers, a generated form and a tool's
  `parameters`, because two would drift in the direction of the form accepting
  what the tool rejects. `TyRecord` / `TyEnum` / `TyVariant` become a titled but
  UNCONSTRAINED `$defs` entry (the declared schema knows a record's name and not
  its fields, and claiming `type: object` would be inventing a fact); a `TyComp`
  slot becomes a component reference, since the host builds the child. Reading
  back collects EVERY error with a JSON Pointer rather than the first.

- **`dyncomp/registry`** — the catalog across loaded bundles, and search over
  it. The weights live in one place so the ranking is arguable rather than
  emergent, and every hit carries WHY it matched: a search a person cannot
  explain is one they stop trusting. Describing the catalog never calls a guest.

- **`dyncomp/surface`** — the layout model and the six-op patch algebra the
  editor drives. A flat node table with children by id, so an edit is not a
  rewrite of the path down to it; an ATOMIC batch, because a caller that got
  half a layout cannot tell what it now has; a flex/grid subset that stops at
  `Nfr` / `Npx` / `auto`, since `minmax` / `repeat` / `calc` are where a
  generated layout silently collapses; and unknown prop names as errors rather
  than silence. One document format for export, read-back and resuming.

- **`dyncomp/policy`** — the executable half of `dyncomp/SECURITY.md`. `host`
  owns the mechanics of loading and this owns the decisions, so "what can a
  dropped bundle do to my page" has one answer instead of six call sites.

- **A bundle says what it is.** `tutuca:component` is `0.3.0` (manifest
  `api-version: 3`): `doc` / `keywords` / `category` / `message-docs` per
  component, `doc` per field and per init fixture, and a `constraint` (min /
  max / lengths / pattern / format / enum / default) — the half a TYPE cannot
  state. `ty-def` says a field holds a string; the constraint says it holds an
  email under 254 characters, and a form and a JSON Schema both need the second
  half. The manifest also carries advisory catalog metadata (doc / version /
  homepage / authors) and its capability requests.

- **`env` and `control.after`, each behind a capability.** `now-ms` coarsened
  to a second and FROZEN for one dispatch, `random-u64` from a seeded xorshift,
  `new-id` monotonic per bundle, plus `locale` / `tz-offset-min` — deliberately
  weaker than the platform, because the world imports no WASI, a real monotonic
  clock is the primitive a timing side channel is built from, and an ambient
  clock makes a dispatch unreplayable. `control.after` asks the host for a later
  message; the host owns the timer, so there is no cancel. Both gaps are
  recorded rather than hidden: the browser bridge still supplies `env`
  unconditionally rather than per grant, and `control.after` has no host
  implementation yet.

- **`dyncomp/SECURITY.md`, `dyncomp/ARCHITECTURE.md` and
  `docs/agent-runtime.md`** — what a bundle can and cannot do with the
  file/line evidence for each claim, where this sits against AG-UI, A2UI and
  MCP Apps, and six fixed tools over a declarative surface patch (rather than
  one tool per component, which a runtime-mutable catalog cannot offer).

- **A wasm guest DECLARES its state, and stops implementing what the
  declaration already says.** `tutuca:component` is `0.2.0` (manifest
  `api-version: 2`, and a manifest declaring anything else is refused rather
  than adapted — the contract is prototype-stage and breaks cleanly). A
  `component-def` now carries its fields over a flat `ty-def` table (WIT has no
  recursive types, so a compound points at its parts by index), its message
  buckets, its `@when` filters, the requests it serves and its named `init`
  fixtures. From that the host builds a real `SchemaInfo`, which is what gives
  a guest — with no guest code — structural equality, `Value::to_json`, the
  debug rendering, hot-swap migration, the inspector's form, and the generated
  per-field mutators. A guest that declares `count: s32` gets `setCount`.

- **`@component.FieldBox` and `@component.schema_mutators`.** The generated
  mutators (`setX`, `toggleX`, `pushInX`, `setInXAt`, …) used to be written
  against `TypedInstance`; they are written against three closures now — read a
  field, write one, name the instance — so the same generator serves a typed
  instance and a wasm guest whose fields live behind `get-field` /
  `with-field`. One implementation, one set of semantics.

- **`SchemaInfo::shape_fingerprint`**, for a schema that arrives at runtime and
  has no generated `<v>_schema_fingerprint` to carry. The runtime twin of
  `@statedef.fingerprint`, which hashes the same shape one step earlier.

- **`Component::view_handler_names`**, and `compile()` filling in a schema's
  `inputs` when nothing stated them. The names a view raises live in the parsed
  tree; the generator states them ahead of time, and a component whose views
  arrive at RUNTIME now recovers them instead of having an empty descriptor.

- **A drop's files reach handlers as `value`.** `@on.drop="load value"` gets a
  `List` of the dropped files (`id`, name, size, type, lastModified) on both
  backends. The `File` itself never becomes a `Value` — the backend keeps the
  last drop's files and a host reads one back by id — which is what lets a page
  take a dropped file without installing a listener of its own. The universal
  demo's page-level drop-zone JS is gone.

- **Guests reach the rest of the framework**: the `bubble` bucket (a guest
  parent hears a guest child's `emit`), `stop-propagation`, `send-at` /
  `bubble-at` over paths relative to the dispatching component, `request-opts`
  (`on-ok` / `on-error` / `on-res` / `live-path`), `@when` filters answered
  through `call-method`, and requests a BUNDLE serves — registered in its own
  scope, so its components find them before the host's.

- **A bundle's views are linted when it loads** (`Bundle::diagnostics`), with
  the findings logged by the wasm glue. A guest's views are the one part of a
  component that never went through a build step, so this is the only feedback
  its author gets.

### Fixed

- **A comment inside a view costs more than a comment should.** One before a
  template's root element makes the view a fragment; one INSIDE it sits where
  the renderer's `§…§` boundary meta is expected and ends the chain dispatch
  walks — which is how a click inside a component nested in that view stops
  reaching it. The editor had both, and its placed components were inert
  because of the second. The prose moved out of the template; the trap itself
  is still there and is worth a linter rule.

- **The editor held its placed instances twice**, and the copy went stale the
  moment one of them was used: a successor lands in the rendered tree, so the
  map beside it was one update behind and — once the superseded sweep ran — was
  holding a guest handle the host had already collected. The tree is the only
  holder now (`@ui.live_slots` reads them back out), and the bridge answers a
  handle it does not have with a warning and an empty answer instead of
  throwing mid-render.

- **An `@if` branch that does not parse says so.** `@then="btn btn-primary"` is
  a class list that forgot its quotes; it used to leave the branch unset, which
  is indistinguishable from not writing one, so the element rendered with no
  class and nothing reported why — least visible of all next to a static
  `class`, which then appears to work. It is a `BadValue` now, and `gen-views`
  fails on it. An unset branch stays legal and silent.

- **`<input class="a" />` is not a duplicate attribute.** The vendored
  tokenizer finishes the last attribute a second time when a solidus follows
  whitespace and reports its name as a duplicate of itself, so every
  self-closing element with attributes carried a bogus
  `HTML_DUPLICATE_ATTRIBUTE` warning. Found by running the linter over a wasm
  guest's views, which is where the warning had nowhere to be seen.

- **The universal demo's picker showed its chrome over the component it had
  already selected**, when that component's own `seq-entries` were empty (a
  fresh counter, whose history is). `truthy?` is the SIZED predicate; asking
  whether something has been picked is `null?`. Its layout buttons were also
  unclickable with a real mouse: `.btn:active` sets `translate`, which
  overrode `.indicator-item`'s and moved the button out from under the cursor
  between mousedown and mouseup.

### Removed

- **From the guest contract: `instance.eq`, `instance.to-json`, the
  `dom-event` record and `handle-event`'s event parameter, and the manifest's
  four handler-name lists.** Equality and the JSON projection are the declared
  schema's; a handler's arguments arrive evaluated (`event` / `target` / `ctx`
  are not handler arguments in tutuca); the names a view raises are read off
  the compiled views. What a guest still declares is `handlers` — the input
  names it answers ITSELF, the rest being mutators the host applies.

- **The storybook's "Dynamic" pane and `dyncomp/host/wasm`'s `shell_module`**,
  a second loading UX maintained beside the universal demo's. The demo gained
  what the pane demonstrated: loading a bundle by URL, and hot-swapping a
  loaded module with the mounted components migrating into it. `cmd/dev --
  storybook-bundle` goes with it.

- Test-only and internal `@render` exports: `ViewMap`, `ViewRegistry`,
  `CompiledView`, `CacheEntry`, `render_view`, and the non-lifecycle
  `RenderCache` methods (`get`, `set`, `stats`, `size`, `evict`). Production
  integrations keep `render_root`, the resolver/boundary traits, and
  `RenderCache::new` / `clear` / `next_generation`.

### Changed

- **The Rust guest is a tabbed notepad** (`guests/rust-notepad`, was
  `rust-counter`). A counter never has to answer the questions the newer halves
  of the contract exist for; notes do — which tab you were looking at is state
  the declared fields do not name, and losing what you typed is a thing a
  person notices. It persists as a length-prefixed byte string of its own,
  which is a better demonstration of "the host never reads these" than JSON
  would be.

- **The universal demo keeps your session.** The layout, the bundles (by URL —
  a dropped file is not something a page can fetch again) and every placed
  component go into `localStorage` on each settled cascade and come back on the
  next visit. A hot swap now carries placed instances across through the same
  snapshot, so reloading a bundle over a running one is a save and a load with
  no store in between.

- **`register_bundle` refuses with the reason in it.** It raises one error type
  now, so a page that turns a bundle away shows "this host takes no CSS from a
  bundle" instead of the generic "bad manifest or view" every failure used to
  collapse into.

- **The catalog of loaded components is kept by the wasm glue**
  (`@dhw.registry()`): registered on load, replaced in place on a hot swap so a
  module keeps its position in the palette, and forgotten on drop. That is the
  code that already knows about all three, and a second copy elsewhere would be
  a second thing to keep in sync.

- Render's package-only tests are white-box tests now, so their source-view
  resolvers and cache probes no longer inflate the published API. The render
  cache also stops maintaining hit/miss counters on every lookup; tests prove
  reuse and eviction directly through VDOM identity and cache generations.

- **Superseded guest handles are collected on the transactor's drained
  cascade** (`@dyncomp.install_gc`), after the App's re-render, rather than at
  the start of the next guest dispatch. The explicit settling work landed the
  hook this always wanted.

- **The universal demo is the one page that hosts runtime-loaded bundles**, and
  it is written the way the framework asks for now: a `component` slot instead
  of `any`, declared `receive` / `bubble` / `response` variants instead of
  string-matched dispatches, and typed messages raised through the generated
  `bubble` helper.

### Security

- **A bundle is `Policy::untrusted()` by default**, enforced before the manifest
  is parsed: no capabilities, no stylesheet of its own, quotas on manifest size.
  An ungranted capability refuses the BUNDLE rather than degrading it — a guest
  reading a frozen zero from an ungranted clock cannot tell that from midnight.
  The tiers differ in convenience, not authority: at every one a bundle can
  still declare components, ship views, hold state, handle events, nest children
  and serve its own requests. `allow_custom_css` currently means someone vouched
  for a bundle, not that anything checked it.

- **`@dangerouslysetinnerhtml` in a guest view is refused**, over the shadow
  parse the linter already does and before anything is registered. It cannot be
  sanitized ahead of time — the directive's value is an expression, so what it
  will hold is unknowable until render, and by then the markup is in the
  document. Guest CSS, which is scoped by concatenation and would escape through
  a `}`, is held instead as a contract invariant: no guest-declared field
  reaches the host's unscoped `global_style`, and the WIT says so.

## [0.9.3] - 2026-07-30

### Fixed

- **`slots~` now names a slot the schema declared as the bare `component`
  marker.** A state block can say "this field is a component slot" without saying
  *which* — most often because the name is not spellable there, kebab-case being
  unable to round-trip `DnDExample` (`d-n-d-example` comes back as
  `DNDExample`). `slots~` is then the only place the name can come from, and it
  was read and dropped: `component()` only added slots for fields the schema did
  **not** declare, so a declared-but-unnamed slot kept its empty component name,
  `lookup_component("")` found nothing, and the field stayed `Null`.

  The visible cost was the composability example's Drag-and-Drop tab rendering
  empty, in the storybook and in every demo host. That example had no test, which
  is why it went unnoticed; it has one now, asserting on the child's own markup
  after clicking the tab rather than on the slot merely being non-null.

  A slot the schema **names** is still not overridable — a caller contradicting a
  declared type would leave the inspector and structural equality disagreeing with
  the block — and that half is now pinned by a test too.

  This also restores, in a narrower and true form, the reason the `as=`-view check
  in `gen-views` is a hint rather than an error: the component filling a bare
  `component` slot is MoonBit the generator cannot see. The comments in
  `viewgen/` and `cli/gen_views.mbt` that stated the old, broader rationale are
  corrected.

- **Two stale doc comments in the library.** `Path::update`'s contract in
  `core/path_spec.mbt` still described resolving a handler "exact name, then the
  `$unknown` fallback" — that sentinel was removed in 0.9.0 and dispatch does one
  lookup. `component()`'s doc comment still described the `specs` parameter and
  `FieldSpec::comp`, both removed; it documents `slots` / `slot_args` now.

- **`testing.md` overpromised the harness's selectors.** They are ONE compound
  selector — a tag plus `#id` / `.class` / `[attr]` qualifiers — with no
  descendant combinator, so `.pane .row` silently matches nothing rather than
  scoping. Found while writing the composability test; the skill said
  "CSS-selector addressed".

## [0.9.2] - 2026-07-30

### Added

- **`cmd/dev -- check-skill` compiles the bundled skill's snippets**, and `ci`
  runs it. Nothing compiled `skill/tutuca/` before, and it rotted: `specs=` and
  `@component.FieldSpec::comp(...)` outlived the parameter's removal by two
  releases in five files, and the skill ships *inside* the CLI binary, so a wrong
  snippet is what an agent reads before writing any tutuca code.

  A recipe that shows both halves — a `.html` view file, then the MoonBit that
  uses it — gets the view half generated by the same js-built generator the
  playground check uses, and the pair compiled together, so a snippet is checked
  against the REAL generated surface (`counter_component`, `CounterMsg`) rather
  than a stub. The unit is a markdown **section**: snippets in one section refer
  to each other, snippets in different sections are unrelated components that
  would collide.

  Fences are load-bearing — bare ` ```moonbit ` is compiled, `moonbit fragment`
  is wrapped in a `fn` first, and `moonbit nocheck` is skipped but must carry a
  `// nocheck: <reason>` line. Most blocks are bucket-argument fragments
  (`update=(s, msg, ctx) => ...,`) that no wrapper makes compilable, which is the
  right shape for the doc and also exactly where the rot lived. So every block,
  `nocheck` included, additionally goes through an **identifier check** against
  the checked-in `.mbti` files: a `@pkg.Name` that appears in no interface file,
  or a `name=` keyword argument no tutuca API takes, fails. That second pass is
  what catches a removed parameter, and the run reports its own coverage (18 of
  67 blocks compiled) rather than implying the whole skill is compile-verified.

- **`skill/tutuca/schema.md`** — the `<script type="tutuca/state">` language in
  one place: every field spelling, the mutators each kind generates, slots,
  message buckets, declared `$`-callables, `tutuca/init` fixtures. It merges
  cli.md's WIT-subset section with core.md's field-kind table, which described
  the same thing from opposite ends with core.md holding the stale copy. It also
  covers three declarations nothing documented: a freestanding `func` (which
  cli.md listed as UNsupported — the opposite of the truth), `variant bubble` /
  `variant response`, and `resource` / `own<c>` / `borrow<c>` slots.

- **`skill/tutuca/events.md`** — handler argument names, the generated
  `<Comp>Msg` payload-type table, modifiers, and custom-element events, out of
  core.md.

- **`core.md` gained the sections its own frontmatter promised.** *The handler
  buckets* is now one canonical anchor covering all seven buckets, the
  enum-match vs string-keyed-map spellings, and `Input` dispatch precedence
  (swap → update → generated mutator) — replacing a disclaimer that was paid for
  in eight places. **`swap` is documented at all**: it was named in the SKILL.md
  description and nowhere else, a trigger that loaded the skill and dead-ended.
  Also new: teardown and observation of a mounted `App` (`root_value`,
  `render_count`, `event_names`, `transactor.observe`'s unsubscribe closure,
  `destroy`), and, in cli.md, every diagnostic `gen-views` can report — the 27
  lint codes with their three levels, `state-without-views`, `NotIterable` /
  `NotRenderable`, and the drift check.

### Fixed

- **~25 stale or invented API references in the bundled skill**, each verified
  against the checked-in `.mbti` files. The parameter `specs=` and the type
  `@component.FieldSpec` no longer exist (`slots~` / `slot_args~` replaced them);
  `Component` lost `compute_names` / `generated_names` / `has_update` in 0.7.0;
  the `"$unknown"` dispatch sentinel is gone; `DispatchStep` has two cases, not
  three; `counter_compute` / `counter_swap` are parameters of
  `counter_component(...)`, not functions; `Transactor::observe` returns an
  unsubscribe closure and its record carries five more fields;
  `ANode::collect_classes` fills a set rather than returning one; and
  `compile_margaui` takes an `ArrayView` plus `polyfills?` and **raises**.

- **Three lint codes and a suppression pragma that were never implemented.**
  `TOP_LEVEL_AT_RULE_IN_SCOPED_STYLE`, `GLOBAL_SELECTOR_IN_SCOPED_STYLE`,
  `DUPLICATE_ATTR_DEFINITION` and `/* tutuca-lint-ignore */` appear nowhere in
  `LintCode`. Each is now replaced by what actually happens, which is worse and
  worth knowing: nothing checks these, and the browser or the renderer drops the
  offending thing in silence.

- **`event`, `target` and `ctx` are not handler arguments.** A DOM object is not
  a `Value`, so each resolves to `Null` (`render/dom_event.mbt:55`) — the
  handler silently receives nothing. They were listed as built-ins, given a row
  in the `Msg` payload table, and testing.md's "bad example" was premised on
  digging through an event `Map` that never arrives. Relatedly: modifiers are
  guards on `keydown` and `click` only, not "all events", and the JS framework's
  `+prevent` / `+stop` have no counterpart here — they are ignored rather than
  refused, so a ported `@on.submit+prevent` silently loses its `preventDefault`.

- **`slots~` cannot rename a slot the schema already declares.** Verified
  empirically, not read: with `dnd: component` in the schema,
  `slots={ "dnd": "DnDExample" }` leaves the slot `Null`, because the schema
  field wins and a bare `component` carries no name to look up
  (`component/component.mbt:178`). The skill said the opposite in three places,
  and used it to justify a `gen-views` hint. Documented accurately; the
  underlying gap is not fixed here.

- **Two recipes that could not be run and one that could not compile.**
  `share-state-across-the-tree.md` and `edit-through-a-dynamic-target.md` showed
  machine-mangled MoonBit with `raw_view=...` placeholders and a
  `// ... — from the view file` comment standing in for the markup; both are now
  `.html` + `.mbt` pairs verified through `gen-views`, as are
  `render-a-child-component.md`, `tabbed-interface.md` and `paginate-a-list.md`
  (which showed the pre-schema `priv struct` + stray `init=` form). And
  `patterns/todo-list.md` had a genuine syntax error — a multi-line lambda
  without braces, plus a trailing comma after a match arm — found by the new
  check on its first run.

- **A bad `provide` expression is dropped silently** (`component/component.mbt:369`),
  not reported as a lint error; advanced.md said the latter. If a dynamic binding
  reads as its fallback everywhere, the producer's expression is the thing to
  suspect.

### Changed

- **The skill's own vocabulary stopped contradicting itself.** cli.md said "there
  is no run-time linter and no lint-code table" while six other files said "the
  linter flags…" — and `gen-views` does run the rules, printing
  `CODE (level) Comp/view: message` (`cli/gen_views.mbt:59-67`). What does not
  exist is a `tutuca lint` command to invoke them with, which is now what every
  one of those places says.

- **`SKILL.md`'s frontmatter names the artifact the skill is actually about.**
  It described "`#|` raw-string HTML views" — the older spelling — while the rest
  of the skill treats the `.html` view file plus `gen-views` as canonical, so a
  prompt about a `.html` view, a `<template>`, a `<script type="tutuca/state">`,
  `tutuca watch`, `moon check`, a storybook example or the playground had nothing
  to match. Routing gained rows for schema.md and events.md.

- **Adding a storybook example has three metadata steps, all silent if skipped**
  (`patterns/add-an-example.md`): registering the module, mapping its name to a
  sidebar section (unlisted names land in "Other"), and giving it a title and
  description (unlisted, the title falls back to the raw registry name). None of
  this was written down anywhere.

- `core.md` is about the same length (1068 lines): ~170 lines of reference tables
  moved out to schema.md and events.md, and a comparable amount of new coverage
  moved in.

## [0.9.1] - 2026-07-29

### Fixed

- **`value`'s inferred payload type follows the host element.** The generated
  `<Comp>Msg` case for a `value` handler arg on `<input type="checkbox">` now
  carries `Bool` (the checked state the glue delivers) and on
  `<input type="file">` the metadata `@tutuca.Value` — previously both
  inferred `String`, so those dispatches could only ever land in `Unknown`.
  Only a static `type` attribute participates: a dynamic `:type` keeps the
  `String` default, and call sites that disagree still join to
  `@tutuca.Value`.

### Changed

- **The bundled skill is self-contained.** No more pointers at repo files
  (`storybook/examples/*.mbt`, the margaui repo's skill) — worked examples are
  inlined, since the skill ships in the CLI binary and the reader may have
  nothing else. New content driven by coding-agent feedback: the two bucket
  spellings are labeled everywhere (enum-match for generated wrappers vs
  string-keyed maps for raw `component()` calls) with examples leading with
  the enum form, core.md gained a generated-`Msg` payload-type table and the
  closed/view-driven bucket-enum rule, cli.md a `values` / `list<any>` worked
  example, margaui.md an inline starter class vocabulary, plus two new files:
  a complete todo-list pattern (`patterns/todo-list.md`) and a playground
  authoring guide (`playground.md`).

## [0.9.0] - 2026-07-29

### Added

- **The playground is packaged for npm.** `cmd/dev -- npm-pack` stages and packs
  two packages out of an assembled `dist/`:
  `@marianoguerra/tutuca-playground` (the shell — `<mb-playground>`, worker,
  editor, view generator, margaui; ~0.5 MB) and
  `@marianoguerra/tutuca-playground-payload` (`manifest.json` + `fs/`, the
  `.mi`/`.core` bundles user code compiles against; ~8.6 MB). Manifests and
  READMEs live in `playground/npm/`; both take their version from `moon.mod`.

  Two packages because they turn over for different reasons — the payload is
  rebuilt whenever the MoonBit toolchain moves, the shell is not — and they
  unpack into the same `playground/` + `site/` layout, so a consumer copying
  both into a static directory gets the arrangement everything resolves against
  by default. The in-browser compiler is not packed: it is upstream's
  `@moonbit/moonc-worker` build, published with no license field, so the payload
  names the exact version in `peerDependencies` and the playground is pointed at
  the consumer's own copy. `npm-pack` refuses a `dist/` assembled under a
  different toolchain than `playground/build/toolchain.json` pins, and packs
  only — publishing stays a deliberate manual step (see CONTRIBUTING.md).

- **`<mb-playground target="js">`** pins one element's backend, the way
  `?target=` does for the standalone playground, so a page about one backend can
  say so in the markup. Ignored when the payload has no such target.

### Changed

- **The playground shell stopped assuming it is the site.** Every URL it fetches
  — the worker, `moonc-web.cjs`, `manifest.json`, `fs/` — used to be written
  relative to the page (`./playground/compiler.worker.js`) or resolved by the
  worker against its own location. Both are now resolved once, absolutely, from
  the calling module's `import.meta.url` and handed to the worker in the init
  message (`playgroundConfig` + `makeCompiler` in `playground/web/runtime.js`),
  so the worker resolves nothing itself.

  That buys three things the old layout could not do. The folders relocate — a
  package directory, a subfolder, a CDN — with nothing to configure. A host can
  split them apart with `globalThis.MB_PLAYGROUND = { payloadBase, compilerUrl,
  workerUrl }`, which is what lets them serve their own installed
  `@moonbit/moonc-worker` instead of a copy of the 5.5 MB blob. And a worker on
  another origin now works at all: a `Worker` script must be same-origin, so a
  cross-origin one gets a same-origin blob shim that `importScripts` it — which
  is only safe because the worker no longer resolves anything against the blob's
  base URL, which points at nothing.

  A host-supplied compiler is checked against the payload it was built for:
  `manifest.json` carries `mooncWorker` (plus `mooncBuild` and `moon`, so the
  pin travels with the bundles), and the worker compares it against the
  `package.json` npm ships beside `moonc-web.cjs` when one is there. The payload
  and the compiler are one pair; a mismatch used to surface as `[E4018] … no
  impl is defined` against perfectly good user code, and now says so before
  fetching 5.5 MB. Versions are compared as semver identities, not strings —
  npm publishes the compiler with build metadata the registry and the pin both
  leave off (`0.1.202607282+5e7afb0c0`), and when it is there the build must
  match `manifest.mooncBuild` too. Either shell also stops labelling a failed
  compiler load "wasm instantiate failed", which hid exactly that message.

- **The standalone playground opens on wasm-gc, and `?target=` pins a backend.**
  A linked wasm-gc module is ~0.26 MB where the js one is ~1.1 MB of
  JavaScript, and it is what the landing page's embeds already run. `?target=js`
  or `?target=wasm-gc` wins over the default, so a link can pin the backend it
  is about; the toggle keeps the query parameter in step, so the URL in the
  address bar always reproduces what is on screen. A payload without wasm-gc
  (`JS_ONLY=1`) still opens on js, and — since the default now needs
  JS-String-Builtins — a mount that throws drops the page to js once and says
  why, the same fallback the embeds make.

- **The playground toolbar got a once-over.** One height and one shape for every
  control (the UA widgets agreed on neither, which is what made the row look
  ragged), a primary Run button, uppercase labels on both selects, and a status
  chip with a state-coloured dot at the far end. The chrome's colours moved into
  CSS custom properties, so dark mode is a token swap rather than a second copy
  of every rule that draws a line.

- **The landing page's embedded playgrounds compile to wasm-gc.** A linked
  wasm-gc module is ~0.26 MB where the js one is ~1.1 MB of JavaScript, which is
  the better trade on a page that mounts ten of them. Each embed falls back to
  js on its own if the payload carries no wasm-gc (a `JS_ONLY=1` build) or if
  the mount throws — what an engine without JS-String-Builtins looks like — so
  the toggle is still there and the page still works where wasm-gc doesn't. The
  standalone playground still opens on js.

  Two things had to work first. `mountWasm` did not compile the app's margaui
  classes, so a class-styled example would have rendered unstyled; it now reads
  them back through the exported `classes_json`, and the injected CSS is
  byte-identical to what the js mount produces. And the compiler worker — ONE
  worker for the whole page — held a single payload, so whichever `init()` ran
  last decided what every element compiled against. It keeps a payload per
  target now and picks one per compile from the request. That bug was reachable
  before this change too: toggling any single playground's target and back
  handed a wasm binary to the js mount (`Invalid or unexpected token`) or JS
  text to `WebAssembly.instantiate` (`expected magic word 00 61 73 6d`).

### Fixed

- **The playground's wasm-gc target runs.** It has compiled and linked user
  code for a while, but the linked module never validated: on wasm-gc a MoonBit
  `String` lowers either as a JS-String-Builtins `externref` or as MoonBit's
  native `(ref 1)` char array, the choice is made at link time for every core in
  the set at once, and the baked cores are built for the js-string ABI. Linking
  without asking for it mixed the two, and the browser rejected the bytes with
  `array.new_fixed[0] expected type externref, found local.get of type (ref 1)`.

  `linkCore` had no knob for this when the blocker was first written up; the
  pin moved to `@moonbit/moonc-worker@0.1.202607282`, which exposes one. The
  worker now passes `useJsBuiltinString: true` and `importedStringConstants:
  "_"` for wasm-gc, matching what `runtime.js` already instantiated with. The
  module's imports come out as `jscore`/`tdom`/`console` — the same surface the
  shipped `demo/counter_wasm` links to through the native `moonc`.

  That left a second fault of its own: the module instantiated, `mount()` ran,
  and nothing appeared. The wasm host reads the DOM as
  `@core.global_this()._get("document")`, and the `jscore` import handed back
  the shell page's `globalThis`, so the app looked for `#app` outside the
  preview iframe and logged that it was missing. `jsCoreImports` now takes the
  realm to answer with and `mountWasm` passes the iframe's window.

  All four picker examples now compile, render, route events through the
  exported `on_event`, and report state and activity through the exported
  getters on wasm-gc. `WASM_TARGET_STATUS.md` stops being a blocker report and
  describes the two couplings that keep the backend working.

## [0.8.1] - 2026-07-29

### Fixed

- **Every compiler warning is gone, on all three targets.** `moon check`
  reported 11 and `cmd/dev -- check` — which opts into
  `--warn-list +unnecessary_annotation` — reported 362 more.

  The 11: `to_repr(x)` as a *free* function is deprecated in favour of
  `Repr(x)` (the `impl Debug with fn to_repr` definitions are untouched — only
  the free form moved); `storybook/ui` reached `@string.parse_int` without
  importing `moonbitlang/core/string`; and three structs in the js smoke test
  still derived `ToJson`/`FromJson`, unread since the state codec replaced the
  Json bridge.

  The 362 were all `unnecessary_annotation` — `T::{ … }` where the position
  already has a type. 294 were in generated modules, so they are fixed in the
  **emitters** and the modules regenerated, never hand-edited: `<T>State::zero`,
  the state and user-record decoders, an init fixture's full-record form, and
  `StateDef::zero_expr` for enums, variants and records. A zero always lands
  somewhere its type is known, and MoonBit resolves a constructor against the
  expected type — two enums in one module both declaring `low` stay
  unambiguous. `ty_info_src` already wrote its constructors bare for a related
  reason; the two now say so as a pair.

### Changed

- **A field-less generated state derives `Default` and is built through it.**
  This is the one interface change in this release, and it is a workaround, not
  a preference: MoonBit has no warning-free literal for an empty struct. A bare
  `{  }` parses as an empty `Map` and fails to type, and `<T>State::{  }` — the
  only form that compiles — is then reported as an unnecessary annotation. So
  the struct derives `Default` and `zero()`/`decode` call
  `<T>State::default()`. Empty structs in hand-written code take the same route
  spelled `Default::default()`, because a `priv` struct's derived `default` is
  not implicitly promoted.

## [0.8.0] - 2026-07-29

### Added

- **An instance carries a fingerprint and a revision (`@tutuca.ObjId`), so a
  render cache has something cheap to key on.** `0.7.0` removed all render
  memoization; `benchmarks/OPTIMIZATIONS.md` #8 recorded that the render-site
  cache paid for itself where it hit (`toggle todo 1000` +58.9% without it) and
  was a net loss where it missed, because it built a per-site string key and
  then missed with it. The fingerprint replaces that string.

  `ObjId` is a **bucket, not an identity**, and it is deliberately not unique.
  Two instances created from the same arguments get the same origin; so do the
  same component loaded twice at runtime from two different bundles. That is
  what removes the need for a process-global counter, and with it the question
  of how two independently loaded components avoid clashing — they do not have
  to, because a bucket collision costs a miss and the cache checks physical
  identity on the value it stored before returning anything.

  It rides on machinery that already existed. `TypedInstance::make` is the only
  place a host instance comes into being — creation, an `update` handler and a
  field write all land there — and it already returns the ORIGINAL instance
  when nothing changed, so "the revision moved" means "the instance really
  changed" without a second rule being written. Guest instances get the same
  treatment through `DynObj::successor`, which already threaded a struct copy.

  Fingerprinting stays cheap through one rule: a nested `Obj` contributes its
  own origin and never its contents, so a parent costs a pass over its own
  fields rather than a walk of the subtree under it. `Bundle.comps` carries the
  manifest fingerprint hashed once at registration for the same reason.

  The id is absent from `obj_field`, `obj_eq`, `obj_debug`, the schema and the
  JSON projection: a bucket is not state, and every DOM snapshot, inspector row
  and `gen-views` output is unchanged by this.

- **The component render-site cache, rebuilt on that key — updates are 27–57%
  faster.** `@render.RenderCache` keys a `Map[UInt64, _]` on the fingerprint, so
  nothing is built at lookup time, and it DECLINES for a value that has no one
  (a plain `Map` render site, a component-less `ViewMap` embedding) rather than
  keying and missing — the two things `benchmarks/OPTIMIZATIONS.md` #8 asked a
  reintroduced cache to fix. `App` holds one across passes and rolls a
  generation per render; `RenderCtx` carries it as `RenderCache?`, and `None`
  renders exactly as the uncached port did.

  A hit requires the revision, the render-site `node_id`, the resolved
  `(cid, vid)`, `physical_equal` on the stored value and on the dyn-binds
  chain. That is all a site reads: a component boundary is a bind barrier, so
  the enclosing `@each` binds cannot reach inside it, and position is never
  baked into a subtree (the dispatch path is reconstructed from the DOM at
  event time). Anything else is a miss that overwrites, so a bucket collision
  can cost time and never correctness.

  `RenderOnce` and the constant-attribute memo did NOT come back — they are the
  half that reached into the AST and made `viewgen` parse each view two ways.

  One row costs: `patch counter` is 3.0% slower, because a single component
  whose state changes on every click misses every pass and the lookup buys
  nothing. The old cache cost 9.8% there; the rest of it was `site_cache_key`
  building a string to miss with. Full numbers and the comparison against #8's
  table are entry #9.

## [0.7.0] - 2026-07-29

### Added

- **`gen-views` takes `[path…]`, and the checks that need two components come
  with it.** Paths are `.html` files or directories, following `watch`'s rule
  (a directory contributes the files that already have a generated sibling), so
  `tutuca gen-views src/` compiles a project in one invocation. Every file is
  split before any is emitted, which is what makes a reference to a component
  declared in ANOTHER file checkable:

  - **`<x render=".slot" as="edit">` where the child has no `edit` view.** At
    run time `resolve_view` returns None and the site renders *nothing* — the
    same silent blank that `.field` had before the schema could answer it.
    Reported as a hint rather than a failure, because `component()`'s `slots~`
    can point a declared slot at a different component than the schema names
    and the generator cannot see that.
  - **`.field` and `@value.member` inside a loop over child components.**
    `list<todo>` names the Todo component, so the body is checked against
    *that* schema instead of going opaque. A misspelt field is a build error
    naming the near miss, where before it was not even looked at.

  A component outside the paths passed is unknown, and unknown is not wrong —
  so a single-file invocation still works and simply checks less. `--name` and
  an `--out` ending in `.mbt` each name one thing, so both are refused for a
  batch. `agent-context`'s `schemaVersion` is 6.

- **A container in `@show` / `@hide` fails generation.** `Value::is_truthy`
  answers `true` for List, Map and Obj unconditionally, so `@show=".alts"`
  shows the element for an empty list too: it reads as a guard and is not one.
  The message names `empty? .alts` as the fix. `StateTy::is_boolish` existed,
  was tested, and was called by nothing; it now says what its own comment
  always said — a string, a number and an option are left alone, because
  `@show=".role"` beside `@text=".role"` is the idiomatic way to hide an empty
  badge.

- **A constant `id` inside an `@each` fails generation.** The loop stamps the
  body once per item, so the id is not unique the moment the sequence holds
  two. Only the compiled tree knows the element repeats, which is why no HTML
  linter reading the source can catch it.

### Performance

- **Constant attributes are evaluated once, not once per element per render.**
  `eval_attrs` rebuilt a `Map[String, AttrValue]` for every `ConstAttrs`
  element on every pass and `@vdom.h` copied it into a second map — two
  allocations per element per pass for attributes that cannot change. They are
  memoized now on a per-element key minted at load time (the same contract a
  `RenderOnce` id has), and `h` adopts an attribute map rather than copying it
  when there is nothing to strip out of it. The point is not the allocations:
  handing the differ the SAME map is what lets `diff_props` short-circuit on
  `physical_equal` instead of hashing every key in both directions, which
  `benchmarks/OPTIMIZATIONS.md` ranked first under "Not yet tried".

  `RenderOnce` does not already cover these — it needs the whole subtree
  constant, so `<div class="row"><x text=".name"></x></div>` misses it, and
  that is the shape of every list row. Native, release, against a saved
  baseline: `patch counter` −17.1%, `add+remove todo 10/100/1000`
  −17.6/−15.4/−14.6%, `toggle todo 10/100/1000` −10.9/−11.4/−5.6%,
  `switch view` −13.4%, `page people 1000` −11.9%, `refilter people 100`
  −11.9%.

### Removed (BREAKING)

- **All render caching.** Rendering memoized three ways and now memoizes
  nothing: the component render-site cache keyed on value identity
  (`@render.RenderCache`), the `RenderOnce` constant-subtree memo, and the
  constant-attribute memo added earlier in this same Unreleased section. Every
  pass rebuilds every subtree and every attribute map from the value tree, and
  `@vdom`'s differ is what keeps the DOM writes proportional to the change.

  This is deliberate and it costs time — `patch toggle todo 1000` +110%,
  `patch move json 8x4` +150%, `patch counter` +23% (wasm-gc; the full table
  and the per-cache attribution are entry #8 in `benchmarks/OPTIMIZATIONS.md`).
  The caches reached into the AST, the view pipeline and the render context,
  which is more structure than is worth holding still while the core design is
  moving. They are meant to come back, keyed on whatever it settles on.

  Removed from the public API:

  - `@render.RenderCache` and all its methods (`new`, `get`, `set`,
    `next_generation`, `stats`, `size`, `evict`, `clear`).
  - `@render.RenderCtx`'s `render_once`, `render_cache` and `const_attrs`
    fields, and the matching `RenderCtx::new` parameters — it is now
    `RenderCtx::new(view_resolver?)`.
  - `@anode.optimize_node`, the `ANode::RenderOnce` variant and
    `@anode.RenderOnceData`, `DomData::attrs_id`, and
    `ParseContext::new`'s `cache_const_nodes` parameter.

  A `match` over `@anode.ANode` that had a `RenderOnce` arm must drop it; one
  that was exhaustive without it is unaffected. `@anode.Attrs`'s
  `ConstAttrs`/`DynAttrs` split is NOT affected — that is a representation
  choice about re-evaluating `Val` expressions, independent of the memo.

  What did **not** change: the no-op-update short-circuit and everything that
  feeds it (`TypedInstance`'s memoized `Obj(self)`, `REUSE_FUEL`/`reuse_equal`,
  `with_field`/`with_item` returning the untouched container). That win comes
  from the transactor's root-identity check, not from any render cache —
  `patch noop todo 1000` is in fact 8.3% *faster* now.

## [0.6.0] - 2026-07-27

### Added

- **Every storybook story gets a live Instance tab.** Story | Instance beside
  each pane; the Instance pane renders the inspector's explorer over that
  story's own instance, with the Component tab beside its fields. It stays live
  because `i<N>` is rebuilt in the same successor that writes `s<N>` — a story
  dispatch rebuilds the spine through the shell's `obj_with_field`, so the
  explorer tracks the story rather than showing the state as of the moment the
  tab was opened. Built when the tab is opened and dropped when it is closed:
  a gallery has ~50 stories and an explorer is a whole component tree.

  `Inspector::explore_value(v, comps?)` is the entry point — the registry is
  optional now that a value names its own fields.

- **A schema-driven state editor.** `@inspector.Inspector::edit_instance(v)`
  renders a form over any component instance: one row per DECLARED field, a
  control chosen from the field's kind (checkbox / number / text, with a
  collection or a child slot shown rather than edited), the WIT spelling as
  the type label, and an edit written back through the per-field mutator
  (`setTitle`, `setCount`, …) resolved by name off the instance. No part of it
  is written per component and none of it needs a downcast.

  It edits the instance it holds — a storybook knob or a fixture builder —
  rather than writing through to a mounted app, which would need the path the
  instance sits at.

- **The playground's Activity panel is the transactor's observer stream.** One
  line per handler invocation with its bucket, name, args, path and whether the
  leaf changed, newest first. It was a numbered list of state STRINGS, because
  a record could not be serialized: `before`/`after` are component instances.
  `ObserveRecord::to_json` exists now, along with `ObserveKind::label` /
  `ObserveMatch::label`, and the wasm host's `state_json` returns real JSON
  like the js one.

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

- **The storybook's Instance tab rendered blank.** The explorer was built
  correctly and had no descriptor anyone could render it with: `<x render>`
  resolves an instance through the shared registry by component id, and the
  gallery registered the shell and each story's module but never the
  inspector's own components. `Inspector::components` is public so a host that
  renders an inspector view it built itself can register them.

- **A nested instance rendered as `Object`.** Only the inspector's ROOT row
  read the name off `v.schema()`; every level below it went through
  `classify`, which matched on `obj_schema()` for the fields and dropped the
  name, so a component holding child components opened into `Object {1}`
  instead of `JsonBoolean {1}`.

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

[Unreleased]: https://github.com/marianoguerra/tutuca-moonbit/compare/v0.9.1...HEAD
[0.1.0]: https://github.com/marianoguerra/tutuca-moonbit/releases/tag/v0.1.0
