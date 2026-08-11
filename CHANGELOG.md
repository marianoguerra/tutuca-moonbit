# Changelog

All notable changes to this project are documented here. The format is based on
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and this project
adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Added

- **`dyncomp/host/wasm/abi.mjs` — the canonical ABI for `tutuca:component`,
  written once instead of shipped in every bundle.** A guest archive can now
  carry its core module and a four-field descriptor:

  ```json
  { "world": "tutuca:component@0.6.0", "encoding": "utf16",
    "core": "counter.component.core.wasm", "manifest": { "...": "..." } }
  ```

  and the host does the lifting. What it replaces is `jco transpile` output —
  5,000 to 7,500 lines per archive, and 38-57% of a gzipped one. That file
  never carried anything about the component: across fifteen bundles it takes
  eight distinct values, and which one you get is a pure function of the host
  functions the module imports and the string encoding it was embedded with.
  Everything else is the world, and the world is fixed, so `WORLD` in `abi.mjs`
  transcribes `wit/tutuca-component.wit` as type descriptors and one generic
  implementation of alignment, size, flattening, load/store and lift/lower
  walks them.

  Two things follow that are not about size:

  **An archive stops carrying executable JavaScript.** `loader.mjs` imported
  the guest's own transpiler output from a blob URL, which runs at PAGE
  AUTHORITY — the one channel the wasm sandbox says nothing about, and the
  thing `SECURITY.md` and a bundle audit both had to warn about rather than
  prevent. A descriptor archive has nothing to import.

  **A capability is checked against the import section.** Imports bind by name
  against a closed table, so anything outside `tutuca:component@0.6.0` is
  refused before a guest instruction runs — and `env` is refused unless the
  host granted the matching capability. This is the gap `SECURITY.md` §2
  admitted to: `Policy::check_capabilities` reads the manifest, a guest writes
  its own manifest, and a guest that imported `env.now-ms` without mentioning
  `cap-clock` got the clock anyway. It cannot any more. `setGrants()` is the
  page's side of that decision; its default is `Policy::untrusted()`'s answer,
  which is nothing.

  The two trampoline core modules are not needed either. They exist because the
  transpiler captures `memory` at instantiation time and has to break the
  resulting cycle; every import here reads memory at CALL time, so the main
  module is the only one instantiated — and the only one an archive must ship.

  `loader.mjs` takes whichever shape arrived. An archive without a descriptor
  still loads its transpiler output, and now says out loud that it is doing so.

- **`tutuca:component@0.6.0` separates declaration from execution.** The WIT
  no longer exports the catalog/schema/view graph through `get-manifest`; it is
  static `manifest.json` plus HTML files. Input handler names are no longer
  duplicated there either: `handle-event` returns `unhandled`, `unchanged`, or
  `changed(instance)`, so the host can fall back to a generated field mutator
  without guessing. `seq-entries` is gone; iterable state is an ordinary
  declared list field. The guest SDK consequently asks authors only for
  behavior, factories, persistence, and optional request serving.

  Checked three ways against a fifteen-bundle corpus, not asserted: every bundle
  driven through both implementations with the same host agrees on 379 guest
  answers and 372 host calls; 337 computed layouts match the core signatures
  wit-component wrote into the shipped modules; and the two codecs — one over
  linear memory, one over flat core values — round-trip 18 types identically in
  both encodings. The Rust guest is the one that matters: utf8, hand-written
  bindings, and the host cannot tell.

- **`@setinnermd` — markdown in a view, sanitized by construction.** Takes a
  markdown SOURCE string and replaces the element's children with the nodes it
  parses to: CommonMark plus GFM (tables, task lists, strikethrough, footnotes),
  with no flag to turn any of it on.

  It is `@dangerouslysetinnerhtml`'s safe sibling, and the name carries no
  warning because it does not need one. The markdown never becomes an HTML
  string: `vdom/filter/markdown` walks the AST straight into vdom nodes, asking
  the app's own `@sanitize.Sanitizer` for a verdict on **every element** and
  running **every attribute value** past `@filter.attr_value_allowed` on the
  way — routed through one `emit` helper so no arm of the walk can skip it.
  `set_inner_html` is never called, so the browser never re-parses a string this
  code produced and there is no second parse for a mutation-XSS to live in.
  Raw HTML inside the document goes through the same `html_nodes` builder
  `@dangerouslysetinnerhtml` uses, so a `<script>` cannot be refused by one path
  and allowed by the other.

  **There is nothing to permit, so Pass 1 never refuses it.** `raw_markup` is a
  permission because a raw-HTML payload arrives as markup the config gets no say
  over; markdown has no such route. A host that wants less names the elements it
  will have, the same lever it already has over every other node in the tree.

  It works with no configuration: `App::new` now installs
  `@mdfilter.default_filter()` — `MdFilter` in front of the `@filter.Baseline`
  it installed before. **The cost is that every app links the vendored parser**
  (~4.7k lines), since the call is unconditional and nothing about it is dead.
  `set_filter(Some(@filter.Baseline::new()))` restores the previous footprint;
  `set_filter(None)` is still the full opt-out.

  Without a filter that understands it, `set_prop` **fails closed** — the
  element is cleared rather than being given the markdown as text or as markup.
  A directive whose name promises it is sanitized has to fail visibly when
  nothing sanitized it.

  A live editor is on the landing site: source on the left, preview on the
  right, and a second half of the document that is nothing but attacks — HTML
  and SVG `<script>` (different elements, since identity is namespace-qualified),
  `<iframe>`, `<base>`, `on*` handlers, `javascript:` and `data:text/html` URLs.
  None of it renders. See `docs/sanitizer.md` for the design.

