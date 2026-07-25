// Per-stage timings for the view pipeline over both corpora in corpus_gen.mbt.
//
//   moon bench --release benchmarks              (default target)
//   moon bench --release --target native benchmarks
//
// The stage functions live in viewparse.mbt so benchmarks/cmd/viewparse can run
// the same workload under a profiler.

///|
test "bench many-views split" (it : @bench.T) {
  it.bench(() => it.keep(@benchmarks.split(@benchmarks.all_views)))
}

///|
test "bench many-views surface" (it : @bench.T) {
  it.bench(() => it.keep(@benchmarks.surface(@benchmarks.all_views)))
}

///|
test "bench many-views build" (it : @bench.T) {
  it.bench(() => it.keep(@benchmarks.build(@benchmarks.all_views)))
}

///|
test "bench many-views gen" (it : @bench.T) {
  it.bench(() => it.keep(@benchmarks.gen(@benchmarks.all_views)))
}

///|
test "bench one-big-view split" (it : @bench.T) {
  it.bench(() => it.keep(@benchmarks.split(giant_1x)))
}

///|
test "bench one-big-view surface" (it : @bench.T) {
  it.bench(() => it.keep(@benchmarks.surface(giant_1x)))
}

///|
test "bench one-big-view build" (it : @bench.T) {
  it.bench(() => it.keep(@benchmarks.build(giant_1x)))
}

///|
test "bench one-big-view gen" (it : @bench.T) {
  it.bench(() => it.keep(@benchmarks.gen(giant_1x)))
}

///|
/// A workload is only meaningful while it stays the whole repo's views and keeps
/// generating the same output; these pin size and output for both corpora
/// (scaling_bench_test.mbt pins the same for the giant view it shares).
test "workload shape" {
  inspect(@benchmarks.all_views.length(), content="58476")
  inspect(@benchmarks.build(@benchmarks.all_views), content="107")
  inspect(@benchmarks.gen(@benchmarks.all_views), content="497695")
  inspect(@benchmarks.gen(giant_1x), content="140912")
}
