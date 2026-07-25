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
  stay reproducible. (`cli/skill_assets_gen.mbt` is the exception: it is NOT
  fmt-stable, so revert it after a `moon fmt` and regenerate through
  `skill-embed`. Since `gen-views` and `fmt` both end in `moon fmt`, run
  `skill-embed` after either of them before checking for drift.)

- The guest binding trees under `guests/counter/` and `guests/todo/` are
  generated and checked in the same way, by `gen-guest-bindings`, from the ONE
  WIT in the repo (`dyncomp/wit/tutuca-component.wit` — no guest keeps a copy,
  and the Rust guest's `generate!` macro reads it too). `wit-bindgen`'s raw
  output has to be normalized before it can be checked in meaningfully: it
  emits its FFI shims in HASH order, which differs between two runs on the
  same input. `guests/gen-bindings.mjs` sorts them (MoonBit `///|` blocks are
  order-irrelevant) and drops the `moon.pkg.json` twins of the hand-maintained
  package files, which is what makes the drift check honest. The handwritten
  files in those trees (`sdk.mbt`, `counter.mbt`, `todo.mbt`) have names
  wit-bindgen never emits, so regeneration leaves their contents alone.

## Tooling

### Task runner (`cmd/dev`)

Common workflows are collected in a MoonBit task runner instead of loose
commands. It is the single place tasks live (the `dev/` package holds the task
list; `cmd/dev` is the native shell that runs it):

```
moon run --target native cmd/dev -- <task>
```

| Task       | Does                                                              |
|------------|------------------------------------------------------------------|
| `check`    | `moon check` for default, js and native targets                  |
| `fmt`      | `moon fmt` then `moon info` (format + regenerate `.mbti`)         |
| `test`     | `moon test` for default, native, and js browser adapters         |
| `build`    | `moon build` for wasm-gc, native CLI, and js                     |
| `coverage` | `moon coverage analyze`                                           |
| `setup`    | `npm install` (happy-dom for js tests) + enable the git hooks    |
| `ci`       | `check` then `test`                                              |
| `dist`     | build all targets and assemble a self-contained runnable `dist/` |
| `gen-views` | regenerate the checked-in `*_view_gen.mbt` from their `.html` sources (`viewgen/`); formats after generating, so follow with `git diff --exit-code` to catch drift |
| `gen-guest-bindings` | regenerate the checked-in MoonBit guest bindings (`guests/counter`, `guests/todo`) from the ONE WIT (`dyncomp/wit/tutuca-component.wit`), then drift-check them |
| `skill-embed` | regenerate `cli/skill_assets_gen.mbt` from `skill/tutuca/` (the embedded assets `tutuca install-skill` writes out; `dist` runs it first) |
| `css-bundle` | regenerate `css/{tailwind,margaui}_bundle_gen.mbt` from the pinned `tailwindcss` npm release + a margaui clone (needs network); see "Styling" below |

While editing views, `tutuca watch [path…]` regenerates them on every save
(mizchi/fswatch; native only, since the watcher is the shell's job). It
manages the `.html` files that already have a generated sibling, so pointing
it at a project root does not try to compile `index.html`.

The `playground` task ends with `playground/build/check-viewgen-tab.mjs`: the
View tab generates a MoonBit module in the browser and feeds it to the
in-browser compiler, and nothing else exercises that path — the generated
module compiles in a package with no `moon.pkg`, where `@tutuca` is the
module-root facade rather than `core/`. It drives generate → compile → link
headlessly against the assembled payload, for the standalone playground's
starter AND every landing-site example pair
(`playground/site/examples/<name>.{mbt,html}`, which the embedded
`<mb-playground>` elements compile in a visitor's browser). The cheaper
`check-examples` task covers the same examples through `moon check` instead,
generating their views with the same generator built to js.

`dist` produces `dist/index.html` (a landing page with run instructions),
`dist/counter/` (the **js** counter demo with its bundle, `<script src>`
repointed to sit beside the page), `dist/counter-wasm/` + `dist/universal/`
(the **wasm-gc** demos — each a `.wasm` plus a shared loader and host page),
`dist/storybook/` (the storybook
gallery compiled to wasm-gc — the bundle `tutuca storybook` serves),
`dist/playground/` + `dist/site/`, and
`dist/cli/tutuca` (the native CLI binary). The wasm pages need a browser with
the JS String Builtins proposal, e.g. Chrome. Serve dist with any static file
server: `cd dist && python3 -m http.server` — or `dist/cli/tutuca storybook`
serves `dist/storybook/` over HTTP (default port 4321). `dist/` is gitignored.
Run with no task to print the task list.

The wasm demos are driven by the `vdom/wasm` + `app/wasm` packages (the wasm-gc
twins of `vdom/browser` + `app/browser`): the DOM is reached from wasm-gc
through mizchi/js's `@core.Any` plus a small `tdom` FFI, and — since MoonBit
closures can't cross into JS on wasm-gc — JS calls the exported `on_event` on
each DOM event instead of receiving a closure. `demo/counter_wasm`,
`demo/universal_wasm`, and `demo/storybook_wasm` are the wasm-gc hosts
(`demo/counter_wasm` is the twin of the js `demo/counter`; `storybook_wasm`
mounts the `storybook/ui` gallery over the whole example registry, and
`universal_wasm` hosts the dyncomp guest bundles). margaui styling is compiled
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

**Take `tw/*.css` from npm, never from the margaui checkout.** margaui's own
`tw/README.md` calls its copies a manual mirror and they lag — at v0.5606.3 they
were still missing the `mauve`/`olive`/`mist`/`taupe` palettes upstream added in
4.3.2. The compiler is ported from one exact tag
(`.mooncakes/marianoguerra/tailwindcss/UPSTREAM.md`), so the stylesheets must
come from that tag or the engine and its data disagree; `fetch-tailwind.mjs`
fails the build if the two pins drift apart. `compile_margaui` merges both maps,
so margaui resolves its `./tw/*` imports against the good copies.

`tutuca gen-tailwind-css` / `gen-margaui-css` are the build-time face of the same
pipeline: the class collection a host does at mount time, run over a project's
view files instead, so an AOT project can ship a static stylesheet.

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
  (vdom/browser, app/browser, demo/counter — happy-dom based)
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
