// Timings for the render path: mount a component tree on the in-memory DOM,
// render it, serialize it.
//
//   node benchmarks/report.mjs --file render_bench_test.mbt [--target native]
//
// The workload functions live in render.mbt so benchmarks/cmd/viewparse can run
// the same set under a profiler. Update cost is patch_bench_test.mbt.

///|
test "bench render all examples" (it : @bench.T) {
  it.bench(() => it.keep(@benchmarks.render_all_examples()))
}

///|
test "bench render list 0" (it : @bench.T) {
  it.bench(() => it.keep(@benchmarks.render_list(0)))
}

///|
test "bench render list 10" (it : @bench.T) {
  it.bench(() => it.keep(@benchmarks.render_list(10)))
}

///|
test "bench render list 100" (it : @bench.T) {
  it.bench(() => it.keep(@benchmarks.render_list(100)))
}

///|
test "bench render list 1000" (it : @bench.T) {
  it.bench(() => it.keep(@benchmarks.render_list(1000)))
}

///|
test "bench render todo 0" (it : @bench.T) {
  it.bench(() => it.keep(@benchmarks.render_todo(0)))
}

///|
test "bench render todo 1" (it : @bench.T) {
  it.bench(() => it.keep(@benchmarks.render_todo(1)))
}

///|
test "bench render todo 5" (it : @bench.T) {
  it.bench(() => it.keep(@benchmarks.render_todo(5)))
}

///|
test "bench render todo 10" (it : @bench.T) {
  it.bench(() => it.keep(@benchmarks.render_todo(10)))
}

///|
test "bench render todo 100" (it : @bench.T) {
  it.bench(() => it.keep(@benchmarks.render_todo(100)))
}

///|
test "bench render todo 1000" (it : @bench.T) {
  it.bench(() => it.keep(@benchmarks.render_todo(1000)))
}

///|
test "bench render people 10" (it : @bench.T) {
  it.bench(() => it.keep(@benchmarks.render_people(10)))
}

///|
test "bench render people 100" (it : @bench.T) {
  it.bench(() => it.keep(@benchmarks.render_people(100)))
}

///|
test "bench render people 1000" (it : @bench.T) {
  it.bench(() => it.keep(@benchmarks.render_people(1000)))
}

///|
test "bench render json 3x4" (it : @bench.T) {
  it.bench(() => it.keep(@benchmarks.render_json(3, 4)))
}

///|
test "bench render json 8x4" (it : @bench.T) {
  it.bench(() => it.keep(@benchmarks.render_json(8, 4)))
}

///|
/// Rendered-HTML length at each size. Every workload has to actually render
/// something, and keep rendering the same thing: a mount that silently produced
/// an empty DOM would make a fast but meaningless benchmark.
fn at_sizes(f : (Int) -> Int) -> String {
  @benchmarks.sizes.map(n => f(n).to_string()).join(" ")
}

///|
test "render workload shape" {
  inspect(
    at_sizes(@benchmarks.render_list),
    content=(
      #|125 202 510 895 8095 82795
    ),
  )
  inspect(
    at_sizes(@benchmarks.render_todo),
    content=(
      #|254 679 2379 4504 42844 427144
    ),
  )
  // Pagination bounds what SharedPeople renders, so past one page the DOM stops
  // growing while the filter pipeline still walks every item — which is the
  // point of having this one alongside the unpaginated lists.
  inspect(
    at_sizes(@benchmarks.render_people),
    content=(
      #|549 1201 3819 3820 3822 3824
    ),
  )
  inspect(
    @benchmarks.render_json(3, 4),
    content=(
      #|10424
    ),
  )
  inspect(
    @benchmarks.render_json(8, 4),
    content=(
      #|23849
    ),
  )
  inspect(
    @benchmarks.render_all_examples(),
    content=(
      #|65964
    ),
  )
}
