# benchmarks — view pipeline

Performance benchmarks for the ahead-of-time view compiler (`viewgen/`, and
`anode/` + the vendored HTML parser under it). Repo tooling: excluded from
`moon package`, not part of the published library.

## The workload

`all_views.html` is a synthetic view file: **every view `.html` in the repo
concatenated into one**, with each file's component names prefixed so nothing
collides (`storybook/examples/json.html`'s `JsonArray` becomes `SbJsonJsonArray`,
`playground/site/examples/json.html`'s becomes `SiteJsonJsonArray`). A file whose
single component is unnamed — a bare `<template>` — becomes that prefix's `main`
view. 36 source files, 108 views, ~58 KB.

`all_views_gen.mbt` is the same text as a MoonBit string, so the bench needs no
filesystem and runs on every backend. Both are generated and checked in:

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

Four stages, matching what `tutuca gen-views` does:

| Stage     | What it runs                                                   |
|-----------|----------------------------------------------------------------|
| `split`   | `split_file` — tokenize the file, slice out each view's source  |
| `surface` | `split` + `view_surface` — parse every view, extract its types  |
| `build`   | `split` + `build_views` — parse every view into a compiled tree |
| `gen`     | the whole CLI job: `split` + both emitted modules               |

`split` is included in the other three because they need it; subtract it for a
stage's own cost. `viewparse_bench_test.mbt` also pins the workload's size and
two output checksums, so a change that alters generated output fails the test
rather than silently invalidating a comparison.

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
