// Applying edits, and the two ways a rule can be wrong about one.
//
// This is the whole of the danger. A rule produces spans; if two of them
// overlap, or one names text the file does not hold, applying them writes a
// file nobody asked for — and the author finds out later, from a compiler, in
// a file they did not think they had changed. Both are checked here, before a
// single character moves, and both stop the file rather than mangling it.

///|
pub fn apply(source : String, edits : Array[Edit]) -> String raise MigrateError {
  if edits.is_empty() {
    return source
  }
  let sorted = edits.copy()
  sorted.sort_by(fn(a, b) { a.span.start - b.span.start })
  // Overlap first, and against the SORTED list, so "overlaps" is one
  // comparison per neighbour rather than a square of them.
  for i in 1..<sorted.length() {
    let prev = sorted[i - 1]
    let cur = sorted[i]
    if cur.span.start < prev.span.end_ {
      raise Overlap(first=prev.rule, second=cur.rule, at=cur.span.start)
    }
  }
  let chars = source.to_array()
  for e in sorted {
    let got = slice(chars, e.span.start, e.span.end_)
    if got != e.from {
      raise Mismatch(rule=e.rule, at=e.span.start, want=e.from, got~)
    }
  }
  // Right to left: replacing a later span cannot move an earlier one, so no
  // rule has to know what any other rule did.
  let out = StringBuilder()
  let mut cut = 0
  for e in sorted {
    out.write_string(slice(chars, cut, e.span.start))
    out.write_string(e.to)
    cut = e.span.end_
  }
  out.write_string(slice(chars, cut, chars.length()))
  out.to_string()
}

///|
/// `chars[start:end_]` as a string, clamped, because a span past the end is a
/// rule bug that should report a mismatch rather than crash.
fn slice(chars : Array[Char], start : Int, end_ : Int) -> String {
  let n = chars.length()
  let a = if start < 0 { 0 } else if start > n { n } else { start }
  let b = if end_ < a { a } else if end_ > n { n } else { end_ }
  let out = StringBuilder()
  for i in a..<b {
    out.write_char(chars[i])
  }
  out.to_string()
}

///|
pub fn diff_lines(path : String, m : Migration) -> Array[String] {
  let out : Array[String] = []
  let sorted = m.edits.copy()
  sorted.sort_by(fn(a, b) { a.span.start - b.span.start })
  for e in sorted {
    out.push("\{path}:\{e.span.start}  \{e.rule}  \{e.from} -> \{e.to}")
  }
  out
}
