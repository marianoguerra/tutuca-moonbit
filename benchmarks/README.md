# benchmarks — view pipeline

Performance benchmarks for the ahead-of-time view compiler (`viewgen/`, and
`anode/` + the vendored HTML parser under it). Repo tooling: excluded from
`moon package`, not part of the published library.

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

## Running it

```
moon run --target native cmd/dev -- bench            # just bench
moon bench --release benchmarks                      # wasm-gc only
moon bench --release --target native benchmarks
```

Four stages per corpus, matching what `tutuca gen-views` does:

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

See [OPTIMIZATIONS.md](OPTIMIZATIONS.md) for the measured changes.
