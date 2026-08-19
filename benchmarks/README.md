# benchmarks

Performance benchmarks for tutuca, in four suites:

| Suite       | Measures                                              | Files |
|-------------|-------------------------------------------------------|-------|
| view        | the ahead-of-time view compiler (`viewgen/`, `anode/` and the vendored HTML parser under it) | `viewparse.mbt`, `scaling_bench_test.mbt` |
| render      | mounting a component tree and rendering it the first time | `render.mbt` |
| diff/patch  | changing a mounted app: re-render, diff, patch         | `patch.mbt` |
| dispatch    | routing a message: an intent's walk per hop, and what a name nobody answers costs | `intent.mbt` |

Repo tooling: excluded from `moon package`, not part of the published library.

```
moon run --target native cmd/dev -- bench      # everything, both targets
node benchmarks/report.mjs [--target native] [--file <bench_test.mbt>]
```

`report.mjs` runs `moon bench` and collapses its three lines per benchmark into
one. `--save before.json` then `--baseline before.json` is the A/B loop:

```
node benchmarks/report.mjs --target native --save /tmp/before.json
# ...make the change...
node benchmarks/report.mjs --target native --baseline /tmp/before.json
```

Known-noisy benches, not to be used for judging a change: `render all examples`
(±13–26%), `render json 3x4` (±31–38%) and the whole `intent dyn depth *` row
(±13–58%, and it measures a render that grows with the same parameter as the
walk — see OPTIMIZATIONS.md #14 for what those rows do and do not establish).
Everything else lands under ±5%.

---

# The view suite

## The workloads

Two corpora, same nodes, opposite shapes — so a cost that is per-view shows up
in one and a cost that scales with a view's size shows up in the other.

**`all_views.html` — 108 small views.** Every view `.html` in the repo
concatenated into one view *file*, with each file's component names prefixed so
nothing collides (`storybook/examples/json.html`'s `JsonArray` becomes
`SbJsonJsonArray`, `playground/site/examples/json.html`'s becomes
`SiteJsonJsonArray`). A file whose single component is unnamed — a bare
`<template>` — becomes that prefix's `main` view. 36 source files, 108 views,
~58 KB.

**`one_big_view.html` — one enormous view.** Every one of those views' *bodies*
inside a single `<template>`: 107 bodies, ~55 KB, one tree.

`corpus_gen.mbt` holds both as MoonBit strings (the second as its body, which
`@benchmarks.giant_view(n)` wraps once or n times over), so the bench needs no
filesystem and runs on every backend. Everything here is generated and checked
in:

```
moon run --target native cmd/dev -- bench-views     # just bench-views
```

Two things about the concatenation are not faithful to compiling the files
separately, neither of which matters for a parser benchmark: file-level
`<style>` elements all land on the *first* component (that is what `split_file`
does with them), and a source file with no `<template>` at all would be wrapped
in one — currently none are.

## The stages

Four per corpus, matching what `tutuca gen-views` does:

| Stage     | What it runs                                                   |
|-----------|----------------------------------------------------------------|
| `split`   | `split_file` — tokenize the file, slice out each view's source  |
| `surface` | `split` + `view_surface` — parse every view, extract its types  |
| `build`   | `split` + `build_views` — parse every view into a compiled tree |
| `gen`     | the whole CLI job: `split` + both emitted modules               |

`split` is included in the other three because they need it; subtract it for a
stage's own cost.

`scaling_bench_test.mbt` adds a third axis: `build` over one view holding 1×, 2×
and 4× every view body. Perfectly linear is 1 : 2 : 4, and the ratio is what to
watch — that is how the quadratic term in `slice_without_styles` surfaced.

Both bench files pin their corpus size and output checksums, so a change that
alters generated output fails a test rather than silently invalidating a
comparison.

## Profiling

`benchmarks/cmd/viewparse` is an argv-free, filesystem-free shell that runs each
stage `ROUNDS` times and prints its checksum — a profiler drives repetition.

```
# wasm-gc under wasmtime + GuestProfiler (needs --no-strip for symbol names).
# Note wasmtime runs this ~50× slower than native, so one iteration is plenty.
moon build --target wasm-gc --release --no-strip benchmarks/cmd/viewparse
moon-pprof profile _build/wasm-gc/release/build/benchmarks/cmd/viewparse/viewparse.wasm \
  --out /tmp/base.pb.gz --interval-us 500 --iterations 1
moon-pprof summary /tmp/base.pb.gz

# js under V8 — much faster to iterate on, and closest to native's hot-spot
# ranking of the three (the wasmtime profile over-weights string literals).
moon build --target js --release benchmarks/cmd/viewparse
node --cpu-prof --cpu-prof-dir=/tmp/prof --cpu-prof-interval=200 \
  _build/js/release/build/benchmarks/cmd/viewparse/viewparse.js
moon-pprof cpuprofile2pprof /tmp/prof/CPU.*.cpuprofile /tmp/base-js.pb.gz
moon-pprof summary /tmp/base-js.pb.gz

# diff two profiles
moon-pprof summary --diff /tmp/base-js.pb.gz /tmp/patched-js.pb.gz
```

`perf record` on the native binary would be the most representative, but needs
`kernel.perf_event_paranoid <= 2`.

`benchmarks/cmd/render` is the same kind of shell for the render and diff/patch
suites; substitute it for `cmd/viewparse` above.

---

# The render suite

Mounts a component tree as a live app on the in-memory DOM (`@memdom` runs on
every backend, so this stays target-agnostic) via `testing/harness`, then reads
the rendered DOM back. Two axes:

- **feature coverage** — `render all examples` mounts all 50 usable modules in
  `storybook/examples` with the args the storybook and the CLI mount them with.
  Between them they render every view directive the framework has. (The 51st,
  `lint-errors`, exists to be broken: one of its bad values is a `render` op that
  recurses forever.)
- **data size** — the same view over 0, 1, 5, 10, 100 and 1000 items:
  - `list` — `@each` over plain values, no child components (the floor)
  - `todo` — `@each` + `<x render-it>`: every row is its own component
  - `people` — the same list behind `@filter-with` / `@enrich-with` +
    pagination, so the pipeline walks every item while only a page reaches the
    DOM
  - `json` — the JSON editor's array nested into itself, so *depth* grows

The seeded state is built once per size and memoized: building 1000 component
instances costs more than rendering them, and leaving that inside the timed
closure both drowned the signal and made whole samples differ 3×.

---

# The diff/patch suite

The render suite measures the FIRST render. This one measures every one after it:
new state → re-render → diff against the live tree → patch the DOM.

- the app is mounted once, outside the bench, and shared across iterations
- every workload is a **round trip** (a change and the change back), so a shared
  app never drifts — each number is *two* diff+patch passes
- `patch_test.mbt` asserts each round trip restores the DOM it started from, so
  the sharing is checked rather than assumed
- the witness is `render_count()`, an Int, not the serialized DOM — serializing a
  1000-row list costs several times the patch being measured

Ordered by how much of the tree the change touches:

| Workload      | Change                                                      |
|---------------|-------------------------------------------------------------|
| `noop`        | set a checkbox to the value it already has — the differ walks, the DOM is untouched |
| `counter`     | one text node                                               |
| `toggle`      | one row's attributes                                        |
| `add+remove`  | append a row, drop the first: same length, rotated by one    |
| `move`        | drag a row two places and back — nodes move, not change      |
| `page`        | a page of rows replaced by different ones                    |
| `refilter`    | a query change: the pipeline re-runs over every item         |
| `switch view` | a whole component subtree leaves and another arrives         |

The in-memory DOM is the point, not a limitation: `@memdom`'s primitives are
array splices with no layout, style or event system behind them, so what is left
is tutuca's own diff and patch. Two things about the setup are worth knowing:

- **Harness overhead is measured, not assumed.** Each dispatched event resolves a
  selector first. `Harness::find` now stops at the match it wants instead of
  collecting every one, which cut these numbers by 30–78%; the `find …` benches
  time the remaining walk alone so it can be subtracted (5.5 µs for `.checkbox`
  on a 1000-row list, 38 µs for `.next`, which sits after the list).
- **`memdom` removal is O(children), where a real DOM is O(1).** Children are an
  `Array`, so both the index scan in `detach` and the splice are linear. It
  inflates move-heavy patches; see OPTIMIZATIONS.md's open list.

See [OPTIMIZATIONS.md](OPTIMIZATIONS.md) for the baselines and the measured
changes.
