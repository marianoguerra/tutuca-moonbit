///|
/// How many times each stage runs per corpus per process. Enough work that a
/// 1ms sampling interval gets a dense profile, small enough that a run stays
/// well under a second.
const ROUNDS = 10

///|
fn main {
  for corpus in @benchmarks.corpora {
    let (corpus_name, source) = corpus
    for stage in @benchmarks.stages {
      let (name, run) = stage
      let mut sum = 0
      for _ in 0..<ROUNDS {
        sum = sum + run(source)
      }
      println("\{corpus_name}\t\{name}\t\{sum / ROUNDS}")
    }
  }
}