- **`markdown/` — the parser, vendored from mizchi/markdown.mbt** (MIT, commit
  pinned in `markdown/UPSTREAM.md`). 15 of upstream's 29 production files,
  verbatim: the AST, scanner, block parser and inline parser. Its HTML renderer,
  markdown serializer, editor-preview renderer and incremental reparser are
  deliberately left behind — building nodes means never needing an HTML string.

  Vendored rather than depended on because the published `mizchi/markdown` drags
  `mizchi/moomaid` and declares `supported-targets: js+wasm`, while this module
  prefers wasm-gc. What is copied has no third-party dependency and no `extern`
  at all.

  Two findings from reading that parser shaped the design, and
  `markdown/parse_test.mbt` pins both so a re-sync cannot move them quietly:
  `Inline::HtmlInline` is only ever a complete HTML comment (so every raw-HTML
  carrier is self-contained and no half-open tag needs reassembling across
  siblings — which is what removed the AST→string step from the original plan);
  and `try_parse_autolink` accepts any `<…>` without whitespace, so `<span>`
  arrives as `Autolink(url="span")`. The builder renders an autolink as a link
  only when the URL has a real scheme, and as literal text otherwise —
  without that, an ordinary comment body would fill with stray relative links.

### Changed

- **`filter_for` moved to `vdom/filter/markdown`.** The chain is now
  `[MarkupFilter?] → MdFilter → Baseline`, and `markup` cannot name it: the
  dependency runs `markdown` → `markup`, and a cycle is not available.
  `@markup.filter_for` is deprecated and still does what it always did — the
  right answer for a host that wants the raw-markup rule and nothing else.
- **`@markup.html_nodes` is public**, extracted from `MarkupFilter`'s private
  builder. One HTML-tree→sanitized-vdom builder shared by both directives,
  rather than two that could drift apart.
- `@vdom.AttrValue` gained `Md(String)`, and `@anode.AttrItem` gained
  `RawMarkdown`. Both are exhaustively matched, so a downstream `match` on
  either will need the new arm.

- **`examples/` — consumers of the published package, inside the repository.**
  Each is its own module depending on `marianoguerra/tutuca` from mooncakes
  with no path dependency and no `../`. Nothing else here can catch what they
  catch: `moon check` never leaves the module, so it cannot tell whether the
  two wasm-gc JS loaders survived `moon publish`, whether the relative import
  between them is repointable once they land beside a page, or whether `tutuca
  new-guest` emits a tree that builds. Excluded from publish; each has its own
  `build.mjs` and needs nothing from this repo. Run them after a release.

  The first is `examples/dyncomp-dice`: the universal dynamic-component host
  plus one guest of its own — a die, which asks the page for its number because
  a `tutuca:component` world imports no entropy. It found the jco breakage
  below on its first run.

- **`dyncomp/` ships.** It was excluded from the published package, so
  `moon add marianoguerra/tutuca` delivered the framework and the CLI and
  nothing of the dynamic-component story: no contract, no host, no policy, no
  catalog, no universal UI, and no way to write a guest. All nine packages are
  in the tarball now, with `dyncomp/wit/tutuca-component.wit` and the three
  design documents beside them. It imports nothing that was not already
  published, and `docs/`, which always shipped, has always linked into it —
  those links worked in the repository and not in the tarball. This is a MINOR
  bump: additive, with no existing package changed.

  The one part still excluded is `dyncomp/test`, whose `*.test.mjs` drive real
  guest bundles out of `guests/*/dist/js` — a path that exists in the repo and
  in no tarball.

- **`tutuca new-guest <name>`** — scaffold a `tutuca:component` guest. The
  whole tree is compiled into the binary: the WIT contract, the checked-in
  wit-bindgen bindings, the SDK, a working component to edit, and the
  build/pack scripts. Needs `moon`, `wasm-tools` and `node` — **not**
  `wit-bindgen`, since the bindings ship generated and the WIT is a contract to
  implement rather than a source to regenerate against.

  It is a scaffolder rather than a package to depend on, and that is forced
  rather than chosen: `sdk.mbt` implements the `declare`s in the generated
  `top.mbt` and defines methods on `Instance`, which `top.mbt` declares, and
  MoonBit puts both in the package that declares them. No import edge can carry
  them. `agent-context`'s `schemaVersion` is now 7, with three new error codes.

