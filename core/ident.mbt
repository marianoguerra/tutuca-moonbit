// The identifier rule, which every language in this repo shares.
//
// One rule across the slot language, the script block and the state block is
// the property the design exists to protect: a name means the same thing
// wherever it is written. It also settles a real ambiguity — with `-` admitted,
// `count-1` would lex as ONE name, and arithmetic is the whole point of a
// block, which is why the two-word declaration kind is `enrichScope` and not
// `enrich-scope`.
//
// Here rather than in each lexer because four copies of a rule are four rules
// that can drift, and a lexer that admits one character more than its neighbour
// is a file that means different things to two backends.

///|
/// A letter or `_`: what an identifier may begin with.
pub fn is_ident_start(c : Char) -> Bool {
  (c >= 'a' && c <= 'z') || (c >= 'A' && c <= 'Z') || c == '_'
}

///|
/// A letter, digit or `_`: what an identifier may continue with.
pub fn is_ident_char(c : Char) -> Bool {
  is_ident_start(c) || is_digit(c)
}

///|
/// An ASCII decimal digit. Deliberately not `Char::is_numeric`, which admits
/// every digit Unicode has: a number in these languages is ASCII, and a lexer
/// that accepted Devanagari digits would produce tokens no parser can read.
pub fn is_digit(c : Char) -> Bool {
  c >= '0' && c <= '9'
}
