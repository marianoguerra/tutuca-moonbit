// "Did you mean" suggestions (tools/core/util/closest-name.js): Damerau-
// Levenshtein distance with adjacent transpositions counted as one edit.
// Inputs are identifier-shaped strings and candidate sets in the tens, so no
// banded variant is needed.

///|
fn min2(a : Int, b : Int) -> Int {
  if a < b {
    a
  } else {
    b
  }
}

///|
fn edit_distance(a : String, b : String) -> Int {
  if a == b {
    return 0
  }
  let la = a.length()
  let lb = b.length()
  if la == 0 {
    return lb
  }
  if lb == 0 {
    return la
  }
  let prev2 = Array::make(lb + 1, 0)
  let prev1 = Array::make(lb + 1, 0)
  let curr = Array::make(lb + 1, 0)
  for j in 0..<=lb {
    prev1[j] = j
  }
  for i in 1..<=la {
    curr[0] = i
    let ca = a[i - 1]
    for j in 1..<=lb {
      let cb = b[j - 1]
      let cost = if ca == cb { 0 } else { 1 }
      let mut v = min2(min2(curr[j - 1] + 1, prev1[j] + 1), prev1[j - 1] + cost)
      if i > 1 && j > 1 && ca == b[j - 2] && a[i - 2] == cb {
        v = min2(v, prev2[j - 2] + 1)
      }
      curr[j] = v
    }
    for j in 0..<=lb {
      prev2[j] = prev1[j]
      prev1[j] = curr[j]
    }
  }
  prev1[lb]
}

///|
pub fn closest_name(
  name : String,
  candidates : Array[String],
  max_distance? : Int = 2,
) -> String? {
  if name == "" {
    return None
  }
  let lower = name.to_lower()
  let mut best : String? = None
  let mut best_dist = max_distance + 1
  for cand in candidates {
    if cand == name {
      return None // exact match — caller shouldn't have asked
    }
    if cand.to_lower() == lower {
      return Some(cand) // pure case typo
    }
    let d = edit_distance(name, cand)
    if d < best_dist {
      best = Some(cand)
      best_dist = d
    }
  }
  if best_dist <= max_distance {
    best
  } else {
    None
  }
}