- **`dyncomp/ui/wasm`** — the universal UI as a mountable host. `dyncomp/ui` is
  backend-agnostic on purpose, and says in its own header what it therefore
  cannot do: fetch an archive, read a dropped file, reach localStorage. That
  half was 535 lines inside `demo/universal_wasm`, where nothing published
  could reach it. It is now a package, and the demo is the ~90-line executable
  around it: which bundles to offer, whether to remember a session, one service
  to lend, and the export list. A host is `@uiw.mount(session~, samples~,
  requests~)`.

  Two shapes changed on the way out. The mutable page state — the store, the
  in-flight count, the loaded URLs, the app and the UI — is a `UniversalHost`
  rather than five module-level refs. And the bar's sample buttons are DATA: a
  `list<sample>` the host passes in, rather than six URLs hardcoded in a view,
  since a published component cannot know any bundle's name. Persistence is one
  `Session?` rather than a boolean threaded through four functions, because it
  has to be gated at both ends: a page that restores but does not save, or the
  reverse, writes an empty tree over the thing it exists to keep.

- **[`docs/dynamic-components.md`](docs/dynamic-components.md)** — hosting a
  bundle and writing one, in the published docs, which is where someone who has
  only the package can find it.

### Changed

- **The playground gives its space to the preview.** The state and activity
  panels used to sit UNDER the preview, so the running component — the thing
  the page exists to show — got about half of half the window, and the other
  half was a code editor whether or not anyone was reading it. Three changes,
  one goal:

  - **State and Activity are a fourth tab of the LEFT pane**, beside Component,
    View and Generated. Putting them there rather than over the preview is what
    lets both be read at once: the inspector is next to the component it
    describes, not covering it. The tab carries a dot when state changes while
    another tab is showing.
  - **The code pane collapses** — the ⟨ button in its tab strip, the `Code`
    rail it leaves behind, or Ctrl/⌘+B — and the preview takes the whole
    window. A compile error re-opens it, because the diagnostics panel lives
    there and a red status line is not a message.
  - **The divider drags.** Width and collapsed state persist in
    `localStorage`, so the layout someone settles on survives a reload.

- **The wasm-gc JS import shims moved out of `demo/`.** `app/wasm` and
  `vdom/wasm` were shipping with their JS import contract living only in an
  excluded directory, so a consumer could build a wasm-gc page and have nothing
  to instantiate it with. `demo/wasm-loader-lib.mjs` is now two files, split
  along the seam it already had:

  - `app/wasm/loader.mjs` — `jscore`, `tdom` and `instantiate`; every wasm-gc
    tutuca page needs it
  - `dyncomp/host/wasm/loader.mjs` — `tcomp` and `tkv` plus the bundle
    unpacker, linked through `instantiate`'s `makeExtra` hook

  A page that never loads a bundle now carries none of the second, which the
  counter and storybook demos did before. **Breaking for anyone who copied
  `demo/wasm-loader-lib.mjs`**: import the two published files instead. In
  `dist/` they land beside each page as `app-loader.mjs` and
  `dyncomp-loader.mjs`.

- **One guest SDK, not five.** `sdk.mbt` was copy-pasted into all five MoonBit
  guest trees, byte-identical but for two comment lines — five copies of the
  guest contract are five chances to disagree. The canonical file is
  `guests/sdk.mbt`, and `gen-bindings.mjs` copies it into each guest, so the
  existing `git diff --exit-code -- guests` drift check now covers it too.

- **`ci` gained `check-guest-template`**, which scaffolds a guest with the
  embedded template and compiles it with `--deny-warn`. Nothing else covers
  that tree: CI never builds a guest, and the template is assembled from three
  sources with placeholders substituted at write time, so all three can be fine
  and the result still not compile. It caught one immediately — a guest named
  `*-test` produces `*_test.mbt`, which MoonBit reads as a test file, so the
  author's `dyn_module` lands in test scope and the bundle declares nothing.
  That was a *warning*, not an error. `new-guest` now rejects the name.

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

- **The whole viewport is the app, and the app is a component tree:
  `dyncomp/ui` + `dyncomp/ui/std`.** The root holds ONE component and it starts
  as a `Universal` — an empty cell with a `+` in it — so the first thing a
  person does is choose what the page is, and everything after that is the same
  gesture one level in. Clicking a `+` opens a command bar over the page,
  searching a catalog that holds the standard components and everything any
  loaded bundle declares; ctrl/cmd opens the generated form instead, which also
  opens by itself when a component has a required argument nothing has answered.
  Dropping the bar's `config` pill on a cell — or clicking its badge — opens a
  sidebar: a component that declares a `config` view of its own gets it rendered
  live, and everything else gets the same generated form, pre-filled from what
  the instance already holds. Containers grow hover-only insert buttons: before
  each child and after the last on a `Stack`, one per edge on a `Grid`.

  **`Universal` is a HOLDER, not a placeholder that gets replaced**, and that
  one decision is what the rest rests on. Everything a person places sits inside
  one, so the editing chrome has a single host-owned home that nothing has to
  opt into — a guest component is decorated exactly like a standard one, because
  neither is asked to participate. Every container's children are universals, so
  "insert a cell" needs no kind and no binding. And emptying a cell gives the
  `+` back instead of deleting it.

  Edit mode is a VIEW rather than a field: the app pushes `edit` with
  `@push-view`, every component that declares one shows its affordances, and one
  that does not — every guest — is simply itself in both. A boolean threaded
  through the tree would be the same fact stored once per node, and a guest,
  which cannot grow the field, could never join in.

  The standard set is `Universal`, `Stack`, `Grid` (uniform m×n), `Tabs` /
  `TabPage`, `Text` and `Textarea` — ordinary tutuca components in a package
  that knows nothing about bundles, so `moon test` drives all of it on the
  in-memory DOM. Only `Universal` has to exist; the rest are convenience, and a
  bundle shipping a better stack would be no different in kind. `guests/rust-notepad`
  reproduced by composition — tabs, a tab holding a universal, pick a textarea —
  is a test rather than a claim.

