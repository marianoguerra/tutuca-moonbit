// "Did you mean" — the distance, and the choosing.
//
// One implementation, because three diagnostics suggesting a name by three
// measures give three answers to the same question, and the one that used plain
// Levenshtein scored a transposition as two edits — which made `.lable` too far
// from `.label` to suggest, and a transposition is the typo people make.

///|
/// Damerau-Levenshtein: an adjacent transposition counts as ONE edit.
pub fn edit_distance(a : String, b : String) -> Int {
  let (x, y) = (a.to_array(), b.to_array())
  let n = y.length()
  let mut prev2 = Array::make(n + 1, 0)
  let mut prev = Array::makei(n + 1, i => i)
  for i in 1..<=x.length() {
    let cur = Array::make(n + 1, 0)
    cur[0] = i
    for j in 1..<=n {
      let sub = prev[j - 1] + (if x[i - 1] == y[j - 1] { 0 } else { 1 })
      let del = prev[j] + 1
      let ins = cur[j - 1] + 1
      let mut m = sub
      if del < m {
        m = del
      }
      if ins < m {
        m = ins
      }
      if i > 1 && j > 1 && x[i - 1] == y[j - 2] && x[i - 2] == y[j - 1] {
        let swap = prev2[j - 2] + 1
        if swap < m {
          m = swap
        }
      }
      cur[j] = m
    }
    prev2 = prev
    prev = cur
  }
  prev[n]
}

///|
/// The nearest of `names` to `name`, when one is close enough to suggest.
///
/// `limit` is the caller's, and it is the one thing that legitimately differs:
/// a fixed handful of command and flag names can afford a generous two edits,
/// where field names are as long as the author made them and want a threshold
/// that grows with the word. Suggesting nothing is better than suggesting the
/// wrong thing — a reader trusts a "did you mean".
pub fn closest_name(
  name : String,
  names : Array[String],
  limit~ : Int,
) -> String? {
  let mut best : String? = None
  let mut best_d = limit + 1
  for n in names {
    let d = edit_distance(name, n)
    if d < best_d {
      best_d = d
      best = Some(n)
    }
  }
  if best_d <= limit {
    best
  } else {
    None
  }
}
