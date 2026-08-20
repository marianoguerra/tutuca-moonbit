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
  inspect(
    @benchmarks.all_views.length(),
    content=(
      #|62030
    ),
  )
  inspect(
    @benchmarks.build(@benchmarks.all_views),
    content=(
      #|108
    ),
  )
  inspect(
    @benchmarks.gen(@benchmarks.all_views),
    content=(
      #|315952
    ),
  )
  inspect(
    @benchmarks.gen(giant_1x),
    content=(
      #|140915
    ),
  )
}

///|
/// The corpora must PARSE, checked by a plain test rather than only by the
/// benches above.
///
/// `moon test` does not execute a `bench` body, so a corpus that no longer
/// splits fails only under `moon bench` — which is not what CI runs. Both
/// corpora were silently unusable for exactly that reason once view files
/// started carrying schema blocks: `all_views` concatenates every view file,
/// and 36 schemas in one file is not a view file, while a `<template>`
/// written inside a schema COMMENT was taken for an opening tag.
test "both corpora still split" {
  let many = @viewgen.split_file(@benchmarks.all_views)
  assert_true(many.components.length() > 50)
  // A schema block is WIT, not markup: the corpus builder strips it, so no
  // schema survives the concatenation to be parsed as a second one.
  assert_eq(many.state.length(), 0)
  let giant = @viewgen.split_file(@benchmarks.giant_view(1))
  assert_eq(giant.components.length(), 1)
}
