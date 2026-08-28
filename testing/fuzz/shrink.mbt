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
  script : Array[@component.Dispatch],
  remount : () -> @harness.Harness[N]?,
  at? : @tutuca.DispatchPath = @tutuca.DispatchPath::new(),
  read? : Reader,
  rounds? : Int = 200,
) -> Array[@component.Dispatch] {
  let mut best = script
  let mut budget = rounds
  // Repeat until a pass finds nothing smaller: one pass over the candidates
  // shortens a script, and the shortened one usually has candidates of its
  // own. Bounded by `budget` rather than by trust — a shrinker that does not
  // terminate is worse than one that stops early.
  for ;; {
    let mut improved = false
    for cand in @arb.shrink_script(best) {
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
/// Whether `script` still breaks an invariant, from a fresh mount.
///
/// A candidate that could not be mounted answers false: it is not a candidate
/// that reproduces, and shrinking must not turn a mount failure into the
/// component's.
fn[N] still_fails(
  plan : Plan,
  script : Array[@component.Dispatch],
  remount : () -> @harness.Harness[N]?,
  at : @tutuca.DispatchPath,
  read? : Reader,
) -> Bool {
  guard remount() is Some(h) else { return false }
  (plan.run(h, script, at~, read?).outcome is Broke(..)) catch {
    _ => false
  }
}
