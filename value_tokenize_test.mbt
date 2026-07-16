// Port of the tokenizeValue suite from tutuca test/value.test.js

///|
test "splits on whitespace" {
  assert_true(
    @tutuca.tokenize_value("equals? .view detail") ==
    ["equals?", ".view", "detail"],
  )
}

///|
test "keeps a quoted literal with spaces as one token" {
  assert_true(
    @tutuca.tokenize_value("equals? .name 'John Doe'") ==
    ["equals?", ".name", "'John Doe'"],
  )
}

///|
test "keeps an escaped quote inside the token" {
  assert_true(
    @tutuca.tokenize_value("equals? .name 'it\\'s here'") ==
    ["equals?", ".name", "'it\\'s here'"],
  )
}

///|
test "keeps a $'…' template as a single token" {
  assert_true(@tutuca.tokenize_value("$'a {.b} c' .d") == ["$'a {.b} c'", ".d"])
}

///|
test "empty string yields no tokens" {
  assert_true(@tutuca.tokenize_value("") == ([] : Array[String]))
}
