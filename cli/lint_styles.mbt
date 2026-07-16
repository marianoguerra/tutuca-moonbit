// Scoped-style checks (JS checkScopedStyleTopLevel / scanScopedCss).
//
// `style`/`commonStyle` are wrapped by Component::compile_style in a
// component-scoped selector ([data-cid="N"]{ … }), so their CSS lands
// *inside* a style-rule block. Top-level-only at-rules and rules whose
// leading selector targets the document root are invalid or dead once
// nested there — the browser silently drops them. `globalStyle` is injected
// verbatim, so it is never checked.
//
// CSS is a raw string with no parser in the project; we scan after blanking
// comments and string literals. A `/* tutuca-lint-ignore */` comment on the
// same line as a finding suppresses it.

///|
/// Top-level-only at-rule names; the nestable conditional-group rules
/// (@media, @supports, @container, @layer, @scope, @starting-style) are
/// deliberately absent.
let non_nestable_at_rules : Array[String] = [
  "charset", "import", "namespace", "font-face", "keyframes", "page", "property",
  "counter-style", "font-feature-values", "font-palette-values", "view-transition",
]

///|
let style_to_global_help : String = "Move it to the component's 'globalStyle' key, which is injected without the component-scoping wrapper. To suppress a false positive, put a /* tutuca-lint-ignore */ comment on the same line."

///|
fn is_css_space(c : Char) -> Bool {
  c is (' ' | '\t' | '\n' | '\r')
}

///|
fn is_word_char(c : Char) -> Bool {
  c is ('a'..='z' | 'A'..='Z' | '0'..='9' | '_')
}

///|
fn to_lower_char(c : Char) -> Char {
  if c is ('A'..='Z') {
    (c.to_int() + 32).unsafe_to_char()
  } else {
    c
  }
}

///|
/// Replace comments and string literals with spaces (newlines kept so byte
/// offsets and line numbers stay accurate). JS blankCssNoise.
fn blank_css_noise(css : String) -> Array[Char] {
  let chars : Array[Char] = css.iter().collect()
  let n = chars.length()
  fn blank(from : Int, to : Int) {
    for k in from..<to {
      if chars[k] != '\n' {
        chars[k] = ' '
      }
    }
  }

  let mut i = 0
  while i < n {
    let c = chars[i]
    if c == '/' && i + 1 < n && chars[i + 1] == '*' {
      let mut j = i + 2
      while j + 1 < n && !(chars[j] == '*' && chars[j + 1] == '/') {
        j = j + 1
      }
      let end = if j + 1 < n { j + 2 } else { n }
      blank(i, end)
      i = end
    } else if c is ('"' | '\'') {
      let quote = c
      let mut j = i + 1
      while j < n && chars[j] != quote && chars[j] != '\n' {
        if chars[j] == '\\' && j + 1 < n {
          j = j + 2
        } else {
          j = j + 1
        }
      }
      // Unterminated-by-newline strings stay unblanked, like the JS regex.
      if j < n && chars[j] == quote {
        blank(i, j + 1)
        i = j + 1
      } else {
        i = i + 1
      }
    } else {
      i = i + 1
    }
  }
  chars
}

///|
/// 1-based line/column of `index` within the char array.
fn line_col_at(chars : Array[Char], index : Int) -> (Int, Int) {
  let mut line = 1
  let mut line_start = 0
  for i in 0..<index {
    if chars[i] == '\n' {
      line = line + 1
      line_start = i + 1
    }
  }
  (line, index - line_start + 1)
}

///|
/// 1-based line numbers carrying a `/* tutuca-lint-ignore */` directive.
fn suppressed_lines(css : String) -> Array[Int] {
  let chars : Array[Char] = css.iter().collect()
  let needle : Array[Char] = "tutuca-lint-ignore".iter().collect()
  let lines : Array[Int] = []
  let n = chars.length()
  let mut i = 0
  while i + 1 < n {
    if chars[i] == '/' && chars[i + 1] == '*' {
      let start = i
      let mut j = i + 2
      while j < n && is_css_space(chars[j]) {
        j = j + 1
      }
      let mut k = 0
      while k < needle.length() && j + k < n && chars[j + k] == needle[k] {
        k = k + 1
      }
      if k == needle.length() {
        let mut m = j + k
        while m < n && is_css_space(chars[m]) {
          m = m + 1
        }
        if m + 1 < n && chars[m] == '*' && chars[m + 1] == '/' {
          let (line, _col) = line_col_at(chars, start)
          lines.push(line)
        }
      }
    }
    i = i + 1
  }
  lines
}