- **A component from anywhere is in the same catalog as the host's own.**
  `Registry` holds `builtins` beside its loaded modules, and `dyncomp/ui/builtins.mbt`
  builds each one's `Descriptor` from the component's own declared schema, so
  nothing can describe a standard component differently from how it behaves. The
  same search ranks them, the same projection generates their form, the same
  validator refuses their bad arguments with the same JSON Pointers. The ONE
  place they differ is construction: one is compiled in, the other arrived in an
  archive.

- **A guest can offer a hole for a person to fill.** A component declaring a
  field whose type names a component from ANOTHER module (`resource universal;
  body: universal`) gets it built and answered by the HOST, and never sees it —
  `DynObj` holds it, `obj_field` answers it without crossing the bridge, and a
  successor carries it. No contract change: `ty-comp` already carried the name.
  It has to work this way round because the boundary allows nothing else — a WIT
  `value` has no case that can carry a host component. A same-bundle `ty-comp`
  is left alone, because that is the guest's own nested child.

- **REMOVED: `dyncomp/surface`.** The layout document and its six-op patch
  algebra were built, shipped in this same unreleased cycle, and are gone. The
  component tree is the layout now, and what replaced the algebra is the runtime
  `core/` already had: a `+` bubbles, `ctx.target_path()` is the fixed path of
  whoever raised it, the app keeps that path across dispatches and sends the
  answer back to exactly that component. The trade, plainly: what was lost is a
  serializable document with one atomic apply and a wire format an agent could
  diff; what was gained is one class of thing instead of two, and a seam that
  reaches INSIDE a guest's own placeholder — which a document describing only
  the host's layout never could. `docs/agent-runtime.md` was specified against
  that document and now carries a banner saying it needs redesigning;
  `dyncomp/ARCHITECTURE.md` records both the new shape and the known gaps.

- **Two more MoonBit guests: a calculator and tic-tac-toe.** They exist to
  cover the halves of the contract the counter does not. `calclib/Calculator`
  declares `display` — the answer, which a host can project, form and hand
  back — and keeps the pending operand and its operator to itself, because
  they mean nothing outside the component and a host that could write them
  could not reason about what it wrote; so it `persist`s, as its own JSON.
  `gameslib/TicTacToe` declares the board as a list and stores nothing else:
  whose turn it is, who won and which line they won on are all functions of
  it, and state that can be computed is state that can be wrong. It has no
  `persist` for the same reason the counter has none — the board IS the
  declared field.

  Both are sample bundles on the universal demo. The tic-tac-toe board also
  re-learns a lesson the Rust notepad had already recorded: a `$method` takes
  no arguments in a conditional slot, so "is this square part of the winning
  line" rides ON each square rather than being asked per square. Written the
  other way it renders no class at all, silently.

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

- **Every wasm-gc preview in the playground failed to link, and said the
  browser was at fault.** `playground/web/runtime.js` carried its own copy of
  the `jscore` and `tdom` import namespaces that `app/wasm/loader.mjs` defines.
  `tdom` grew `dropped_files`; the copy did not follow; from then on every
  wasm-gc mount — the DEFAULT target, in the standalone playground and in every
  `<mb-playground>` on the landing page — died with `LinkError: Import #8
  "tdom" "dropped_files": function import requires a callable`. The js fallback
  caught it, so the page kept working and reported `wasm-gc not supported
  here`, which is why it survived a release: the one message a reader cannot
  act on and an author reads as somebody else's problem.

  runtime.js now imports the loader (`./app-loader.mjs`, copied into
  `dist/playground/` by `assemble.mjs` and packed into the npm shell) and
  substitutes only `global_this`, which must be the preview iframe's window
  rather than the page's. There is no second copy of the contract left to drift.

  Two guards, because a wasm-gc mount is only exercised by a browser:
  `check-viewgen-tab.mjs` now instantiates its import object FROM that loader
  and fails the build when a linked module names something the loader does not
  supply (it catches this exact bug — verified by removing `dropped_files` and
  watching it fire), and the fallback now reports the real error instead of
  blaming the engine, in the standalone shell's status and diagnostics and as a
  `console.warn` from the embeddable element.

