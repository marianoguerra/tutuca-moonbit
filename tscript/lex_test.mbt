// Port of the tokenizeValue suite from tutuca test/value.test.js, plus the
// spans that suite had nothing to say about.

///|
/// Just the text, for the runs the original suite pinned.
fn texts(s : String) -> Array[String] {
  @tscript.tokenize(s).map(t => t.text)
}

///|
test "splits on whitespace" {
  assert_eq(texts("equals? .view detail"), ["equals?", ".view", "detail"])
}

///|
test "keeps a quoted literal with spaces as one token" {
  assert_eq(texts("equals? .name 'John Doe'"), [
    "equals?", ".name", "'John Doe'",
  ])
}

///|
test "keeps an escaped quote inside the token" {
  assert_eq(texts("equals? .name 'it\\'s here'"), [
    "equals?", ".name", "'it\\'s here'",
  ])
}

///|
test "keeps a $'…' template as a single token" {
  assert_eq(texts("$'a {.b} c' .d"), ["$'a {.b} c'", ".d"])
}

///|
test "empty string yields no tokens" {
  assert_eq(texts(""), ([] : Array[String]))
}

///|
test "every token carries the range it came from" {
  // The whole point of the move: a value diagnostic can name a column now.
  let toks = @tscript.tokenize("equals? .view 'detail'")
  assert_eq(toks.map(t => t.span.start), [0, 8, 14])
  assert_eq(toks.map(t => t.span.end_), [7, 13, 22])
}

///|
test "spans index characters, not UTF-16 units" {
  // They index the same `Array[Char]` `viewfile` slices with and the WHATWG
  // tokenizer counts in, so a span from a slot and a span from the file agree
  // for any input. An astral character is one position, not two.
  let toks = @tscript.tokenize("'\u{1F600}' .after")
  assert_eq(toks.length(), 2)
  assert_eq(toks[0].span, { start: 0, end_: 3 })
  assert_eq(toks[1].span, { start: 4, end_: 10 })
}

///|
test "leading and trailing whitespace does not shift a span" {
  // The parser deliberately does NOT trim before tokenizing: trimming would
  // move every span off the string the caller handed in.
  let toks = @tscript.tokenize("   .count  ")
  assert_eq(toks.length(), 1)
  assert_eq(toks[0].span, { start: 3, end_: 9 })
}
