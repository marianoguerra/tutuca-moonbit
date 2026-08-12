// The state language's tokenizer.
//
// Deliberately NOT shared with `tscript`'s, even though the two blocks sit in
// one file and the token sets nearly agree. The disagreement is exactly the
// interesting bit: `tscript` folds a trailing `?` into the IDENTIFIER, because
// `empty?` is one name there, and a state block needs `String?` to be a type
// and a question mark. One lexer would have to be told which language it was
// reading, which is two lexers with extra steps.
//
// It is also what keeps `statedef` free of `core`: sharing would mean
// depending on `tscript`, and this package's whole shape is text in, typed
// `StateDef` out, with three small dependencies and no `Value` anywhere.

///|
/// A half-open character range in the block.
///
/// Character indices, not bytes — the same `Array[Char]` `viewfile` slices
/// with, so a span from here and a span from the file agree for any input.
/// State and script diagnostics both use character ranges, so a caller can
/// rebase either block onto the containing view file exactly.
pub(all) struct Span {
  start : Int
  end_ : Int
} derive(Eq, @debug.Debug)

///|
/// The empty span, for a failure with no position of its own.
let no_span : Span = { start: 0, end_: 0 }

///|
priv enum Tok {
  TIdent(String)
  TStr(String)
  TNum(Double)
  /// A `///` line, without the marker. The parser joins a run of them.
  TDoc(String)
  TLBrace
  TRBrace
  TLBracket
  TRBracket
  TLParen
  TRParen
  /// `#[`, which opens an attribute list. One token because `#` alone means
  /// nothing here, and two would let `# [` through.
  THashBracket
  TColon
  TComma
  TQuestion
  TEquals
  TEof
} derive(Eq)

///|
priv struct Token {
  tok : Tok
  span : Span
}

///|
fn is_ident_start(c : Char) -> Bool {
  (c >= 'a' && c <= 'z') || (c >= 'A' && c <= 'Z') || c == '_'
}

///|
fn is_ident_char(c : Char) -> Bool {
  is_ident_start(c) || (c >= '0' && c <= '9')
}

///|
fn is_digit(c : Char) -> Bool {
  c >= '0' && c <= '9'
}

///|
/// Tokenize a state block.
///
/// Newlines are NOT tokens: a declaration ends at its closing brace and a
/// field at the next name, so nothing here needs a statement separator. The
/// trailing comma a field may carry is optional and ignored, which is why the
/// language reads the same whether an author writes MoonBit's commas or not.
fn tokenize(source : String) -> Array[Token] raise DefError {
  let chars : Array[Char] = source.iter().collect()
  let out : Array[Token] = []
  let n = chars.length()
  let mut i = 0
  fn push(t : Tok, start : Int, end_ : Int) -> Unit {
    out.push({ tok: t, span: { start, end_ } })
  }

  while i < n {
    let c = chars[i]
    if c == ' ' || c == '\t' || c == '\r' || c == '\n' {
      i = i + 1
      continue
    }
    // -- comments -----------------------------------------------------------
    if c == '/' && i + 1 < n && chars[i + 1] == '/' {
      let doc = i + 2 < n && chars[i + 2] == '/'
      let start = i
      let mut j = if doc { i + 3 } else { i + 2 }
      let text = StringBuilder::new()
      while j < n && chars[j] != '\n' {
        text.write_char(chars[j])
        j = j + 1
      }
      if doc {
        push(TDoc(text.to_string().trim(chars=" ").to_owned()), start, j)
      }
      i = j
      continue
    }
    // -- strings ------------------------------------------------------------
    if c == '"' {
      let start = i
      let text = StringBuilder::new()
      let mut j = i + 1
      let mut closed = false
      while j < n {
        if chars[j] == '\\' && j + 1 < n {
          text.write_char(chars[j + 1])
          j = j + 2
          continue
        }
        if chars[j] == '"' {
          j = j + 1
          closed = true
          break
        }
        text.write_char(chars[j])
        j = j + 1
      }
      if !closed {
        raise Syntax(msg="unterminated string", span={ start, end_: n })
      }
      push(TStr(text.to_string()), start, j)
      i = j
      continue
    }
    // -- numbers ------------------------------------------------------------
    if is_digit(c) || (c == '-' && i + 1 < n && is_digit(chars[i + 1])) {
      let start = i
      if c == '-' {
        i = i + 1
      }
      while i < n && is_digit(chars[i]) {
        i = i + 1
      }
      if i < n && chars[i] == '.' && i + 1 < n && is_digit(chars[i + 1]) {
        i = i + 1
        while i < n && is_digit(chars[i]) {
          i = i + 1
        }
      }
      let text = StringBuilder::new()
      for k in start..<i {
        text.write_char(chars[k])
      }
      let s = text.to_string()
      let v : Double = @string.from_str(s) catch {
        _ => raise Syntax(msg="`\{s}` is not a number", span={ start, end_: i })
      }
      push(TNum(v), start, i)
      continue
    }
    // -- identifiers --------------------------------------------------------
    if is_ident_start(c) {
      let start = i
      while i < n && is_ident_char(chars[i]) {
        i = i + 1
      }
      let text = StringBuilder::new()
      for k in start..<i {
        text.write_char(chars[k])
      }
      push(TIdent(text.to_string()), start, i)
      continue
    }
    // -- punctuation --------------------------------------------------------
    if c == '#' && i + 1 < n && chars[i + 1] == '[' {
      push(THashBracket, i, i + 2)
      i = i + 2
      continue
    }
    let single : Tok = match c {
      '{' => TLBrace
      '}' => TRBrace
      '[' => TLBracket
      ']' => TRBracket
      '(' => TLParen
      ')' => TRParen
      ':' => TColon
      ',' => TComma
      '?' => TQuestion
      '=' => TEquals
      _ =>
        raise Syntax(msg="`\{c}` has no meaning in a state block", span={
          start: i,
          end_: i + 1,
        })
    }
    push(single, i, i + 1)
    i = i + 1
  }
  push(TEof, n, n)
  out
}

///|
/// How a token reads in a message.
fn Tok::describe(self : Tok) -> String {
  match self {
    TIdent(n) => "`\{n}`"
    TStr(_) => "a string"
    TNum(_) => "a number"
    TDoc(_) => "a doc comment"
    TLBrace => "`{`"
    TRBrace => "`}`"
    TLBracket => "`[`"
    TRBracket => "`]`"
    TLParen => "`(`"
    TRParen => "`)`"
    THashBracket => "`#[`"
    TColon => "`:`"
    TComma => "`,`"
    TQuestion => "`?`"
    TEquals => "`=`"
    TEof => "the end of the block"
  }
}