- **A browser host could not choose what it accepts.** `dyncomp/policy` has
  three tiers and `register_bundle` takes one, but `dyncomp/host/wasm` called it
  without an argument — so every bundle a page loaded was registered as
  `untrusted` and there was no way to say otherwise. A host that wanted to grant
  a capability could not, which made `Granted` and `System` reachable only from
  a test: any bundle declaring `cap-clock` or `cap-random` was refused by every
  page that could actually run one, and shipping its own CSS was likewise
  impossible. `@uiw.mount` now takes `policy` (still defaulting to `untrusted`,
  which is the only safe default for a loader whose purpose is to accept an
  archive from somewhere), `@dhw.set_app` takes it for a page that mounts
  itself, and `@dhw.set_policy` changes it afterwards for a host that asks a
  person first. It applies at LOAD, so narrowing it does not retract a bundle
  already registered — revoking is dropping the bundle.

- **A scaffolded guest could not be built.** `tutuca new-guest` writes a
  `build.mjs` that ran jco from a hard-coded `node_modules/@bytecodealliance/
  jco/src/jco.js`, and it declares that dependency as `^1.25.2`. jco 1.26 moved
  its entry point to `dist/jco.js`, so a scaffold created after that release
  npm-installed cleanly and then failed on the transpile step with "jco is not
  installed" — the one error message that could not be acted on, because it was
  installed. The path now comes from jco's own manifest (`bin.jco`), which is
  the one place that cannot disagree with the layout. Found by
  `examples/dyncomp-dice`, which is what it is for.

  The repository's own guest builders had the same hard-coded path and were
  merely hidden by its pin: `guests/build-guest.mjs` and
  `guests/rust-tempconv/build.mjs` broke the moment the devDependency moved to
  1.26, taking `just guests` with them. They ask the manifest now too, through
  a shared `jcoBin()` in `guests/guests.mjs` — resolved from this repository's
  `node_modules` and never from `PATH`, where the bare `jco` name is a
  dependency-confusion placeholder.

