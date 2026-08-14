// The normalization phase: what happens to the bytes before any rule reads
// them, and the two divergences it exists to close.
//
// ## Why there is a phase here at all
//
// Every CSS sanitizer that has ever been broken was broken in the same place:
// it compared a name it had read against a name it expected, and the browser
// read a different name. CSS gives an attacker three ways to make that happen —
// escapes (`\75 rl(…)` is `url(…)`), the input preprocessing the spec requires
// before tokenizing (a NUL is U+FFFD, a form feed is a newline), and comments
// in the middle of a value. A validator that tokenizes and then compares
// strings has already lost if its tokenizer disagrees with the browser's about
// any of the three.
//
// So this phase does not try to match the browser. It REFUSES anything where
// the two could differ, which is a much smaller thing to be right about.
//
// ## The two divergences in `mizchi/css/token`, concretely
//
// **It does not decode escapes.** `Tokenizer::consume_name` skips the backslash
// and copies the next raw character; its own comment says "CSS hex escapes
// aren't decoded here". So `\75 rl(https://evil.test/)` tokenizes as
// `Ident("75") Whitespace Function("rl")`, and every browser reads `url(`. There
// is no source span on `Token`, so the original spelling is not recoverable
// downstream and no amount of care after the fact can fix it.
//
// The answer is `has_escape`: refuse any input containing a backslash, at all,
// anywhere. A CSS escape is a way of spelling a character you could have
// written directly, and no value in any level here needs one — the subset has
// no strings outside `font-family`, no custom idents, and no selectors. So the
// refusal costs a syntax nobody uses and closes the whole class rather than one
// spelling of it. It is checked on the RAW input, before tokenizing, because a
// tokenizer that mis-handles escapes cannot be trusted to report them either.
//
// (A scoped STYLESHEET could not do this: Tailwind emits `.bg-\[\#fff\]`, and a
// selector legitimately carries escapes. That is one of the reasons the
// stylesheet half is not built here — see `dyncomp/SECURITY.md` §4.)
//
// **NUL is its EOF sentinel.** `peek_char` returns U+0000 both for "the byte
// here is a NUL" and for "there is no byte here", so an embedded NUL is
// indistinguishable from end of input. css-syntax-3 §3.3 says a NUL is U+FFFD,
// which is a name character, so the browser keeps reading where the tokenizer
// may stop. `preprocess` does the §3.3 replacement first, and after it no NUL
// reaches the tokenizer at all.
//
// ## What else the phase refuses, and why each one
//
// `BadString`, an unmatched bracket, `CDO`/`CDC`, and any at-keyword. These are
// exactly the shapes where a recovery rule decides the meaning, and recovery
// rules are where two parsers disagree. None of them appears in a declaration
// list anyone wrote on purpose.

///|
/// css-syntax-3 §3.3 input preprocessing.
///
/// `\r\n`, a lone `\r` and a form feed all become `\n`; U+0000 and any lone
/// surrogate become U+FFFD. The surrogate half matters because MoonBit's
/// `String` is UTF-16 and the tokenizer reads it a code unit at a time, so an
/// unpaired half would otherwise reach a name comparison as a character no
/// browser would produce.
fn preprocess(src : String) -> String {
  let out = StringBuilder::new()
  let n = src.length()
  let mut i = 0
  while i < n {
    let c = src.unsafe_get(i)
    if c == 0x000D {
      // CR, or CRLF, becomes one LF.
      out.write_char('\n')
      i += if i + 1 < n && src.unsafe_get(i + 1) == 0x000A { 2 } else { 1 }
    } else if c == 0x000C {
      out.write_char('\n')
      i += 1
    } else if c == 0x0000 {
      out.write_char('\u{FFFD}')
      i += 1
    } else if c >= 0xD800 && c <= 0xDBFF {
      // A high surrogate keeps its pair and is replaced when it has none.
      let lo = if i + 1 < n { src.unsafe_get(i + 1) } else { 0 }
      if lo >= 0xDC00 && lo <= 0xDFFF {
        out.write_char(c.unsafe_to_char())
        out.write_char(lo.unsafe_to_char())
        i += 2
      } else {
        out.write_char('\u{FFFD}')
        i += 1
      }
    } else if c >= 0xDC00 && c <= 0xDFFF {
      out.write_char('\u{FFFD}')
      i += 1
    } else {
      out.write_char(c.unsafe_to_char())
      i += 1
    }
  }
  out.to_string()
}

