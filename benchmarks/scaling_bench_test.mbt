// Is anything in the pipeline superlinear in a SINGLE view's size?
//
// One view holding 1×, 2× and 4× every view body in the repo. Perfectly linear
// would be 1 : 2 : 4; the ratio is the number to watch, not the absolute times.
// Two factors in the pipeline grow together with a view file's size (its length
// and the number of `<style>` elements lifted out of it), so a per-char loop
// that rescans the styles reads as mildly superlinear here — that is how
// slice_without_styles' quadratic term was found.

///|
let giant_1x : String = @benchmarks.giant_view(1)

///|
let giant_2x : String = @benchmarks.giant_view(2)

///|
let giant_4x : String = @benchmarks.giant_view(4)

///|
test "scaling corpus shape" {
  inspect(
    giant_1x.length(),
    content=(
      #|53569
    ),
  )
  inspect(
    giant_2x.length(),
    content=(
      #|107101
    ),
  )
  inspect(
    giant_4x.length(),
    content=(
      #|214165
    ),
  )
  // One view however big, and it stays compilable at every size.
  inspect(@benchmarks.build(giant_1x), content="1")
  inspect(@benchmarks.build(giant_4x), content="1")
}

///|
test "bench scaling 1x" (it : @bench.T) {
  it.bench(() => it.keep(@benchmarks.build(giant_1x)))
}

///|
test "bench scaling 2x" (it : @bench.T) {
  it.bench(() => it.keep(@benchmarks.build(giant_2x)))
}

///|
test "bench scaling 4x" (it : @bench.T) {
  it.bench(() => it.keep(@benchmarks.build(giant_4x)))
}
