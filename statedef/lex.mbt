// The state language's tokenizer.
//
// Deliberately NOT shared with `tscript`'s, even though the two blocks sit in
// one file and the token sets nearly agree. The disagreement is exactly the
// interesting bit: `tscript` folds a trailing `?` into the IDENTIFIER, because
// `empty?` is one name there, and a state block needs `String?` to be a type
// and a question mark. One lexer would have to be told which language it was
// reading, which is two lexers with extra steps.
//
// It is also what keeps `statedef` off `tscript`: sharing would mean depending
// on it, and this package's whole shape is text in, typed `StateDef` out, with
// a handful of small dependencies and no `Value` anywhere. `core` it does
// reach, for the `Ty`/`Domain`/`Span` vocabulary the schema is written in.

///|
/// A half-open character range in the block.
///
/// `core`'s one `Span` (`core/span.mbt`). State and script diagnostics both use
/// character ranges — the same `Array[Char]` `viewfile` slices with — so a
/// caller can rebase either block onto the containing view file exactly, and
/// two records with the same two fields would only have made that a conversion.
pub using @tutuca {type Span}

///|
/// The empty span, for a failure with no position of its own.
let no_span : Span = @tutuca.no_span

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
  TDoubleColon
  TAmp
  TComma
  TQuestion
  TEquals
  /// `.`, which heads the field reference in a `where` clause: `.items`.
  ///
  /// Two tokens rather than one `.items`, because the dot and the name are
  /// separately meaningful — the name is checked against the state's fields
  /// and the dot is what says it IS a field rather than a bare word.
  TDot
  /// The four orderings a `where` compares with.
  ///
  /// No angle bracket means anything else in this block — type arguments are
  /// `[…]`, a tuple is `(…)`, an option is `?` and a protocol intersection is
  /// `&` — so these took nothing away from the grammar to add.
  TGte
  TGt
  TLte
  TLt
  /// A value-language expression, taken WHOLE: `.sheet`, `.items[.selId]`,
  /// `self`, `'gray'`.
  ///
  /// The one place this lexer admits a language that is not its own, and it
  /// admits it opaquely: inside a `provide { … }` / `lookup { … }` section it
  /// finds where an expression ENDS and hands the slice on untouched. Reading
  /// it is `tscript`'s job, which is why a wiring section can carry a `.` and
  /// a `'` without either meaning anything here.
  TExpr(String)
  /// A brace-delimited body, taken WHOLE and WITHOUT its braces: what a `pred`
  /// or an `invariant` holds.
  ///
  /// The second place this lexer admits a language that is not its own, and it
  /// admits it the same way `TExpr` does — by finding where the body ENDS and
  /// handing the slice on untouched. A rule is one expression in the BLOCK
  /// language, which has `and`, `implies`, `is not` and `$'…'`, and none of
  /// those means anything here. `tscript` reads it; this finds it.
  ///
  /// The span on the token is the INNER range — just past `{` to just before
  /// the matching `}` — because that is what a consumer rebases a parse error
  /// from the block language onto.
  TBody(String)
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
  // Whether we are inside a `provide { … }` / `lookup { … }` section, and
  // whether the last token was its `=`. Two flags rather than a mode enum,
  // because the only thing the mode changes is what may follow an equals sign.
  //
  // The trigger is the WORD followed by a brace, which is why `provide` and
  // `lookup` are not reserved field names: `provide : Text` is still a field,
  // and nothing had to be taken away from an author to add this.
  let mut wiring = false
  let mut pending_wiring = false
  let mut after_equals = false
  // A rule — `pred NAME [format <expr>] { <body> }` — and the two opaque reads
  // it needs. Same shape as the wiring flags above and for the same reason: the
  // only thing the mode changes is what may follow a word this lexer otherwise
  // has no opinion about.
  //
  // `rule_clause` is on between the rule's NAME and its closing brace, which is
  // the window in which a `{` opens a body rather than a block. `after_format`
  // is the one token of it that reads an expression instead.
  let mut rule_name = false
  let mut rule_clause = false
  let mut after_format = false
  fn push(t : Tok, start : Int, end_ : Int) -> Unit {
    out.push({ tok: t, span: { start, end_, }, })
  }

  // Where an opaque read that started at `from` ends, respecting `'…'` strings
  // and nesting. `stop` decides, at nesting depth 0 and outside a string,
  // whether the character in hand ends the read.
  //
  // One scanner for both reads, because the two differ only in what stops them
  // — and a second copy is the kind of thing that grows a bug on one side of
  // the pair a year later.
  fn scan_opaque(from : Int, stop : (Char, Int) -> Bool) -> Int {
    let mut j = from
    let mut depth = 0
    let mut quoted = false
    while j < n {
      let d = chars[j]
      if quoted {
        if d == '\\' && j + 1 < n {
          j = j + 2
          continue
        }
        if d == '\'' {
          quoted = false
        }
        j = j + 1
        continue
      }
      if d == '\'' {
        quoted = true
        j = j + 1
        continue
      }
      if stop(d, depth) {
        break
      }
      if d == '[' || d == '(' || d == '{' {
        depth = depth + 1
      } else if d == ']' || d == ')' || d == '}' {
        depth = depth - 1
      }
      j = j + 1
    }
    j
  }

  fn slice(from : Int, to : Int) -> String {
    let text = StringBuilder()
    for k in from..<to {
      text.write_char(chars[k])
    }
    text.to_string()
  }

  // The identifier starting at `from`, and where it ends. ("", from) when there
  // is none.
  fn word_at(from : Int) -> (String, Int) {
    if from >= n || !is_ident_start(chars[from]) {
      return ("", from)
    }
    let mut k = from
    while k < n && is_ident_char(chars[k]) {
      k = k + 1
    }
    (slice(from, k), k)
  }

  fn skip_space(from : Int) -> Int {
    let mut k = from
    while k < n &&
          (
            chars[k] == ' ' ||
            chars[k] == '\t' ||
            chars[k] == '\r' ||
            chars[k] == '\n'
          ) {
      k = k + 1
    }
    k
  }

  while i < n {
    let c = chars[i]
    if c == ' ' || c == '\t' || c == '\r' || c == '\n' {
      i = i + 1
      continue
    }
    // -- a rule's `format` expression ---------------------------------------
    //
    // It runs to the `{` that opens the body. A `{` inside the sentence is
    // inside a `$'…'` template and therefore inside a string, which is exactly
    // what `scan_opaque` steps over.
    if after_format {
      after_format = false
      let start = i
      let j = scan_opaque(i, (d, depth) => depth == 0 && d == '{')
      let expr = slice(start, j).trim(chars=" \t\r\n").to_owned()
      if expr.is_empty() {
        raise Syntax(msg="`format` with no sentence after it", span={
          start,
          end_: j,
        })
      }
      push(TExpr(expr), start, j)
      i = j
      continue
    }
    // -- a rule's body ------------------------------------------------------
    if rule_clause && c == '{' {
      let inner = i + 1
      let close = scan_opaque(inner, (d, depth) => depth == 0 && d == '}')
      if close >= n {
        raise Syntax(msg="unclosed rule body", span={ start: i, end_: n, })
      }
      push(TBody(slice(inner, close)), inner, close)
      rule_clause = false
      i = close + 1
      continue
    }
    // -- a wiring section's right-hand side ---------------------------------
    if wiring && after_equals {
      after_equals = false
      let start = i
      let mut j = i
      let mut depth = 0
      let mut quoted = false
      while j < n {
        let d = chars[j]
        if quoted {
          if d == '\\' && j + 1 < n {
            j = j + 2
            continue
          }
          if d == '\'' {
            quoted = false
          }
          j = j + 1
          continue
        }
        if d == '\'' {
          quoted = true
          j = j + 1
          continue
        }
        if d == '[' || d == '(' {
          depth = depth + 1
        } else if d == ']' || d == ')' {
          depth = depth - 1
        } else if depth == 0 && (d == ',' || d == '}') {
          break
        }
        j = j + 1
      }
      let text = StringBuilder()
      for k in start..<j {
        text.write_char(chars[k])
      }
      let expr = text.to_string().trim(chars=" \t\r\n").to_owned()
      if expr.is_empty() {
        raise Syntax(msg="`=` with no expression after it", span={
          start,
          end_: j,
        })
      }
      push(TExpr(expr), start, j)
      i = j
      continue
    }
    // -- comments -----------------------------------------------------------
    if c == '/' && i + 1 < n && chars[i + 1] == '/' {
      let doc = i + 2 < n && chars[i + 2] == '/'
      let start = i
      let mut j = if doc { i + 3 } else { i + 2 }
      let text = StringBuilder()
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
      let text = StringBuilder()
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
        raise Syntax(msg="unterminated string", span={ start, end_: n, })
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
      let text = StringBuilder()
      for k in start..<i {
        text.write_char(chars[k])
      }
      let s = text.to_string()
      let v : Double = @string.from_str(s) catch {
        _ =>
          raise Syntax(msg="`\{s}` is not a number", span={ start, end_: i, })
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
      let text = StringBuilder()
      for k in start..<i {
        text.write_char(chars[k])
      }
      let word = text.to_string()
      // A rule opens on `pred` / `invariant` plus a NAME plus either the body's
      // brace or the word `format`. Two tokens of lookahead and not one,
      // because one would claim `enum Kind { pred invariant }` — a case list is
      // the one place two bare identifiers sit side by side. With the second
      // token required, a case named `pred` is still a case.
      //
      // This is the same bargain `provide` struck: the trigger is a SHAPE, so
      // `pred : Bool` is still a field and nothing was taken away from an
      // author to add this.
      if !wiring &&
        !rule_name &&
        !rule_clause &&
        (word == "pred" || word == "invariant") {
        let (name, after_name) = word_at(skip_space(i))
        if name != "" {
          let k = skip_space(after_name)
          let (next, _) = word_at(k)
          // `(` arms it too, and deliberately: a rule in this block takes no
          // parameters, and letting `pred containsText(q) { … }` through to
          // here is what lets the PARSER say so. Refusing it at the lexer
          // means the body's `.title` arrives as a bare `.` and the author is
          // told a dot has no meaning, which is true and useless.
          if (k < n && (chars[k] == '{' || chars[k] == '(')) || next == "format" {
            rule_name = true
          }
        }
      } else if rule_name {
        // The name itself. Everything up to the closing brace is now the
        // rule's, which is what lets a `{` mean a body.
        rule_name = false
        rule_clause = true
      } else if rule_clause && word == "format" {
        after_format = true
      }
      // A wiring section opens on the WORD plus a brace, so the lookahead
      // stops at the first thing that is not a space.
      if !wiring &&
        (
          word == "provide" ||
          word == "lookup" ||
          word == "property" ||
          word == "view"
        ) {
        let mut k = i
        while k < n &&
              (
                chars[k] == ' ' ||
                chars[k] == '\t' ||
                chars[k] == '\r' ||
                chars[k] == '\n'
              ) {
          k = k + 1
        }
        pending_wiring = k < n && chars[k] == '{'
      }
      push(TIdent(word), start, i)
      continue
    }
    // -- punctuation --------------------------------------------------------
    if c == '#' && i + 1 < n && chars[i + 1] == '[' {
      push(THashBracket, i, i + 2)
      i = i + 2
      continue
    }
    if c == ':' && i + 1 < n && chars[i + 1] == ':' {
      push(TDoubleColon, i, i + 2)
      i = i + 2
      continue
    }
    // The two-character orderings before the one-character ones, or `>=` would
    // lex as `>` followed by an `=` that ends a wiring section.
    if (c == '>' || c == '<') && i + 1 < n && chars[i + 1] == '=' {
      push(if c == '>' { TGte } else { TLte }, i, i + 2)
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
      '&' => TAmp
      ',' => TComma
      '?' => TQuestion
      '=' => TEquals
      '.' => TDot
      '>' => TGt
      '<' => TLt
      _ =>
        raise Syntax(msg="`\{c}` has no meaning in a state block", span={
          start: i,
          end_: i + 1,
        })
    }
    match single {
      TLBrace =>
        if pending_wiring {
          pending_wiring = false
          wiring = true
        }
      TRBrace => wiring = false
      TEquals => after_equals = wiring
      _ => ()
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
    TDoubleColon => "`::`"
    TAmp => "`&`"
    TComma => "`,`"
    TQuestion => "`?`"
    TEquals => "`=`"
    TDot => "`.`"
    TGte => "`>=`"
    TGt => "`>`"
    TLte => "`<=`"
    TLt => "`<`"
    TExpr(e) => "the expression `\{e}`"
    TBody(_) => "a rule body"
    TEof => "the end of the block"
  }
}
