# Project Agents.md Guide

This is a [MoonBit](https://docs.moonbitlang.com) project — a port of
[tutuca](https://github.com/marianoguerra/tutuca), a JS UI framework.

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

- **The repo reads as a first release.** There is no backward compatibility to
  keep, no retired spelling still accepted, and no alias kept for a name that
  moved — rename the thing and fix every caller. Prose follows the same rule:
  documentation and comments describe what is true now, not what changed. The
  CHANGELOG is where history lives, and it is the only place.

- **A diagnostic names the repair, not just the verdict.** "does not conform" is
  something the reader has to go and derive; the spelling to write instead is
  what they needed. Tests assert on the MESSAGE, not the code — a code is a
  constant and stays green while the sentence beside it rots.

- MoonBit code is organized in block style, each block is separated by `///|`,
  the order of each block is irrelevant. In some refactorings, you can process
  block by block independently.

- Files named `*_gen.mbt` are GENERATED and checked in; never hand-edit one.
  Change its source and rerun the task that produces it (`gen` for a
  `*_view_gen.mbt` from its `.html`; `skill-embed` for
  `cli/skill_assets_gen.mbt` from `skill/tutuca/`). Each generating task ends
  in `moon fmt`, so what is checked in is already what fmt produces and a
  later `moon fmt` leaves it alone — run the task, not the CLI directly.

- `tgc/` has two documents: `SPEC.md` is the format — the frozen rec group, the
  freeze rule, the op space, the exports, the encoding — and `SECURITY.md` is
  what a loaded module can and cannot do, with the evidence for each claim.
  **The rec group in `tgc/abi/preamble.mbt` is frozen**: a group's identity
  depends on the whole group, so touching it breaks every module ever built.
  Extension goes through `tg_ext` and the `i32` op space. Changing anything in
  `tgc/` means checking `SECURITY.md`'s "What to check when changing this".

- `examples/*` are not packages of this module and not demos. Each is a
  CONSUMER: its own `moon.mod` depending on the PUBLISHED `marianoguerra/tutuca`
  fetched from mooncakes like anyone else's, so `moon check` / `moon fmt` / `ci`
  never reach them and each builds only through its own `build.mjs`. **An
  example must never gain a path dependency, a `../` out of its own directory,
  or a step that runs anything from this repo** — proving a release is complete
  on its own is the one thing they do, and any of those would quietly stop
  proving it. `examples/README.md` and CONTRIBUTING.md's release section are the
  rest.

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

| Task | Does |
|---|---|
| `ci` | what CI runs: every drift check, then `check`, the example/skill/card checks, `test` and `build` |
| `dist` | build all targets and assemble a self-contained runnable `dist/` |
| `check` / `test` / `build` | across wasm-gc, js and native |
| `fmt` | `moon fmt` then `moon info` — format and regenerate every `.mbti` |
| `gen` | regenerate the checked-in `*_view_gen.mbt` from their `.html` sources, then drift-check them. A stale one type-checks and tests green, which is why the check exists |
| `setup` | `npm install` (happy-dom for js tests) + enable the git hooks |

**That is the whole table, deliberately.** `cmd/dev` with no task prints every
task with what it does, generated from the same list that runs them, so a task
added without touching this file is still discoverable. A table here is a second
list, and the second list is the one that goes stale.

Two tasks worth knowing about before you need them: `test` caps its native leg
with `-j` (it links a whole-program binary per test package and the biggest
`moonc` peaks near 1.8 GB, so moon's one-job-per-core default OOMs a small box —
see `NATIVE_TEST_JOBS` in `dev/tasks.mbt`), and the four regenerate-from-upstream
tasks need the network, so they are not in `ci` — see `css/README.md`.

While editing views, `tutuca watch [path…]` regenerates them on every save
(mizchi/fswatch; native only, since the watcher is the shell's job). It
manages the `.html` files that already have a generated sibling, so pointing
it at a project root does not try to compile `index.html`. Add
`--tailwind-css`/`--margaui-css <file>` and it rewrites that stylesheet too,
once per settled batch over every watched view.

Three checks are worth knowing exist, each documented in its own script's
header: `playground/build/check-viewgen-tab.mjs` drives generate → compile →
link headlessly through the in-browser compiler (the only thing that does),
`scripts/check-playground-examples.mjs` covers the same examples through `moon
check`, and `scripts/check-skill-snippets.mjs` compiles the bundled skill's
snippets and checks every identifier in them against the checked-in `.mbti`
files. The last one matters most: the skill ships inside the CLI binary, so a
wrong snippet is what an agent reads before writing any tutuca code.

`dist` assembles a self-contained, runnable tree: the landing page and card
tutorial, the js and wasm-gc counter demos, this repo's storybook gallery, both
playgrounds, and the native CLI binary. `dist_steps` in `dev/tasks.mbt` is the
inventory and says why each piece is copied where it is; `tutucard/README.md`
covers the card half.

The wasm pages need a browser with the JS String Builtins proposal, e.g. Chrome.
Serve it with any static file server (`cd dist && python3 -m http.server`), or
`dist/cli/tutuca storybook` serves the gallery over HTTP. `dist/` is gitignored.

The wasm demos are driven by the `vdom/wasm` + `app/wasm` packages (the wasm-gc
twins of `vdom/browser` + `app/browser`): the DOM is reached from wasm-gc
through mizchi/js's `@core.Any` plus a small `tdom` FFI, and — since MoonBit
closures can't cross into JS on wasm-gc — JS calls the exported `on_event` on
each DOM event instead of receiving a closure. `demo/counter_wasm` and
`demo/storybook_wasm` are the wasm-gc hosts (`demo/counter_wasm` is the twin of
the js `demo/counter`; `storybook_wasm` is the same shape over the
published `storybook/ui/wasm` — an export list and this repo's story set,
nothing else, an export list being per-package `link` config that cannot come
from a dependency).

margaui styling is compiled in MoonBit rather than fetched: a host's `mount()`
hands `collect_classes()` to `css`, injects the resulting `<style
id="margaui-css">`, and re-runs it from `refresh_margaui()` after a module
loads. No CDN build and no `globalThis` class hand-off. **`css/README.md`** is
that pipeline, the two generated bundles behind it, and the rule every
generated-from-upstream table in this repo follows.

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

- Targets: `preferred_target` is `wasm-gc`, so a bare `moon check` / `moon test`
  covers only the target-agnostic packages. Full coverage needs all three, which
  is what the `check` and `test` tasks run: wasm-gc, `--target js` (the
  happy-dom browser adapters `vdom/browser` and `app/browser`, the only packages
  with js-target tests) and `--target native` (the CLI shell). Each target
  surfaces warnings the others don't, so run the task rather than a bare `moon`.

- Prefer `assert_eq` or `assert_true(pattern is Pattern(...))` for results that
  are stable or very unlikely to change. For snapshot tests that record
  structured debugging output, derive `Debug` and use `debug_inspect`, rather
  than deriving `Show` for debugging. For solid, well-defined results (e.g.
  scientific computations), prefer assertion tests. You can use
  `moon coverage analyze > uncovered.log` to see which parts of your code are
  not covered by tests.

## Testing components

`moon test` is the runner — there is no `tutuca test`, and MoonBit's built-ins
cover the whole jest surface. Component tests are ordinary `test { ... }` blocks
over `marianoguerra/tutuca/testing/harness`; a card declares its own as a
`<script type="tutuca/test">` block that `tutucard/drive` runs.

**`skill/tutuca/testing.md` is the reference** — the harness verbs, the scene
language, the assertion mapping, and what a card reports instead of a refusal.
It ships inside the CLI, so it is what an agent reads, and `check-skill` keeps
its snippets compiling. Two repo-internal notes live with their packages
instead: how instances the host holds are collected is in `tgc/host`, and how a
property test derives its generators from a spec block is in `statedef/arb`.
