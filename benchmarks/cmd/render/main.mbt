///|
/// How many times each workload runs per process. The 1000-row updates are tens
/// of milliseconds each, so a handful is already a dense profile.
const ROUNDS = 5

///|
fn main {
  for
    group in [
      ("render", @benchmarks.render_workloads()),
      ("patch", @benchmarks.patch_workloads()),
    ] {
    let (kind, workloads) = group
    for w in workloads {
      let (name, run) = w
      // The last value, not the mean: an update workload's witness is the
      // app's render count, which grows with every round.
      let mut last = 0
      for _ in 0..<ROUNDS {
        last = run()
      }
      println("\{kind}\t\{name}\t\{last}")
    }
  }
}
