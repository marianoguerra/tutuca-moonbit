// The block language's tokenizer.
//
// Finer than the slot tokenizer beside it, and it has to be: `.rows[.sel]` is
// ONE token in a slot and must be four here, because a body can index with an
// expression. The slot tokenizer stays for now and this joins it; the two
// become one once the block grammar has proven itself, which is the moment the
// slot language can be re-expressed as "one expression, restricted by group"
// over this token stream.
//
// Two things it does that a naive lexer would not:
//
//   - **Newlines are tokens**, because a statement ends at one. They are
//     suppressed inside `(` and `[` — where a newline cannot end anything —
//     and NOT inside `{`, where it separates statements. That is the same rule
//     Go and Python use, and it is what lets a long argument list wrap.
//   - **An identifier may end in `?`**, so `empty?` and a user's `ready?` lex
//     as one name rather than a name and a stray operator.

///|
/// One token of the block language.
pub(all) enum STok {
  TLBrace
  TRBrace
  TLParen
  TRParen
  TLBracket
  TRBracket
  TComma
  /// A statement separator: a `;` or a newline. One kind, because they mean
  /// the same thing and the parser should not have to say so twice.
  TSep
  TDot
  TAt
  TDollar
  TCaret
  TAmp
  TAssign
  TPlusAssign
  TMinusAssign
  /// A word or symbol operator: `and` `or` `is` `is not` `implies` `not`
  /// `< <= > >=` `+` `-` `*` `/` `mod`. `*` and `-` are BOTH prefix and infix
  /// and arrive here either way; the parser decides by position, which is why
  /// the lexer needs no whitespace rule to tell `.n * 2` from `*theme`.
  TOp(String)
  TIdent(String)
  TNum(Double)
  /// A `'…'` literal, already unescaped.
  TStr(String)
  /// The raw interior of a `$'…'` template, escapes resolved, `{…}` intact.
  TTpl(String)
  /// A `///` line, without the marker. The parser joins a run of them.
  TDoc(String)
  TEof
} derive(Debug, Eq)

///|
/// A token and where it came from.
pub(all) struct ScriptToken {
  tok : STok
  span : Span
} derive(Debug, Eq)

///|
fn is_ident_start(c : Char) -> Bool {
  (c >= 'a' && c <= 'z') || (c >= 'A' && c <= 'Z') || c == '_'
}

///|
/// Exactly the slot language's rule (`is_valid_val_id`), and deliberately so:
/// one identifier rule across both halves is the §2.4 property this design
/// exists to protect. It also settles a real ambiguity — with `-` admitted,
/// `count-1` would lex as ONE name, and arithmetic is the whole point of a
/// block. Which is why the two-word declaration kind is `enrichScope` rather
/// than the design sketch's `enrich-scope`.
fn is_ident_char(c : Char) -> Bool {
  is_ident_start(c) || (c >= '0' && c <= '9')
}

///|
fn is_digit(c : Char) -> Bool {
  c >= '0' && c <= '9'
}

///|
/// The word operators, so `is` and `mod` lex as operators rather than names.
///
/// `not` is here too even though it is prefix-only: the parser decides
/// position, and a name `not` would shadow the operator in a way no author
/// could then spell around.
fn word_op(s : String) -> Bool {
  s is ("and" | "or" | "is" | "not" | "mod" | "implies")
}

