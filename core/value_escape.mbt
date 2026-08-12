// Quoting a string back into value-language source.
//
// The inverse (`unescape_str`) is the lexer's and lives in `tscript`. These
// stay here because `impl Show for Val` is their only caller and an impl has
// to live where its type does — so the escape half follows `Val` and the
// unescape half follows the parser, and neither is duplicated.

///|
/// Escape `'` and `\` into `buf` (shared by ConstVal quoting and StrTpl
/// re-escaping in value_show).
fn escape_str_into(buf : StringBuilder, s : String) -> Unit {
  for c in s {
    if c is ('\'' | '\\') {
      buf.write_char('\\')
    }
    buf.write_char(c)
  }
}

///|
/// JS ConstVal.toString quoting: `'…'` with `'` and `\` escaped, one pass.
fn escape_str_literal(s : String) -> String {
  let buf = StringBuilder::new()
  buf.write_char('\'')
  escape_str_into(buf, s)
  buf.write_char('\'')
  buf.to_string()
}