///|
/// Whether the source contains a backslash.
///
/// Checked on the raw input rather than on tokens, because the tokenizer is
/// what cannot be trusted with them. See the note at the top of this file.
fn has_escape(src : String) -> Bool {
  for c in src {
    if c == '\\' {
      return true
    }
  }
  false
}

///|
/// Preprocess, refuse escapes, tokenize, and refuse the token shapes that only
/// a recovery rule can give meaning to.
///
/// The `EOF` token the tokenizer appends is dropped, so callers never have to
/// know it was there.
fn normalize(src : String) -> Result[Array[@token.Token], CssReason] {
  if has_escape(src) {
    return Err(Escape)
  }
  let tokens = @token.tokenize(preprocess(src))
  if tokens.length() > max_tokens {
    return Err(TooLarge)
  }
  let out : Array[@token.Token] = []
  let mut depth = 0
  for tok in tokens {
    match tok {
      EOF => break
      BadString => return Err(Malformed("unterminated string"))
      CDO | CDC => return Err(Malformed("<!-- or --> in a value"))
      AtKeyword(name) => return Err(Malformed("@\{name}"))
      LeftBrace | RightBrace =>
        // A declaration list has no blocks in it, and a `}` is the brace
        // breakout `Component::compile_style` is vulnerable to. Refusing the
        // token is not what makes the re-emission safe — nothing unparsed is
        // ever forwarded, so there is nothing for a `}` to escape — but a
        // declaration list containing one was not a declaration list.
        return Err(Malformed("a brace in a declaration list"))
      LeftParen | Function(_) => {
        depth += 1
        if depth > max_nesting {
          return Err(TooLarge)
        }
        out.push(tok)
      }
      RightParen => {
        depth -= 1
        if depth < 0 {
          return Err(Malformed("unbalanced )"))
        }
        out.push(tok)
      }
      LeftBracket | RightBracket =>
        // `[]` appears in a grammar (`grid-template-areas` line names) that no
        // level admits. Refusing the token keeps the emitter from having to
        // have an opinion about it.
        return Err(Malformed("a bracket in a declaration list"))
      _ => out.push(tok)
    }
  }
  if depth != 0 {
    return Err(Malformed("unclosed ("))
  }
  Ok(out)
}

///|
/// ASCII-lowercase, for a name that CSS matches case-insensitively.
///
/// Property names, function names, units and keywords are all ASCII
/// case-insensitive. Custom property names are NOT — `--Foo` and `--foo` are
/// different properties — so `declarations.mbt` folds only what it should.
fn ascii_lower(s : String) -> String {
  let out = StringBuilder::new()
  for c in s {
    if c >= 'A' && c <= 'Z' {
      out.write_char((c.to_int() + 32).unsafe_to_char())
    } else {
      out.write_char(c)
    }
  }
  out.to_string()
}

///|
/// Whether every character is ASCII, and none is a C0 control.
///
/// A name outside ASCII is never one of ours: every property, keyword,
/// function and unit any level admits is ASCII, so a non-ASCII character in one
/// means the comparison is about to be made against something a browser might
/// normalize differently. Refusing is cheaper than being sure.
fn is_plain_ascii_name(s : String) -> Bool {
  if s == "" {
    return false
  }
  for c in s {
    let n = c.to_int()
    if n < 0x21 || n > 0x7E {
      return false
    }
  }
  true
}
