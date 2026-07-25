// Per-stage timings for the view pipeline over benchmarks/all_views.html.
//
//   moon bench --release benchmarks              (default target)
//   moon bench --release --target native benchmarks
//
// The stage functions live in viewparse.mbt so benchmarks/cmd/viewparse can run
// the same workload under a profiler.

///|
test "bench viewgen split (108 views)" (it : @bench.T) {
  it.bench(() => it.keep(@benchmarks.split()))
}

///|
test "bench viewgen surface (108 views)" (it : @bench.T) {
  it.bench(() => it.keep(@benchmarks.surface()))
}

///|
test "bench viewgen build (108 views)" (it : @bench.T) {
  it.bench(() => it.keep(@benchmarks.build()))
}

///|
test "bench viewgen gen (108 views)" (it : @bench.T) {
  it.bench(() => it.keep(@benchmarks.gen()))
}

///|
/// The workload is only meaningful while it stays the whole repo's views and
/// keeps generating the same output; these pin both.
test "workload shape" {
  inspect(@benchmarks.all_views.length(), content="58493")
  inspect(@benchmarks.build(), content="107")
  inspect(@benchmarks.gen(), content="498106")
}
