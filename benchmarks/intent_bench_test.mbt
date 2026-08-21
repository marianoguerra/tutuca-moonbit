// Timings for dispatch: what a walk costs per hop, and what a name nobody
// answers costs.
//
//   node benchmarks/report.mjs --file intent_bench_test.mbt [--target native]
//
// Every app is mounted once here and reused, so what is timed is the dispatch
// and not the mount. The DEPTHS are powers of four so the ratio between two
// rows reads straight off: 4× the hops should be about 4× the walk, and a
// number that grows faster than that is the thing this file exists to catch.
//
// The `lex` row stops at 48 rather than 64 because `INTENT_DEPTH` is 64 and it
// counts HOPS, not legs: 64 declines plus the handler that answers is 65 hops
// and the walk is cut short. `intent_test.mbt` pins that boundary; here it is
// just the reason the last row is not a power of four.

///|
let chain_1 : @harness.MemHarness = @benchmarks.mount_tree_chain(1)

///|
let chain_4 : @harness.MemHarness = @benchmarks.mount_tree_chain(4)

///|
let chain_16 : @harness.MemHarness = @benchmarks.mount_tree_chain(16)

///|
let chain_64 : @harness.MemHarness = @benchmarks.mount_tree_chain(64)

///|
let lex_0 : @harness.MemHarness = @benchmarks.mount_lex_chain(0)

///|
let lex_4 : @harness.MemHarness = @benchmarks.mount_lex_chain(4)

///|
let lex_16 : @harness.MemHarness = @benchmarks.mount_lex_chain(16)

///|
let lex_48 : @harness.MemHarness = @benchmarks.mount_lex_chain(48)

///|
let answered : @harness.MemHarness = @benchmarks.mount_counter()

///|
let unanswered : @harness.MemHarness = @benchmarks.mount_counter()

// --- the `dyn` leg: one hop per ancestor ------------------------------------

///|
test "bench intent dyn depth 1" (it : @bench.T) {
  it.bench(() => it.keep(@benchmarks.intent_dyn(chain_1, 1)))
}

///|
test "bench intent dyn depth 4" (it : @bench.T) {
  it.bench(() => it.keep(@benchmarks.intent_dyn(chain_4, 4)))
}

///|
test "bench intent dyn depth 16" (it : @bench.T) {
  it.bench(() => it.keep(@benchmarks.intent_dyn(chain_16, 16)))
}

///|
test "bench intent dyn depth 64" (it : @bench.T) {
  it.bench(() => it.keep(@benchmarks.intent_dyn(chain_64, 64)))
}

// --- the selector walk that finds the element, for subtracting ---------------

///|
test "bench intent dyn find 64" (it : @bench.T) {
  it.bench(() => it.keep(@benchmarks.find_cost(chain_64, ".head")))
}

// --- the `lex` leg: one hop per DECLINING handler ---------------------------

///|
test "bench intent lex declines 0" (it : @bench.T) {
  it.bench(() => it.keep(@benchmarks.intent_lex(lex_0)))
}

///|
test "bench intent lex declines 4" (it : @bench.T) {
  it.bench(() => it.keep(@benchmarks.intent_lex(lex_4)))
}

///|
test "bench intent lex declines 16" (it : @bench.T) {
  it.bench(() => it.keep(@benchmarks.intent_lex(lex_16)))
}

///|
test "bench intent lex declines 48" (it : @bench.T) {
  it.bench(() => it.keep(@benchmarks.intent_lex(lex_48)))
}

// --- stop-by-default: a name nobody answers ---------------------------------

///|
test "bench dispatch answered" (it : @bench.T) {
  it.bench(() => it.keep(@benchmarks.dispatch_answered(answered)))
}

///|
test "bench dispatch unanswered" (it : @bench.T) {
  it.bench(() => it.keep(@benchmarks.dispatch_unanswered(unanswered)))
}