- **An update that changed only what a schema does not name was thrown away.**
  `reuse_equal` — the check that keeps a rebuilt-but-equal field from
  propagating a new object to the root — compared two INSTANCES structurally,
  and `obj_eq` ranges over the declared fields. So a successor that changed
  something its schema does not name (an opaque guest's draft, a cursor, a
  parser's arena) looked exactly like its predecessor, the parent kept the
  predecessor, and the edit vanished — silently, with the successor's handle
  already queued for collection, which is where the bridge's `no live
  instance` warnings came from. Instances are compared by `obj_identity` now:
  same origin and same revision, or not the same instance. Writing the SAME
  instance back still collapses, so a no-op interaction stays free.

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

- **BREAKING: every `App` sanitizes its own render output now.** `App::new`
  installs `@filter.Baseline` — the URL-scheme rule and the event-handler rule
  in one traversal — where the seam previously defaulted to absent. An app that
  renders `<a href="javascript:…">` from its state, or writes a raw `onclick`
  content attribute, loses that attribute instead of writing it to the DOM.

  The old behaviour is one call: `App::set_filter(None)`. Worth taking
  deliberately rather than reflexively — what it is for is an app with a
  genuinely intended `javascript:` URL, or a tree with no user-supplied data
  anywhere in it.

  The reasoning, for anyone who has to decide which way to go: the trusted
  default was paying nothing and getting nothing, while every app that had never
  heard of the seam was the one carrying the risk. `dyncomp` hosts were already
  covered because their glue installed a filter explicitly; a plain tutuca app
  was not, and `Policy::check_view` — the static pass — has a single call site
  and never runs for one. So "safe by default, opt out in one call" replaces
  "safe if you read `docs/sanitizer.md`".

- **`take_reports` is a `VdomFilter` trait method** rather than an inherent one
  on each filter, defaulting to none for a filter that only rewrites. A host no
  longer necessarily holds the concrete type — the filter that drops something
  is usually the one `App::new` installed — so draining had to work without it,
  or the new default would be a silent dropper and "why did my link vanish"
  would have no answer. `App::take_filter_reports()` is the accessor.

  `dyncomp`'s glue stops installing its own filter, since the app already
  carries one and two would split the reports across two logs. Its
  `take_filter_reports()` drains the app's. That also retires a caveat
  `SECURITY.md` carried: the install used to be one line in the wasm glue, which
  `moon test` never runs, and is now in `App::new`, which the suite exercises.

- **The Rust guest is a temperature converter** (`guests/rust-tempconv`, was
  `rust-notepad`, before that `rust-counter`). A counter never has to answer
  the questions the newer halves of the contract exist for; this does. It
  declares ONE number and shows it three ways, and the half its declared field
  cannot hold is the DRAFT: somebody heading for `-40` is at `-` on the way,
  and reformatting their box while they type is the difference between a
  control that works and one that fights. `-` is not a number and no declared
  field can hold it, so it goes in `persist` — a length-prefixed byte string of
  the guest's own, which demonstrates "the host never reads these" better than
  JSON would.

  The notepad it replaces is now buildable out of primitives (a `Tabs` holding
  a `Textarea`), and a component that primitives compose into is not one worth
  shipping as a bundle. That composition is the acceptance test in
  `dyncomp/ui/ui_test.mbt`.

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
  parse the linter already does and before anything is registered. Guest CSS,
  which is scoped by concatenation and would escape through a `}`, is held
  instead as a contract invariant: no guest-declared field reaches the host's
  unscoped `global_style`, and the WIT says so.

- **The WHATWG Sanitizer API, ported over anode views** (`anode/sanitize`) —
  the spec's config model (`elements` / `removeElements` /
  `replaceWithChildrenElements` / `attributes` / `removeAttributes` /
  `comments` / `dataAttributes`) with its validity relation, over the compiled
  `ANode` tree. Everything the config model asks about is a NAME, and every name
  in a view is a literal — the parser lowercases what it reads and stores it as
  a `String`, so there is no `:onCl${x}ick` — which is what makes an allowlist
  over names COMPLETE over the described part of a view, and the pass decidable
  at registration rather than at render.

  Safety comes from the entry point rather than the config, as in the spec: the
  unsafe elements and every `on*` attribute are refused before a config is
  consulted, so a config naming `script` still does not get `script`. The event
  handler half is a prefix predicate rather than the spec's enumeration, which
  is a superset that cannot fall behind the platform.

  `SanitizerConfig::default()` is the BASELINE, not the spec's default
  configuration — those are different things, and conflating them would refuse
  an ordinary commented view. The spec's element allow-list is deliberately not
  transcribed: it has to come from the specification text rather than a summary
  of it, because an entry quietly lost is a component that mysteriously fails to
  render and one quietly gained is a hole. A host wanting an allow-list supplies
  one and gets `validate()` to keep it honest.

- **`Policy::check_view` runs the sanitizer instead of `has_raw_html`, which
  closes a live hole.** `ANode::for_each_child` never visits `MacroData.slots`,
  so raw markup inside a macro call's slot —
  `<x:card><div @dangerouslysetinnerhtml=".payload"></div></x:card>` — passed
  registration with no refusal. It only rendered if the host had registered a
  macro named `card` whose body placed the slot, so the hole was contingent
  rather than unconditional. The sanitizer carries its own walk rather than a
  fix to `for_each_child`, because `set_data_attr` and `collect_registered`
  share that function and adding `slots` would make them stamp and index the
  same subtree twice once expansion has run. Refusals now name the element and
  carry a locator.

- **A filter seam between render and diff** (`vdom/filter`), for the half the
  Sanitizer API declines to decide. The spec has no opinion about attribute
  VALUES — its own default configuration allows `href` on `<a>`, so
  `<a href="javascript:…">` comes through `setHTML()` untouched, and the
  platform answers that with CSP and Trusted Types instead. anode answers it
  here: a `&VdomFilter` runs between `render_root` and the diff, installed with
  `App::set_filter`.

  It is absent by default, so trusted code pays one `if` per render rather than
  a branch per attribute. It mutates rather than rebuilds, which is load-bearing
  and not a style preference: morph short-circuits a subtree by physical
  identity and the render cache hands back the same `Vdom` object when a site's
  inputs are unchanged, so a filter that rebuilt nodes would quietly turn every
  render into a full diff.

  `UrlFilter` is the rule that ships: normalize (strip whitespace and C0
  controls from anywhere, since `java&#9;script:` is `javascript:` to a browser,
  then lowercase), take the scheme only when its `:` precedes any `/`, `?` or
  `#`, deny `javascript` and `vbscript` outright, and deny `data` on the
  navigational names while allowing it on the media ones — `<img src="data:…">`
  is ordinary, `<a href="data:text/html,…">` is a same-origin document.
  `srcset` and `ping` are checked per entry, because they are lists and a
  whole-string check would pass `"a.png 1x, javascript:… 2x"`. A denied value
  drops the ATTRIBUTE, not the element, and is recorded in a bounded log the
  host drains with `take_reports()` — by then there is no author to report to,
  and the value may have come from application state rather than anyone's
  template.

  Installing is not retroactive: a value already in the DOM stays until
  something re-renders over it, for the same reason a policy applies at load.

- **The dyncomp host installs one**, so a loaded bundle gets both passes rather
  than only the static one — `set_app` calls `set_filter` beside the policy and
  the GC sweep, and `take_filter_reports()` drains the log.

