// How many lines a piece of source has.
//
// The counting half of "where does this offset fall", which two backends had
// written out under two names. The OFFSET half lives in `viewfile`, beside the
// splitter whose spans every caller of it is reporting against — and where the
// `cli`, which deliberately imports no `core`, can reach it.

///|
/// How many newlines `s` contains — one less than the number of lines when it
/// does not end in one, which is why it is named for what it counts.
pub fn line_count(s : String) -> Int {
  let mut n = 0
  for c in s {
    if c == '\n' {
      n = n + 1
    }
  }
  n
}
