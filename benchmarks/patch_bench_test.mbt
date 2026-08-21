// Timings for diff + patch: an app is mounted once here, and each bench applies
// a change and the change back to it.
//
//   node benchmarks/report.mjs --file patch_bench_test.mbt [--target native]
//
// Every number is TWO diff+patch passes (there and back), over a warm app — the
// steady-state cost of an interaction, not the first one. Ordered by how much of
// the tree the change touches.

///|
let todo_10 : @harness.MemHarness = @benchmarks.mount_todo(10)

///|
let todo_100 : @harness.MemHarness = @benchmarks.mount_todo(100)

///|
let todo_1000 : @harness.MemHarness = @benchmarks.mount_todo(1000)

///|
let noop_10 : @harness.MemHarness = @benchmarks.mount_todo(10)

///|
let noop_1000 : @harness.MemHarness = @benchmarks.mount_todo(1000)

///|
let add_10 : @harness.MemHarness = @benchmarks.mount_todo(10)

///|
let add_100 : @harness.MemHarness = @benchmarks.mount_todo(100)

///|
let add_1000 : @harness.MemHarness = @benchmarks.mount_todo(1000)

///|
let counter : @harness.MemHarness = @benchmarks.mount_counter()

///|
let people_100 : @harness.MemHarness = @benchmarks.mount_people(100)

///|
let people_1000 : @harness.MemHarness = @benchmarks.mount_people(1000)

///|
let page_1000 : @harness.MemHarness = @benchmarks.mount_people(1000)

///|
let json_8x4 : @harness.MemHarness = @benchmarks.mount_json(8, 4)

///|
let tabs : @harness.MemHarness = @benchmarks.mount_tabs()

// --- no change at all -------------------------------------------------------

///|
test "bench patch noop todo 10" (it : @bench.T) {
  it.bench(() => it.keep(@benchmarks.patch_noop(noop_10)))
}

///|
test "bench patch noop todo 1000" (it : @bench.T) {
  it.bench(() => it.keep(@benchmarks.patch_noop(noop_1000)))
}

// --- one node ---------------------------------------------------------------

///|
test "bench patch counter" (it : @bench.T) {
  it.bench(() => it.keep(@benchmarks.patch_counter(counter)))
}

///|
test "bench patch toggle todo 10" (it : @bench.T) {
  it.bench(() => it.keep(@benchmarks.patch_toggle(todo_10)))
}

///|
test "bench patch toggle todo 100" (it : @bench.T) {
  it.bench(() => it.keep(@benchmarks.patch_toggle(todo_100)))
}

///|
test "bench patch toggle todo 1000" (it : @bench.T) {
  it.bench(() => it.keep(@benchmarks.patch_toggle(todo_1000)))
}

// --- the list changes shape -------------------------------------------------

///|
test "bench patch add+remove todo 10" (it : @bench.T) {
  it.bench(() => it.keep(@benchmarks.patch_add_remove(add_10)))
}

///|
test "bench patch add+remove todo 100" (it : @bench.T) {
  it.bench(() => it.keep(@benchmarks.patch_add_remove(add_100)))
}

///|
test "bench patch add+remove todo 1000" (it : @bench.T) {
  it.bench(() => it.keep(@benchmarks.patch_add_remove(add_1000)))
}

///|
test "bench patch move json 8x4" (it : @bench.T) {
  it.bench(() => it.keep(@benchmarks.patch_move(json_8x4)))
}

///|
test "bench patch page people 1000" (it : @bench.T) {
  it.bench(() => it.keep(@benchmarks.patch_page(page_1000)))
}

// --- every rendered row changes ---------------------------------------------

///|
test "bench patch refilter people 100" (it : @bench.T) {
  it.bench(() => it.keep(@benchmarks.patch_refilter(people_100)))
}

///|
test "bench patch refilter people 1000" (it : @bench.T) {
  it.bench(() => it.keep(@benchmarks.patch_refilter(people_1000)))
}

// --- a whole subtree is replaced --------------------------------------------

///|
test "bench patch switch view" (it : @bench.T) {
  it.bench(() => it.keep(@benchmarks.patch_switch_view(tabs)))
}

// --- what the harness costs, so it can be subtracted ------------------------

///|
test "bench find .checkbox todo 1000" (it : @bench.T) {
  it.bench(() => it.keep(@benchmarks.find_cost(todo_1000, ".checkbox")))
}

///|
test "bench find .next people 1000" (it : @bench.T) {
  it.bench(() => it.keep(@benchmarks.find_cost(page_1000, ".next")))
}