- **Raw markup as described NODES** (`vdom/filter/markup`), its own package
  because it drags an HTML parser and the config model behind it and a host that
  only wants the URL rule should not pay for either. The obvious port of
  `setHTML()` — parse, prune, serialize, `set_inner_html` — is the shape that
  has bitten every sanitizer which shipped it: the browser parses the string a
  SECOND time, and any disagreement between the two parsers is a mutation-XSS
  vector. So the payload is parsed once, sanitized as a tree, and the result
  replaces the element's children; `set_inner_html` is never called, because the
  attribute `set_prop` looks for is gone by then. The subtree is checked by the
  builder, attribute values included, since no filter runs after the one that
  created those nodes.

  Guests are still refused the construct outright: `check_view` cannot know
  whether a host installed the filter, so a policy permitting raw markup beside
  an app mounted without it would send the payload straight to
  `set_inner_html` unchecked. Loosening that should be one explicit decision
  rather than a side effect of the capability existing.

- **memdom answers `has_property` truthfully for `on*`.** It listed reflected
  and state properties only, so `"onclick" in node` came back `false` and
  `set_prop` sent the name to `set_attribute` — writing a live
  `onclick="…"` content attribute where a browser, for which the name IS a
  property, assigns an inert string to `.onclick` instead. memdom is the DOM
  every `moon test` renders onto, so the divergence ran the wrong direction for
  a test double: anything asserting that this attack fails would have asserted
  it against a DOM that makes it succeed. Same prefix predicate as
  `@sanitize.is_event_handler_attr`.

- **`on*` attribute routing is pinned** (`vdom/memdom/event_attr_test.mbt`).
  Not a construct tutuca asks for — a handler is `@on.click`, which compiles to
  `data-eid` and never reaches vdom as an `on*` name — but a view that writes
  the content attribute directly is the case a sanitizer exists for. The tests
  record that on a plain HTML element the string lands on the property and is
  inert, that this is an accident of routing rather than a defense (the
  property branch falls through to `set_attribute` when assignment fails), and
  that **on a namespaced element it is not inert at all**: `uses_prop` is
  `!namespaced && …`, so `<svg onclick="…">` and `<circle onload="…">` are
  written verbatim as content attributes, which SVG honours. `anode/sanitize`
  refuses the name at registration, but only for a dyncomp guest — a plain app
  runs no static pass, so that half is open and `docs/sanitizer.md` now says
  which change closes it. There is also a test for why `never_assign` is not
  the fix: it would force the attribute path on plain HTML elements too.

- **An event-handler rule at render time** (`@filter.HandlerFilter`), which is
  the half of the name rule a plain app can reach. `anode/sanitize` settles
  names at registration and is the better place — it is cheaper and it can tell
  the author — but `Policy::check_view` has one call site, so that pass runs for
  a dyncomp guest and nobody else. The filter drops `on*` off the tree before
  the diff, by name and whatever the value's type, since a view cannot express
  a function and tutuca's own handlers are `@on.click` compiling to `data-eid`.
  It is the only thing that covers the namespaced case, where no accident of
  routing applies.

  `@filter.Baseline` composes it with the URL rule in ONE traversal, rather than
  `Chain::new([…])`, which walks the tree twice for two rules that both only
  read `attrs` — a difference worth a type given the filter runs on every
  render. `dyncomp` installs `Baseline` now instead of `UrlFilter`: the handler
  half is belt-and-braces there, since a guest carrying an `on*` name never
  loads, but a rule that only holds when another pass already held is not a
  second layer, and the shared walk makes it free.

  Still opt-in for a plain app — `App::set_filter(Some(@filter.Baseline::new()))`.
  Making it the default is a behaviour change for every existing app and is
  tracked separately in `docs/sanitizer.md`.

- **A `Policy` carries its own sanitizer**, so a host can tighten what a guest
  view may name or loosen it. `Policy::with_sanitizer(config)` returns the same
  policy checking against a different `@sanitize.Sanitizer`, raising on an
  invalid config rather than degrading — an invalid config is a programming
  error in the host, the one party here who can read the message and fix it.
  Tightening means an allow-list (the spec's own is still not transcribed, so a
  host that wants one writes it and gets `validate()` to keep it honest);
  loosening means `raw_markup: true`.

  That last one was held back before, because `Policy::check_view` had no way to
  know whether the render-time markup filter was installed, and the permission
  without the filter sends a payload straight to `set_inner_html` unchecked. The
  answer is `@markup.filter_for`, which derives the filter from the SAME
  sanitizer the policy checks against: the markup filter in front of `Baseline`
  when raw markup is permitted, `Baseline` alone when it is not. `set_app` calls
  it, so the two cannot come apart.

  A function rather than a type-level proof because `dyncomp/policy` is a leaf
  over `anode` and must not import `vdom`; the permission cannot carry evidence
  about a filter without inverting that direction. What is available is to make
  one function the only place the two are named together, and to test it from
  both sides.

  Order inside the chain is load-bearing: the markup filter REPLACES a subtree,
  so the attribute rules run after it or they inspect nodes that do not exist
  yet. Built the other way round, a payload's own `javascript:` URL survives.

  Defaults are unchanged — every tier still refuses raw markup, so a guest that
  was registered before is registered now. `Policy` is `pub(all)` and gained a
  field, so code building one as a literal has to add `sanitizer:` (or go
  through `untrusted()` / `granted()` / `system()`, which is the intended way);
  the `Policy::sanitizer()` method is now that field.