///|
/// Case-insensitive literal match of `name` at `pos` with a word boundary
/// after it (the JS `\b` following the at-rule / selector keyword).
fn matches_keyword_at(chars : Array[Char], pos : Int, name : String) -> Bool {
  let target : Array[Char] = name.iter().collect()
  if pos + target.length() > chars.length() {
    return false
  }
  for k in 0..<target.length() {
    if to_lower_char(chars[pos + k]) != target[k] {
      return false
    }
  }
  let after = pos + target.length()
  after >= chars.length() || !is_word_char(chars[after])
}

///|
fn scan_scoped_css(
  run : LintRun,
  css : String,
  key : String,
  view : String?,
) -> Unit {
  if css == "" {
    return
  }
  let ignore = suppressed_lines(css)
  let chars = blank_css_noise(css)
  let n = chars.length()
  fn report(code : String, message_head : String, at : Int) {
    let (line, col) = line_col_at(chars, at)
    if ignore.contains(line) {
      return
    }
    let where_ = match view {
      Some(v) => "\{run.comp.name}/\{v}"
      None => run.comp.name
    }
    run.out.push({
      code,
      level: Error,
      where_,
      message: message_head + " at line \{line}, col \{col}",
      suggestion: Some(Rephrase(from=key, text=style_to_global_help)),
    })
  }

  // Non-nestable at-rules: `@` after start/whitespace/;/{/}, optional
  // vendor prefix, then a name from the list with a word boundary after.
  for i in 0..<n {
    if chars[i] != '@' {
      continue
    }
    if i > 0 &&
      !(is_css_space(chars[i - 1]) || chars[i - 1] is (';' | '{' | '}')) {
      continue
    }
    // optional -vendor- prefix
    let mut name_start = i + 1
    if name_start < n && chars[name_start] == '-' {
      let mut k = name_start + 1
      while k < n && to_lower_char(chars[k]) is ('a'..='z') {
        k = k + 1
      }
      if k > name_start + 1 && k < n && chars[k] == '-' {
        name_start = k + 1
      }
    }
    for rule in non_nestable_at_rules {
      if matches_keyword_at(chars, name_start, rule) {
        report(
          "TOP_LEVEL_AT_RULE_IN_SCOPED_STYLE",
          "'@\{rule}' is a top-level-only at-rule, but '\{key}' is wrapped in a component-scoped selector ([data-cid=…]{…}) where it is invalid and silently dropped — move it to 'globalStyle'",
          i,
        )
        break
      }
    }
  }
  // Rules whose LEADING compound selector is html/body/:root and which open
  // a block before any `;`/`}` (JS GLOBAL_LEADING_SELECTOR).
  for sel in ["html", "body", ":root"] {
    for s in 0..<n {
      if !matches_keyword_at(chars, s, sel) {
        continue
      }
      // Only the leading selector counts: walking back, skip whitespace and
      // require start-of-input or a brace.
      let mut b = s - 1
      while b >= 0 && is_css_space(chars[b]) {
        b = b - 1
      }
      if b >= 0 && !(chars[b] is ('{' | '}')) {
        continue
      }
      // Forward: [^{};]*\{
      let mut f = s + sel.length()
      while f < n && !(chars[f] is ('{' | '}' | ';')) {
        f = f + 1
      }
      if f < n && chars[f] == '{' {
        report(
          "GLOBAL_SELECTOR_IN_SCOPED_STYLE",
          "Selector '\{sel}' targets the document root, but '\{key}' is wrapped in a component-scoped selector, so it becomes a descendant selector that never matches — move it to 'globalStyle'",
          s,
        )
      }
    }
  }
}

///|
fn check_scoped_style_top_level(run : LintRun) -> Unit {
  scan_scoped_css(run, run.comp.common_style, "commonStyle", None)
  for vname, view in run.comp.views {
    scan_scoped_css(run, view.style, "style", Some(vname))
  }
}
