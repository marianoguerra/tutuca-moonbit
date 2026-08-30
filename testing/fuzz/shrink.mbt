// Making a failure small enough to read.

///|
/// The shortest script that still fails, found by replaying candidates from a
/// fresh mount.
///
/// `remount` is a function rather than a harness because shrinking cannot
/// reuse one: every candidate has to start from the same initial state, and a
/// component driven by the previous candidate is not in it. That is also why
/// this cannot live on `Plan` — a plan knows what to send, not how to get a
/// component to send it to.
///
/// `@arb.shrink_script` supplies the candidates (prefixes and deletions); this
/// decides which of them still count as the same failure. "The same failure"
/// is deliberately loose — ANY broken invariant, not the same rule — because a
/// shorter script that breaks a different invariant is still a better bug
/// report than a longer one, and insisting on the rule tends to keep steps
/// that only exist to reach it.
pub fn[N] shrink(
  plan : Plan,
  script : Array[Action],
  remount : () -> @harness.Harness[N]?,
  at? : @tutuca.DispatchPath = @tutuca.DispatchPath::new(),
  read? : Reader,
  rounds? : Int = 200,
) -> Array[Action] {
  let mut best = script
  let mut budget = rounds
  // Repeat until a pass finds nothing smaller: one pass over the candidates
  // shortens a script, and the shortened one usually has candidates of its
  // own. Bounded by `budget` rather than by trust — a shrinker that does not
  // terminate is worse than one that stops early.
  for ;; {
    let mut improved = false
    for cand in shrink_actions(best) {
      if budget <= 0 {
        break
      }
      budget = budget - 1
      if cand.length() >= best.length() {
        continue
      }
      if still_fails(plan, cand, remount, at, read?) {
        best = cand
        improved = true
        break
      }
    }
    if !improved || budget <= 0 {
      return best
    }
  }
}

///|
/// Length-first shrinking for public actions. Arguments stay concrete for the
/// same reason the dispatch shrinker keeps them concrete: a reproducer should
/// minimize the interaction sequence before it minimizes data.
pub fn shrink_actions(script : Array[Action]) -> Iter[Array[Action]] {
  let out : Array[Array[Action]] = []
  let n = script.length()
  if n == 0 {
    return out.iter()
  }
  let mut cut = n / 2
  while cut > 0 {
    out.push(script[0:cut].to_owned())
    cut = cut / 2
  }
  for i in 0..<n {
    let without : Array[Action] = []
    for j, action in script {
      if j != i {
        without.push(action)
      }
    }
    out.push(without)
  }
  out.iter()
}

///|
/// Whether `script` still breaks an invariant, from a fresh mount.
///
/// A candidate that could not be mounted answers false: it is not a candidate
/// that reproduces, and shrinking must not turn a mount failure into the
/// component's.
fn[N] still_fails(
  plan : Plan,
  script : Array[Action],
  remount : () -> @harness.Harness[N]?,
  at : @tutuca.DispatchPath,
  read? : Reader,
) -> Bool {
  guard remount() is Some(h) else { return false }
  (plan.run(h, script, at~, read?).outcome is Broke(..)) catch {
    _ => false
  }
}