- **The filter runs where an element is CONSTRUCTED**, not over the finished
  tree. `RenderCtx` carries it and `render` applies it in the one place it
  builds an element, so every element is filtered exactly once and a subtree the
  render cache hands back — never rebuilt — is never filtered again.

  Applied to the finished tree it had the wrong complexity, which defaulting it
  on made everyone's problem: the cache returns the same `Vdom` object for an
  unchanged site and morph then short-circuits it by physical identity, so the
  filter did O(whole tree) work beside a pipeline that is otherwise O(changed).
  On a thousand-row list, morph touches one row and the filter touched a
  thousand.

  The obvious fix — walk each rebuilt body, stopping at nested `§Comp§`
  boundaries — does NOT work, and the reason is worth knowing: `@vdom.fragment`
  flattens nested fragments (`normalize_childs`), so a nested component's
  `[meta, body]` is spliced inline into its parent's child list and there is no
  boundary left to stop at. A test counting filtered elements caught it at once.
  Hooking construction sidesteps the question entirely and costs no walk at all.

  Two consequences. `App::set_filter` now **clears the render cache**, because a
  cached subtree carries the verdict of whichever filter built it and a newly
  installed one would otherwise never see most of the tree. And a filter that
  replaces children owns checking what it built — nothing runs after it on nodes
  it created — which `MarkupFilter` already did by design and now depends on.

  `VdomFilter`'s primitive is `filter_elem` accordingly; `filter_tree` remains
  as a defaulted convenience for a caller holding a tree.

  Measured: `OPTIMIZATIONS.md` #11. Interleaved 3× per side on both targets —
  `patch move json 8x4` −34.8% / −37.9%, `toggle todo 1000` −28.6% / −20.4%,
  `add+remove todo 1000` −24.7% / −17.4%. The win scales with how much a render
  reuses, so the rebuild-everything workloads move inside their own spread.

  What the filter still costs, with that fixed, is +4% to +33% on what actually
  rebuilds — measured against `set_filter(None)` and recorded in #11. Inspecting
  every attribute of every element BUILT is the irreducible part; the only
  remaining lever that does not weaken the rule is the skip set.

- **The filter's no-op path stops allocating** (`OPTIMIZATIONS.md` #12).
  `url_attrs.contains(name.to_lower())` allocated a String for every attribute
  of every element before discovering the name is not a URL attribute at all —
  which is what almost every name is. `is_url_attr` probes the set with the name
  as it stands and falls back to `to_lower` only for a name that contains an
  uppercase letter. Both filters also allocated a `doomed` array per element for
  names they almost never collect; lazy now. −2% to −3.5% on the workloads that
  construct the most elements, consistent in direction, nothing worse.

- **An SVG `<script>` was not refused.** `<svg><script>alert(1)</script></svg>`
  in a guest view passed `Policy::check_view` with **no violation at all** — so
  it registered, rendered into the host's page, and an SVG `script` inserted
  through the DOM executes.

  The cause is worth stating plainly, because it is the exact failure the design
  document had warned about in the abstract: the baseline list was written from
  a SUMMARY of the spec rather than from the spec. The spec's baseline lists
  `script` **twice**, once per namespace, and element identity here is
  namespace-qualified (`ElementName::key` prefixes `svg:`), so `html("script")`
  never matched it. `svg("script")` is in `unsafe_elements` now.

  `unsafe_elements` is held against the spec's own baseline by a test from here
  on, against a list generated rather than typed. Containment, not equality:
  tutuca additionally refuses `base` — a `<base href>` retargets every relative
  URL on the host's page — and the difference is asserted explicitly so a
  regeneration cannot absorb it silently.

- **The spec's default allow-list is transcribed**, as
  `SanitizerConfig::spec_default()`: 121 elements across three namespaces with
  their per-element attributes, 58 global attributes, comments and `data-*` off.
  Generated by `scripts/fetch-sanitizer-defaults.mjs` from the machine-readable
  `builtins/` in the spec repo at a pinned commit — which is what the spec's own
  prose is generated from, so it cannot drift from the text the way a hand
  transcription can. `--check` fails if the committed file is stale.

  **It is offered, not imposed, and `default()` is still the baseline.** Not
  caution: the spec's default configuration allows no interactive or media
  element at all — no `button`, no `input`, no `img`, no `form`, no `select`. It
  is built for pasting document content into a page, and a tutuca view describes
  an interactive component, so adopting it as the default would refuse
  essentially every real guest. A host whose guests really are document content
  hands it to `Policy::with_sanitizer` and gets the platform's own answer.

  `AGENTS.md` now carries the general rule: never hand-transcribe an allow-list,
  and never take one from MDN or a blog post. An entry quietly lost is a
  component that mysteriously fails to render; one quietly gained is a hole.

- **`SECURITY.md` §3 is rewritten**, including a claim it got wrong about URL
  schemes. Design, and the work still open, in `docs/sanitizer.md`.

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
