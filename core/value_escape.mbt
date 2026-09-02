// Quoting a string back into value-language source.
//
// The inverse is the lexer's and lives in `tscript`, because unescaping is
// something a tokenizer does and escaping is something a printer does. These
// stay here now that the printer does: one AST, one `to_source`, and this is
// the table it quotes with.

///|
/// The escape letter a character is written as inside a `'…'` literal, when it
/// is written as one.
///
/// A newline in a literal is printed as `\n` rather than as itself: the source
/// round-trips either way, but a declaration that grew three lines because a
/// seed carries a paragraph is a declaration nobody can read.
pub fn escape_of(c : Char) -> Char? {
  match c {
    '\'' => Some('\'')
    '\\' => Some('\\')
    '\n' => Some('n')
    '\t' => Some('t')
    '\r' => Some('r')
    _ => None
  }
}

///|
/// Escape into `buf` — shared by literal quoting and template re-escaping.
fn escape_str_into(buf : StringBuilder, s : String) -> Unit {
  for c in s {
    match escape_of(c) {
      Some(e) => {
        buf.write_char('\\')
        buf.write_char(e)
      }
      None => buf.write_char(c)
    }
  }
}

///|
/// A string as a `'…'` literal.
fn escape_str_literal(s : String) -> String {
  let buf = StringBuilder()
  buf.write_char('\'')
  escape_str_into(buf, s)
  buf.write_char('\'')
  buf.to_string()
}
