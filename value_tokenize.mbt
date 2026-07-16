// Value tokenizer (src/value.js VAL_TOKEN_RE / unescapeStr). Implements the
// declares in spec.mbt.

///|
fn is_val_space(c : Char) -> Bool {
  // JS \s (the subset that can occur in attribute values)
  c is (' ' | '\t' | '\n' | '\r' | '\u{b}' | '\u{c}' | '\u{a0}')
}

///|
/// Scan a quoted run starting at the opening quote index (the `'`). Returns
/// the index just past the closing quote, or None when unterminated.
/// Inside the run `\` escapes the next character (JS `\\.`).
fn scan_quoted(chars : Array[Char], open : Int) -> Int? {
  let mut i = open + 1
  while i < chars.length() {
    match chars[i] {
      '\\' => i = i + 2
      '\'' => return Some(i + 1)
      _ => i = i + 1
    }
  }
  None
}

///|
/// The single value tokenizer: a `$'…'` template run, a plain `'…'` literal
/// (escapes kept in the token), or a maximal non-whitespace run. Quoted
/// alternatives win only at their start; an unterminated quote falls back to
/// the plain run (mirrors the JS regex alternation).
pub fn tokenize_value(s : String) -> Array[String] {
  let chars : Array[Char] = s.iter().collect()
  let out : Array[String] = []
  let mut i = 0
  while i < chars.length() {
    if is_val_space(chars[i]) {
      i = i + 1
      continue
    }
    let start = i
    let quote_end : Int? = if chars[i] == '\'' {
      scan_quoted(chars, i)
    } else if chars[i] == '$' && i + 1 < chars.length() && chars[i + 1] == '\'' {
      scan_quoted(chars, i + 1)
    } else {
      None
    }
    let end = match quote_end {
      Some(e) => e
      None => {
        // Plain run: everything up to the next whitespace.
        let mut j = start
        while j < chars.length() && !is_val_space(chars[j]) {
          j = j + 1
        }
        j
      }
    }
    let buf = StringBuilder::new()
    for k in start..<end {
      buf.write_char(chars[k])
    }
    out.push(buf.to_string())
    i = end
  }
  out
}

///|
/// Within a `'…'` literal only the delimiter and the escape char are
/// escapable; every other backslash stays literal (JS unescapeStr).
fn unescape_str(s : String) -> String {
  let chars : Array[Char] = s.iter().collect()
  let buf = StringBuilder::new()
  let mut i = 0
  while i < chars.length() {
    if chars[i] == '\\' &&
      i + 1 < chars.length() &&
      chars[i + 1] is ('\'' | '\\') {
      buf.write_char(chars[i + 1])
      i = i + 2
    } else {
      buf.write_char(chars[i])
      i = i + 1
    }
  }
  buf.to_string()
}

///|
/// JS ConstVal.toString quoting: `'…'` with `'` and `\` escaped, one pass.
fn escape_str_literal(s : String) -> String {
  let buf = StringBuilder::new()
  buf.write_char('\'')
  for c in s {
    if c is ('\'' | '\\') {
      buf.write_char('\\')
    }
    buf.write_char(c)
  }
  buf.write_char('\'')
  buf.to_string()
}
