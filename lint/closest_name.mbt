// "Did you mean" suggestions: Damerau-
// Levenshtein distance with adjacent transpositions counted as one edit.
// Inputs are identifier-shaped strings and candidate sets in the tens, so no
// banded variant is needed.

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
    let d = @tutuca.edit_distance(name, cand)
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