///|
/// Tokenize a block. Comments (`//` to end of line) vanish; `///` lines
/// survive as documentation attached to whatever declaration follows.
pub fn tokenize_script(source : String) -> Array[ScriptToken] raise ScriptError {
  let chars : Array[Char] = source.iter().collect()
  let out : Array[ScriptToken] = []
  let n = chars.length()
  // `(` and `[` only: a newline inside them cannot end a statement, while one
  // inside `{` separates two.
  let mut depth = 0
  let mut i = 0
  fn push(t : STok, start : Int, end_ : Int) -> Unit {
    out.push({ tok: t, span: { start, end_ } })
  }

  fn sep_pending() -> Bool {
    // Collapse a run of newlines and semicolons into one separator, and never
    // start the stream with one.
    match out.last() {
      Some({ tok: TSep, .. }) | None => false
      _ => true
    }
  }

  while i < n {
    let c = chars[i]
    // -- whitespace and separators ------------------------------------------
    if c == '\n' {
      if depth == 0 && sep_pending() {
        push(TSep, i, i + 1)
      }
      i = i + 1
      continue
    }
    if c == ' ' || c == '\t' || c == '\r' {
      i = i + 1
      continue
    }
    if c == ';' {
      if sep_pending() {
        push(TSep, i, i + 1)
      }
      i = i + 1
      continue
    }
    // -- comments ------------------------------------------------------------
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
        // One token per `///` line. Joining a run of them into one comment is
        // the parser's job, because a newline between two of them is a real
        // separator token and the lexer would have to look past it.
        push(TDoc(text.to_string().trim(chars=" ").to_owned()), start, j)
      }
      i = j
      continue
    }
    // -- strings and templates ----------------------------------------------
    if c == '\'' {
      let (text, end_) = scan_string(chars, i + 1, i)
      push(TStr(text), i, end_)
      i = end_
      continue
    }
    if c == '$' && i + 1 < n && chars[i + 1] == '\'' {
      let (text, end_) = scan_string(chars, i + 2, i)
      push(TTpl(text), i, end_)
      i = end_
      continue
    }
    // -- numbers -------------------------------------------------------------
    if is_digit(c) {
      let start = i
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
        _ => raise Unexpected(got=s, want="a number", span={ start, end_: i })
      }
      push(TNum(v), start, i)
      continue
    }
    // -- identifiers and word operators -------------------------------------
    if is_ident_start(c) {
      let start = i
      while i < n && is_ident_char(chars[i]) {
        i = i + 1
      }
      // A trailing `?` belongs to the name: `empty?` is one identifier, and a
      // user predicate is free to end the same way.
      if i < n && chars[i] == '?' {
        i = i + 1
      }
      let text = StringBuilder::new()
      for k in start..<i {
        text.write_char(chars[k])
      }
      let s = text.to_string()
      push(if word_op(s) { TOp(s) } else { TIdent(s) }, start, i)
      continue
    }
    // -- punctuation and symbol operators -----------------------------------
    let two : String = if i + 1 < n {
      let b = StringBuilder::new()
      b.write_char(c)
      b.write_char(chars[i + 1])
      b.to_string()
    } else {
      ""
    }
    match two {
      "+=" => {
        push(TPlusAssign, i, i + 2)
        i = i + 2
        continue
      }
      "-=" => {
        push(TMinusAssign, i, i + 2)
        i = i + 2
        continue
      }
      "<=" | ">=" => {
        push(TOp(two), i, i + 2)
        i = i + 2
        continue
      }
      _ => ()
    }
    let single : STok = match c {
      '{' => TLBrace
      '}' => TRBrace
      '(' => {
        depth = depth + 1
        TLParen
      }
      ')' => {
        depth = if depth > 0 { depth - 1 } else { 0 }
        TRParen
      }
      '[' => {
        depth = depth + 1
        TLBracket
      }
      ']' => {
        depth = if depth > 0 { depth - 1 } else { 0 }
        TRBracket
      }
      ',' => TComma
      '.' => TDot
      '@' => TAt
      '$' => TDollar
      '^' => TCaret
      '&' => TAmp
      '=' => TAssign
      // `*` is an OPERATOR token, not a sigil, and the parser decides by
      // position which it is — exactly as it does for `-`. Lexing it as a
      // sigil would make `a * b` read as `a` applied to `*b`, which is the
      // commoner form losing to the rarer one. A `*dyn` in an argument
      // position therefore takes parentheses: `len (*theme)`.
      '+' | '-' | '*' | '/' | '<' | '>' => TOp(c.to_string())
      _ =>
        raise Unexpected(
          got=c.to_string(),
          want="a declaration, a statement or an expression",
          span={ start: i, end_: i + 1 },
        )
    }
    push(single, i, i + 1)
    i = i + 1
  }
  // A trailing separator says nothing; dropping it means the parser never has
  // to special-case the end of the block.
  while out.last() is Some({ tok: TSep, .. }) {
    out.pop() |> ignore
  }
  push(TEof, n, n)
  out
}

///|
/// Scan a `'…'` run from just past the opening quote. Returns the unescaped
/// text and the index just past the closing quote.
///
/// Only `\'` and `\\` are escapes, exactly as in a slot literal — a second
/// escape vocabulary in the same file would be the thing §2.4 warns against.
fn scan_string(
  chars : Array[Char],
  from : Int,
  open : Int,
) -> (String, Int) raise ScriptError {
  let buf = StringBuilder::new()
  let n = chars.length()
  let mut i = from
  while i < n {
    match chars[i] {
      '\\' if i + 1 < n && chars[i + 1] is ('\'' | '\\') => {
        buf.write_char(chars[i + 1])
        i = i + 2
      }
      '\'' => return (buf.to_string(), i + 1)
      c => {
        buf.write_char(c)
        i = i + 1
      }
    }
  }
  raise Unexpected(got="end of block", want="a closing `'`", span={
    start: open,
    end_: n,
  })
}
