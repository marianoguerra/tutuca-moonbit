# Project Agents.md Guide

This is a [MoonBit](https://docs.moonbitlang.com) project — a port of
[tutuca](https://github.com/marianoguerra/tutuca). References below to JS files
like `src/vdom.js`, `src/path.js`, `tools/core/test.js`, or `docs/examples/*.js`
point at that upstream repo, not at files in this one.

You can browse and install extra skills here:
<https://github.com/moonbitlang/skills>

## Project Structure

- MoonBit packages are organized per directory; each directory contains a
  `moon.pkg` file listing its dependencies. Each package has its files and
  blackbox test files (ending in `_test.mbt`) and whitebox test files (ending in
  `_wbtest.mbt`).

- In the toplevel directory, there is a `moon.mod` file listing module
  metadata. The toplevel package itself is intentionally minimal (just the
  `README.mbt.md` doctest) — the foundational value language + path/dispatch
  runtime lives in `core/` (imported everywhere as `@tutuca` via
  `"marianoguerra/tutuca/core" @tutuca`). It is one package by necessity: its
  `value_*` and `path_*` types form a single dependency cycle that can't be
  split across an import edge (see `core/spec.mbt`).

## Coding convention

- MoonBit code is organized in block style, each block is separated by `///|`,
  the order of each block is irrelevant. In some refactorings, you can process
  block by block independently.

- Try to keep deprecated blocks in file called `deprecated.mbt` in each
  directory.

- Files named `*_gen.mbt` are GENERATED and checked in; never hand-edit one.
  Change its source and rerun the task that produces it (`gen-views` for a
  `*_view_gen.mbt` from its `.html`; `skill-embed` for
  `cli/skill_assets_gen.mbt` from `skill/tutuca/`). `moon fmt` owns the layout
  of the `*_view_gen.mbt` pair, so the `gen-views` task formats after
  generating — run the task, not the CLI directly, and the checked-in files
  stay reproducible. `cli/skill_assets_gen.mbt` works the same way: its task
  ends in `moon fmt` too, so what is checked in is already what fmt produces
  and a later `moon fmt` leaves it alone. (This paragraph used to say the
  opposite — that the file was not fmt-stable and had to be reverted after a
  `moon fmt` — while `dev/tasks.mbt` said the trailing fmt was there precisely
  so it would be. The task was right; it was checked by running both.)

- `dyncomp/` has three documents, and they divide as: `DESIGN.md` is the
  contract and how it maps onto tutuca; `SECURITY.md` is what a loaded bundle
  can and cannot do, with the file/line evidence for each claim; and
  `ARCHITECTURE.md` is the plan for the universal UI and the agent runtime on
  top. The agent tool surface has no document: the one it had was specified
  against the `Surface` document that no longer exists, and it was deleted
  rather than left to mislead.
  Changing the WIT means checking `SECURITY.md`'s "What to check when changing
  this" — two of its three findings were fields nobody thought were a channel.

- The guest binding trees under `guests/*` — every name in `guests/guests.mjs`
  — are generated and checked in the same way, by `gen-guest-bindings`, from
  the ONE WIT in the repo (`dyncomp/wit/tutuca-component.wit` — no guest keeps a copy,
  and the Rust guest's `generate!` macro reads it too). `wit-bindgen`'s raw
  output has to be normalized before it can be checked in meaningfully: it
  emits its FFI shims in HASH order, which differs between two runs on the
  same input. `guests/gen-bindings.mjs` sorts them (MoonBit `///|` blocks are
  order-irrelevant) and drops the `moon.pkg.json` twins of the hand-maintained
  package files, which is what makes the drift check honest. It also copies
  `guests/sdk.mbt` — the ONE guest SDK, for the same reason there is one WIT —
  into every guest tree, and writes one formatted copy back, since the canonical
  is in no moon module and `moon fmt` would never reach it. The one handwritten
  file left in those trees is the component source (`counter.mbt`, `todo.mbt`,
  …); its name is one wit-bindgen never emits, so regeneration leaves it alone.

- `examples/*` are not packages of this module and not demos. Each is a
  CONSUMER: its own `moon.mod` depending on the PUBLISHED `marianoguerra/tutuca`
  fetched from mooncakes like anyone else's. They are excluded from publish,
  `moon check` / `moon fmt` / `cmd/dev -- ci` never reach them (a nested
  `moon.mod` stops discovery, the same way `guests/*` do), and each has its own
  `build.mjs` that is the only way to build it. **An example must never gain a
  path dependency, a `../` out of its own directory, or a step that runs
  anything from this repo** — the one thing they prove is that a release is
  complete on its own, and any of those would quietly stop proving it. That is
  also why the directory is `examples/` rather than `example/`: no one of them
  is "the" example, and a new one should be able to cover a different seam
  without renaming anything.

  `examples/dyncomp-dice` is the first: the universal dynamic-component host
  plus one locally-authored guest. It exercises precisely what `moon check`
  cannot — that the two wasm-gc JS loaders survive `moon publish`, that the
  relative import between them is repointable once they land beside a page, and
  that `tutuca new-guest` emits a tree that actually builds. Run the examples
  after a release, before announcing one.

## Tooling

### Task runner (`cmd/dev`)

Common workflows are collected in a MoonBit task runner instead of loose
commands. It is the single place tasks live (the `dev/` package holds the task
list; `cmd/dev` is the native shell that runs it):

```
moon run --target native cmd/dev -- <task>
```

There is also a `justfile`, and it is the ergonomic front door rather than a
second task list: every recipe is a one-line wrapper over the task of the same
name (`just check`, `just ci`, `just dist`), `just dev <task>` reaches anything
without a recipe, and `just cli <args>` runs the CLI. Prefer adding a task and
letting the recipe stay one line — a recipe that grows a second command has
started being a task in the wrong place. The two `clean` recipes are the
deliberate exception, and say why in the file: the task runner is a native
binary inside the `_build` they delete.

| Task       | Does                                                              |
|------------|------------------------------------------------------------------|
| `check`    | `moon check` for default, js and native targets                  |
| `fmt`      | `moon fmt` then `moon info` (format + regenerate `.mbti`)         |
| `test`     | `moon test` for default, native, and js browser adapters         |
| `build`    | `moon build` for wasm-gc, native CLI, and js                     |
| `coverage` | `moon coverage analyze`                                           |
| `setup`    | `npm install` (happy-dom for js tests) + enable the git hooks    |
| `ci`       | `gen-views` + `skill-embed` drift checks, then `check`, the example/skill/guest checks, `test` and `build` |
| `dist`     | build all targets and assemble a self-contained runnable `dist/` |
| `gen-views` | regenerate the checked-in `*_view_gen.mbt` from their `.html` sources (`viewgen/`); formats after generating, then drift-checks the generated modules — a stale one type-checks and tests green, so this is what catches it |
| `gen-conformance` | project `tscript/conformance`'s corpus into `tscript/conformance/mbt/corpus.html`, then run `gen-views` over it — the MoonBit backend cannot read the corpus directly, since its answers only exist once `moonc` has compiled them. Run after ADDING a case; `ci` re-runs and drift-checks the compiled half on its own |
| `gen-guest-bindings` | regenerate the checked-in MoonBit guest bindings (every guest in `guests/guests.mjs`) from the ONE WIT (`dyncomp/wit/tutuca-component.wit`), copy in the ONE SDK (`guests/sdk.mbt`), then drift-check them |
| `skill-embed` | regenerate `cli/skill_assets_gen.mbt` from `skill/tutuca/` (the embedded assets `tutuca install-skill` writes out; `dist` runs it first), format, then drift-check — in `ci`, because the embed ships inside the binary and a skill edited without re-embedding is invisible until somebody installs it and reads the wrong thing |
| `check-guest-list` | hold `dev/tasks.mbt`'s guest list against `guests/guests.mjs`. Plain node, so unlike the guest BUILD it runs in `ci` — which is how `guests/table` sat in one list and not the other, built by nothing |
| `guest-harness` | build every guest bundle, then run the node harnesses in `dyncomp/test/` over them — the only runtime coverage the guest ABI and the table codec have. Not in `ci`: needs wasm-tools + jco |
| `sanitizer-defaults` | regenerate `anode/sanitize/spec_default_gen.mbt` from the pinned WHATWG spec commit, format, then drift-check (needs network) |
| `dom-props` | regenerate `eventpath/dom_props_gen.mbt` from the browser specs' machine-extracted IDL (`w3c/webref`, pinned in `scripts/fetch-dom-props.mjs`), format, then drift-check (needs network). The type oracle an `e.<path>` is checked against — does this event interface have this property, and what is its type. Same rule as the sanitizer baseline and for the same reason: **never hand-transcribe it** |
| `dyncomp-storybook` | assemble `dist/dyncomp-storybook/` — the gallery of every component every loaded bundle declares, once per named `init` — with every sample bundle beside it. Out of `dist` for the same reason `universal` is: the guests need wasm-tools + jco |
| `guest-template-embed` | regenerate `cli/guest_template_gen.mbt` — the guest tree `tutuca new-guest` writes out — from `guests/counter` (bindings + SDK) + `dyncomp/wit` (the contract) + `guests/template` (the overlay that carries the `{{name}}` placeholders); `dist` runs it beside `skill-embed` |
| `check-guest-template` | scaffold a guest with that embed and `moon check --deny-warn` it; part of `ci`, and the only coverage `new-guest` has (CI never builds a real guest — `guests` needs wasm-tools and jco) |
| `check-skill` | compile-check the MoonBit snippets in `skill/tutuca/` and check every one against the `.mbti` files for names that no longer exist; part of `ci` |
| `css-bundle` | regenerate `css/{tailwind,margaui}_bundle_gen.mbt` from the pinned `tailwindcss` npm release + a margaui clone (needs network); see "Styling" below |
| `npm-pack` | stage + `npm pack` the playground's two npm packages from an assembled `dist/` (manifests in `playground/npm/`); packs only — publishing is manual, see CONTRIBUTING.md |
| `tutucard-playground` | assemble `dist/tutucard/` — the CARD playground, which ships no MoonBit compiler: a card is compiled to wasm by `tutucard/wasm` and the module is instantiated in the page, so the payload is that compiler, the Wax front end it stands on, and the page — plus the two things a card can ASK for, each fetched lazily by the page that wants it: `margaui.wasm` (the class compiler the starter cards' `btn`/`card`/`badge` need, scoped to the preview — `web/margaui.js`) and `editor.bundle.js` (the shared CodeMirror: the page upgrades its own textareas to it once the first card is mounted, `?editor=plain` keeps the textareas, and an `<mb-card codemirror>` upgrades its own). Ends by CHECKING and COMPILING every card through the real entry points — the starter cards, which are JS strings no MoonBit test can reach, and the landing site's `playground/site/cards/*.html`, which are in no moon package — and by holding `web/regions.js` — the offset arithmetic the structured view edits through — to its contract |

While editing views, `tutuca watch [path…]` regenerates them on every save
(mizchi/fswatch; native only, since the watcher is the shell's job). It
manages the `.html` files that already have a generated sibling, so pointing
it at a project root does not try to compile `index.html`. Add
`--tailwind-css`/`--margaui-css <file>` and it rewrites that stylesheet too,
once per settled batch over every watched view.

The `playground` task ends with `playground/build/check-viewgen-tab.mjs`: the
View tab generates a MoonBit module in the browser and feeds it to the
in-browser compiler, and nothing else exercises that path — the generated
module compiles in a package with no `moon.pkg`, where `@tutuca` is the
module-root facade rather than `core/`. It drives generate → compile → link
headlessly against the assembled payload, for every standalone-playground
starter example with a View tab (`playground/web/starter.js` — covered here
and nowhere else) AND every landing-site example pair
(`playground/site/examples/<name>.{mbt,html}`, which the embedded
`<mb-playground>` elements compile in a visitor's browser). The cheaper
`check-examples` task covers the same examples through `moon check` instead,
generating their views with the same generator built to js.

`check-skill` reuses that same js generator for the bundled skill. Nothing else
compiles `skill/tutuca/`, and it rots: `specs=` / `@component.FieldSpec` outlived
the parameter's removal by two releases in five files, and the skill ships inside
the CLI binary, so a wrong snippet is what an agent reads before writing any
tutuca code. A recipe that shows both halves — an ```` ```html ```` view file then
the ```` ```moonbit ```` that uses it — gets the view half generated and the pair
compiled together, per markdown SECTION (snippets in one section refer to each
other; snippets in different sections are unrelated components that would
collide). Fences are load-bearing: bare ```` ```moonbit ```` is compiled,
`moonbit fragment` is wrapped in a `fn` first, and `moonbit nocheck` is skipped
but **must** carry a `// nocheck: <reason>` line. Most blocks are bucket-argument
fragments that no wrapper makes compilable, so they are `nocheck` — which is why
every block, `nocheck` included, additionally goes through an identifier check
against the checked-in `.mbti` files. That second pass is the one that catches a
removed parameter, and it is the reason the task is worth having at all.

Nothing in the playground shell resolves a fetched URL against the page.
`runtime.js`'s `playgroundConfig` derives the four of them — the worker, the
compiler blob, `manifest.json`, `fs/` — from the calling module's own
`import.meta.url`, and `makeCompiler` hands them to the worker **absolutely**,
so the worker resolves nothing against its own location either. That is what
lets the payload sit somewhere other than the shell (a different folder,
package, or origin — a cross-origin worker gets a same-origin blob shim,
since a `Worker` script must be same-origin), and what lets a host serve their
own `@moonbit/moonc-worker` rather than a copy of the 5.5 MB blob:
`globalThis.MB_PLAYGROUND = { payloadBase, compilerUrl, workerUrl }` (all
optional) before the first compile. A host-supplied compiler is checked against
`manifest.mooncWorker` when npm's `package.json` sits beside it — the payload
and the compiler are one pair, and a mismatch otherwise surfaces as nonsense
about the user's code (`playground/vendor/README.md`).

`dist` produces `dist/index.html` (a landing page with run instructions),
`dist/cards.html` (the card tutorial — eight `<mb-card>` embeds and the block
language in one page; its cards are `playground/site/cards/*.html`, which
`tutucard-playground` loads through the real loader),
`dist/counter/` (the **js** counter demo with its bundle, `<script src>`
repointed to sit beside the page), `dist/counter-wasm/`
(the **wasm-gc** demo — a `.wasm`, a host page, and `app/wasm/loader.mjs`
copied beside it as `app-loader.mjs`),
`dist/storybook/` (the storybook
gallery compiled to wasm-gc — the bundle `tutuca storybook` serves),
`dist/playground/` + `dist/site/` + `dist/tutucard/` (the landing page embeds
BOTH kinds of live example: `<mb-playground>`, which compiles MoonBit in the
browser against `dist/playground/`, and `<mb-card>`, which compiles no MoonBit
— `assemble-site.mjs` copies `dist/tutucard/tutucard.js` beside the page,
which is why `dist` assembles the card runtime before the site. It copies
`margaui.wasm` from there too, for an `<mb-card margaui>`: that is the one
thing a card DOES compile, its class names into CSS, and only when an element
asks), and `dist/cli/tutuca` (the native CLI binary).

The landing page also links `./universal/` and `./dyncomp-storybook/`, and
`dist` builds **neither**: both need the component toolchain (wasm-tools + jco)
that the guest bundles require, which is why they are their own tasks. Run
`universal` and `dyncomp-storybook` after `dist` to fill them in — the Pages
workflow does exactly that, and `assemble-site.mjs` warns for each one missing
rather than leaving a dead link to be found by clicking it.

The wasm pages need a browser with
the JS String Builtins proposal, e.g. Chrome. Serve dist with any static file
server: `cd dist && python3 -m http.server` — or `dist/cli/tutuca storybook`
serves `dist/storybook/` over HTTP (default port 4321). `dist/` is gitignored.
Run with no task to print the task list.

The wasm demos are driven by the `vdom/wasm` + `app/wasm` packages (the wasm-gc
twins of `vdom/browser` + `app/browser`): the DOM is reached from wasm-gc
through mizchi/js's `@core.Any` plus a small `tdom` FFI, and — since MoonBit
closures can't cross into JS on wasm-gc — JS calls the exported `on_event` on
each DOM event instead of receiving a closure. `demo/counter_wasm`,
`demo/universal_wasm`, `demo/storybook_wasm` and `demo/dyncomp_storybook_wasm`
are the wasm-gc hosts
(`demo/counter_wasm` is the twin of the js `demo/counter`; `storybook_wasm`
mounts the `storybook/ui` gallery over the whole example registry, and
`universal_wasm` hosts the dyncomp guest bundles — though almost nothing is left
in it, since the host itself is the published `dyncomp/ui/wasm` and the page is
the ~90 lines that call `mount` and re-export the entry points, an export list
being per-package `link` config that cannot come from a dependency;
`dyncomp_storybook_wasm` is that same shape over `dyncomp/storybook/wasm`).
Both host packages stand on `dyncomp/shell`, which is the floor under any page
that hosts bundles — the loader bar, `make_instance`, the margaui refresh. It is
deliberately not in `dyncomp/host/wasm`: the bridge should not have to depend on
a CSS compiler and a view parser to answer `get-field`.

The two dyncomp pages are not variants of one thing, and the difference is what
each is FOR. `universal_wasm` is a blank page a person builds on, so it starts
empty and hides its sample buttons behind `?test`; `dyncomp_storybook_wasm` is a
gallery, so it fetches every sample at mount and draws one card per component
per named `init`. A storybook that opens empty and asks you to press a button
first is a storybook with an extra step; a blank page that opens with seven
buttons naming archives nobody has heard of is the wrong first impression the
other way. margaui styling is compiled
in MoonBit: the host's `mount()` hands `collect_classes()` to `css`'s
`compile_margaui` (the `marianoguerra/tailwindcss` port + embedded stylesheet
bundles) and injects the resulting `<style id="margaui-css">`, re-running it from
the exported `refresh_margaui()` after a dyncomp bundle loads. No CDN build and
no `globalThis` class hand-off. The in-browser playground uses the same compiler
shipped to wasm-gc (`playground/margaui_wasm` → `margaui.wasm`, release + wasm-opt).

### Styling (`css/`)

`css/` is the one place stylesheets live, and it is published — the wasm hosts,
the js playground and the native CLI all compile through it. Two generated
bundles, split by provenance and regenerated together by `cmd/dev -- css-bundle`:

- `css/tailwind_bundle_gen.mbt` — stock Tailwind's `theme` / `preflight` /
  `utilities`, taken from the **`tailwindcss` npm tarball** at the version pinned
  in `scripts/fetch-tailwind.mjs`.
- `css/margaui_bundle_gen.mbt` — margaui's `base/`, `themes/` and `src/*.css`,
  from a clone at the ref pinned in `scripts/fetch-margaui.mjs`, with its `tw/*`
  dropped (`--skip-prefix tw/`).

Two more generated-from-upstream files live elsewhere and follow the same rule:

- `anode/sanitize/spec_default_gen.mbt` — the WHATWG Sanitizer API's built-in
  default configuration, from the **machine-readable `builtins/` in the spec
  repo** at the commit pinned in `scripts/fetch-sanitizer-defaults.mjs`.
  Regenerate and verify with the `sanitizer-defaults` task, which does what
  `skill-embed` and `gen-views` do — regenerate, `moon fmt`, then
  `git diff --exit-code`. Prefer it to the script's own `--check`: that flag
  compares the generator's UNFORMATTED output against a file `moon fmt` has
  reformatted, so it reports "stale" on content that is byte-identical.

- `eventpath/dom_props_gen.mbt` — every property an event path can reach, with its
  type, from the **machine-extracted WebIDL in `w3c/webref`'s `ed/idl/`** at the
  commit pinned in `scripts/fetch-dom-props.mjs`. Regenerate with the
  `dom-props` task, which has the same three steps and the same `--check`
  caveat.

  It covers everything inheriting from `Event` or `Element`, plus the leaf types
  an allowlisted step lands on. `Window` and `Document` are deliberately absent,
  and that absence is load-bearing rather than an omission — see the generated
  file's header. The reader in the script is strict on purpose: an attribute
  declaration it cannot take apart THROWS rather than being skipped, because a
  dropped property is a lint that fires on correct code.

  It is a **type oracle and not a permission list**. Whether a step may be
  traversed at all is `eventpath/event_paths.mbt`'s question, and the two are
  separate because one is fetched and the other is argued.

A fourth vendored-from-upstream tree follows the same rule from the other end —
it is copied rather than generated, but it is equally not ours to edit:

- `markdown/` — the CommonMark + GFM parser, copied verbatim from
  [mizchi/markdown.mbt](https://github.com/mizchi/markdown.mbt) at the commit
  pinned in `markdown/UPSTREAM.md` (MIT). 15 of upstream's 29 production files;
  the HTML renderer, serializer and incremental reparser are deliberately left
  behind, because `vdom/filter/markdown` walks the AST straight into vdom nodes
  and never builds an HTML string. **Do not hand-edit a file in there** —
  re-sync by copying again, and let `markdown/parse_test.mbt` (ours, not
  upstream's) fail if a behaviour the node builder depends on moved.

  It is vendored rather than depended on because the published
  `mizchi/markdown` drags `mizchi/moomaid` and declares `supported-targets:
  js+wasm`, while this module prefers wasm-gc. What is copied has no
  third-party dependency and no `extern` at all — `UPSTREAM.md` has the full
  reasoning and the list.

  **Never hand-transcribe an allow-list, and never take one from MDN or a blog
  post.** An entry quietly lost is a component that mysteriously fails to
  render; one quietly gained is a hole. The first attempt at this list was read
  off a summary, which dropped SVG's `script` from the baseline — and since
  element identity is namespace-qualified, `<svg><script>alert(1)</script></svg>`
  passed the sanitizer with no violation at all. `sanitize_test.mbt` holds
  `unsafe_elements` against the spec's own baseline for that reason.

**Take `tw/*.css` from npm, never from the margaui checkout.** margaui's own
`tw/README.md` calls its copies a manual mirror and they lag — at v0.5704.0 they
are still missing the `mauve`/`olive`/`mist`/`taupe` palettes upstream added in
4.3.2, and still carry the pre-4.3.3 `--font-sans` stack. The compiler is ported from one exact tag
(`.mooncakes/marianoguerra/tailwindcss/UPSTREAM.md`), so the stylesheets must
come from that tag or the engine and its data disagree; `fetch-tailwind.mjs`
fails the build if the two pins drift apart. `compile_margaui` merges both maps,
so margaui resolves its `./tw/*` imports against the good copies.

`tutuca gen-tailwind-css` / `gen-margaui-css` are the build-time face of the same
pipeline: the class collection a host does at mount time, run over a project's
view files instead, so an AOT project can ship a static stylesheet. `tutuca watch
--margaui-css <file>` keeps that stylesheet current alongside the view modules —
`WatchPlan` carries a whole `CssPlan`, so it runs the same path rather than a
second implementation of it.

The raw `moon` commands below still work and are what the tasks run underneath.

- `moon fmt` is used to format your code properly.

- `moon ide` provides project navigation helpers like `peek-def`, `outline`, and
  `find-references`. See $moonbit-agent-guide for details.

- `moon info` is used to update the generated interface of the package, each
  package has a generated interface file `.mbti`, it is a brief formal
  description of the package. If nothing in `.mbti` changes, this means your
  change does not bring the visible changes to the external package users, it is
  typically a safe refactoring.

- In the last step, run `moon info && moon fmt` to update the interface and
  format the code. Check the diffs of `.mbti` file to see if the changes are
  expected.

- Run `moon test` to check tests pass. MoonBit supports snapshot testing; when
  changes affect outputs, run `moon test --update` to refresh snapshots.

- Targets: the module's `preferred_target` is `wasm-gc`, so a bare
  `moon check` / `moon test` covers only the target-agnostic packages. Full
  coverage needs all three: `moon test` (wasm-gc), `moon test --target js`
  (vdom/browser, app/browser — happy-dom based; those two packages are what
  the `test` task passes, and the only ones with js-target tests)
  and `moon test --target native` (the cli shell: cmd/main).
  Run `moon check --target js` and `--target native` too before handing off —
  each target surfaces warnings the others don't.

- Prefer `assert_eq` or `assert_true(pattern is Pattern(...))` for results that
  are stable or very unlikely to change. For snapshot tests that record
  structured debugging output, derive `Debug` and use `debug_inspect`, rather
  than deriving `Show` for debugging. For solid, well-defined results (e.g.
  scientific computations), prefer assertion tests. You can use
  `moon coverage analyze > uncovered.log` to see which parts of your code are
  not covered by tests.

## Testing components

There is no `tutuca test` command and no ported `expect`/`describe` layer — the
original JS runner (`tools/core/test.js`) and chai/jest matchers
(`src/chai-jest.js`) exist only because JS lacked a capable native runner.
**`moon test` is the runner**, and MoonBit's built-in assertions cover the whole
jest surface. Author component tests as plain `moon test "..." { ... }` blocks:

- Mount and drive a `ModuleDef` on the in-memory DOM with the reusable harness
  `marianoguerra/tutuca/testing/harness` (`@harness`): `mount` / `mount_example`
  → a live app, then `click` / `type_into` / `key_down` / `drag` / `send_at_root`
  fire real events through the transactor, and `text` / `texts` / `attr` / `prop`
  / `value_of` / `html` / `render_count` / `drive_value` read the re-rendered DOM
  and settled root value back. See `testing/harness/harness_test.mbt` for the
  shape; the `storybook/examples/*_test.mbt` suite is the worked reference.
- A **card** — the `.html` the browser compiles to a wasm module with no MoonBit
  toolchain — has no `moon test` to run and no MoonBit to write a test in, so it
  declares its tests as a fifth block: `<script type="tutuca/test">`, JSON, in
  the shape `tutuca/init` already has. `scenedef/` parses it (target-agnostic,
  so its error messages are `moon test`-able), `viewfile` lifts and validates it
  at split time so a mistake lands on the line of the `.html`, and
  `tutucard/drive/` mounts the card on memdom and runs the steps through
  `@harness`'s own verbs. It reaches a page as `__tutucard.drive` (the ninth
  entry point, beside `check` / `compile` / `mountCompiled`) and `driveCard` in
  `tutucard/web/card-wasm.js`; the playground's Tests pane and
  `tutucard/build/run-tests.mjs` are the two callers. `gen-views` ignores the
  block, exactly as it ignores `tutuca/wax`.
- Assert with the built-ins — no matcher DSL needed. JS → MoonBit mapping:

  | chai/jest | MoonBit built-in |
  |---|---|
  | `toBe` (identity) | `@test.assert_same_object` / `assert_not_same_object` |
  | `toBe` / `toEqual` (value; `Eq` **is** deep-equal) | `assert_eq` / `assert_not_eq` |
  | `toThrow` | `@test.assert_raise` (or `expect_error` to inspect the error) |
  | `toBeInstanceOf` | `assert_true(v is Obj(_))` — pattern match, no runtime classes |
  | `toBeNull` / `toBeUndefined` | `assert_true(v is Null)` (Value) / `x is None` (Option) |
  | `toBeTruthy` / `toBeFalsy` | `assert_true` / `assert_false`; `v.is_truthy()` for a Value |
  | `toContain` / `toHaveLength` | `assert_true(xs.contains(x))` / `assert_eq(xs.length(), n)` |
  | snapshot | `inspect(x, content=..)` / `debug_inspect(x, content=..)` |

  `tutuca.Value` already derives `Eq + Debug`, so `assert_eq` and `debug_inspect`
  work on values directly. `--bail` and per-component filtering have no direct
  equivalent — organize by `moon test` block names and files.
