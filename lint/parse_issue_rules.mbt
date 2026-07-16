// Parse-issue → finding mapping (tools/core/lint-check.js checkParseIssues,
// PARSE_ISSUES table, classifyBadValue, checkHostBareDirectives).

///|
let known_directive_names : Array[String] = [
  "dangerouslysetinnerhtml", "slot", "push-view", "text", "show", "hide", "each",
  "enrich-with", "when", "loop-with", "then", "else",
]

///|
let x_known_op_names : Array[String] = [
  "slot", "text", "render", "render-it", "render-each", "show", "hide",
]

///|
let x_known_attr_names : Array[String] = [
  "as", "when", "loop-with", "show", "hide",
]

///|
/// Directive-only names that require a leading `@` on a host element; bare
/// they are silently swallowed as plain HTML attributes.
let host_directive_only_names : Array[String] = [
  "when", "enrich-with", "loop-with", "show", "hide",
]

///|
fn finding(
  code : LintCode,
  level : LintLevel,
  info : Array[(String, String)],
  tag : String?,
  suggestion : Suggestion?,
) -> Finding {
  if tag is Some(t) {
    info.push(("tag", t))
  }
  { code, level, info, location: None, suggestion }
}

///|
fn replace_name_suggestion(
  name : String,
  candidates : Array[String],
) -> Suggestion? {
  match closest_name(name, candidates) {
    Some(to) => Some(ReplaceName(from=name, to~))
    None => None
  }
}

///|
/// Report an unknown-name issue: a leading-`@` typo gets a drop-prefix
/// error suggestion plus a MaybeDropAtPrefix hint; otherwise "did you mean".
fn push_unknown_name(
  out : Array[Finding],
  code : LintCode,
  info : Array[(String, String)],
  name : String,
  candidates : Array[String],
  tag : String?,
) -> Unit {
  let at_typo = name is ['@', .. rest] && candidates.contains(rest.to_owned())
  if at_typo {
    let to = name[1:].to_owned()
    out.push(finding(code, Error, info, tag, Some(DropPrefix(from=name, to~))))
    out.push(
      finding(
        MaybeDropAtPrefix,
        Hint,
        info.copy() + [("suggestion", to)],
        tag,
        Some(DropPrefix(from=name, to~)),
      ),
    )
  } else {
    out.push(
      finding(code, Error, info, tag, replace_name_suggestion(name, candidates)),
    )
  }
}

///|
fn bad_value_role_info(role : @anode.BadValueRole) -> Array[(String, String)] {
  match role {
    XOp(op~) => [("role", "x-op"), ("op", op)]
    Attr(name~) => [("role", "attr"), ("attr", name)]
    Directive(name~) => [("role", "directive"), ("directive", name)]
    IfDirective(name~) => [("role", "if"), ("attr", name)]
    ValueIssue(vr) => [("role", "value"), ("value-role", "\{to_repr(vr)}")]
  }
}

///|
pub fn check_collected(collector : LintCollector) -> Array[Finding] {
  let out : Array[Finding] = []
  for pair in collector.parse_issues {
    let (issue, tag) = pair
    match issue {
      XOpIgnoresChildren(op~) =>
        out.push(
          finding(
            XOpIgnoresChildren,
            Warn,
            [("op", op)],
            tag,
            Some(Remove(what="the ignored children")),
          ),
        )
      UnknownDirective(name~, value~) =>
        // No at-prefix rule for directives (they already are @-prefixed).
        out.push(
          finding(
            UnknownDirective,
            Error,
            [("name", name), ("value", value)],
            tag,
            replace_name_suggestion(name, known_directive_names),
          ),
        )
      UnknownXOp(name~, value~) =>
        push_unknown_name(
          out,
          UnknownXOp,
          [("name", name), ("value", value)],
          name,
          x_known_op_names,
          tag,
        )
      UnknownXAttr(op~, name~, value~) =>
        push_unknown_name(
          out,
          UnknownXAttr,
          [("op", op), ("name", name), ("value", value)],
          name,
          x_known_attr_names,
          tag,
        )
      BadValue(role~, value~) => {
        let trimmed = value.trim().to_owned()
        if binding_member_too_deep(trimmed) {
          out.push(
            finding(
              BindingMemberTooDeep,
              Error,
              bad_value_role_info(role) + [("value", value)],
              tag,
              Some(
                Rephrase(
                  from=value,
                  text="Read one level off the binding and compute the rest in a method or an '@enrich-with' handler.",
                ),
              ),
            ),
          )
        } else {
          match classify_bad_value(trimmed) {
            Some(detected) =>
              out.push(
                finding(
                  UnsupportedExprSyntax,
                  Error,
                  bad_value_role_info(role) +
                  [("value", value), ("detected", expr_kind_name(detected))],
                  tag,
                  Some(Rephrase(from=value, text=expr_kind_guidance(detected))),
                ),
              )
            None =>
              out.push(
                finding(
                  BadValue,
                  Error,
                  bad_value_role_info(role) + [("value", value)],
                  tag,
                  None,
                ),
              )
          }
        }
      }
    }
  }
  for pair in collector.deprecations {
    let (dep, tag) = pair
    match dep {
      // TEMPORARY (JS 2026-07-08): remove with the bare x-directive spelling.
      BareXDirective(op~, name~) =>
        out.push(
          finding(
            DeprecatedBareXDirective,
            Warn,
            [("op", op), ("name", name)],
            tag,
            Some(AddPrefix(from=name, to="@" + name)),
          ),
        )
    }
  }
  check_host_bare_directives(collector, out)
  out
}

///|
/// A bare `when`/`show`/… attribute on a host element is probably a dropped
/// `@` (JS checkHostBareDirectives).
fn check_host_bare_directives(
  collector : LintCollector,
  out : Array[Finding],
) -> Unit {
  for record in collector.attrs {
    if record.is_macro_call {
      continue
    }
    let names : Array[String] = []
    match record.result.attrs {
      ConstAttrs(m) =>
        for name, _ in m {
          names.push(name)
        }
      DynAttrs(items) =>
        for item in items {
          match item {
            Plain(name~, ..) | ConstA(name~, ..) => names.push(name)
            If(ia) => names.push(ia.name)
            RawHtml(_) => ()
          }
        }
    }
    for name in names {
      if host_directive_only_names.contains(name) {
        out.push(
          finding(
            MaybeAddAtPrefix,
            Hint,
            [("name", name), ("suggestion", "@" + name)],
            Some(record.tag),
            Some(AddPrefix(from=name, to="@" + name)),
          ),
        )
      }
    }
  }
}

// ---------------------------------------------------------------------------
// Bad-value classification (JS classifyBadValue + BINDING_MEMBER_TOO_DEEP_RE)

///|
priv enum ExprKind {
  Ternary
  Comparison
  Logical
  CallWithArgs
  FieldPath
}

///|
fn expr_kind_name(kind : ExprKind) -> String {
  match kind {
    Ternary => "ternary"
    Comparison => "comparison"
    Logical => "logical"
    CallWithArgs => "call-with-args"
    FieldPath => "field-path"
  }
}

///|
fn expr_kind_guidance(kind : ExprKind) -> String {
  match kind {
    Ternary =>
      "Ternary expressions aren't supported in dynamic attributes. Define a method or computed value on the component that returns the value, then reference it as '$methodName'."
    Comparison =>
      "Comparisons aren't supported in dynamic attributes. Define a method like 'isFooSelected' that returns the boolean, then reference it as '$isFooSelected'."
    Logical =>
      "Logical operators aren't supported in dynamic attributes. Combine the conditions in a method on the component and reference it as '$methodName'."
    CallWithArgs =>
      "Method calls with arguments aren't supported here. Reference a no-arg method ('$methodName') and read what you need from component state, or split into per-case methods."
    FieldPath =>
      "Fields can't be read through a dotted path. Define a method that returns the value, render a child component for the nested data, or — inside a loop — read one member off a binding ('@value.member')."
  }
}

///|
fn is_space(c : Char) -> Bool {
  c is (' ' | '\t' | '\n' | '\r')
}

///|
fn is_ident_start(c : Char) -> Bool {
  c is ('a'..='z' | 'A'..='Z' | '_')
}

///|
fn is_ident_char(c : Char) -> Bool {
  c is ('a'..='z' | 'A'..='Z' | '0'..='9' | '_')
}

///|
/// /\s<mid>\s/ anywhere in s (for the space-guarded ternary/comparison forms).
fn has_space_guarded(s : Array[Char], mid : Char) -> Bool {
  for i in 1..<(s.length() - 1) {
    if s[i] == mid && is_space(s[i - 1]) && is_space(s[i + 1]) {
      return true
    }
  }
  false
}

///|
/// JS /\s\?\s.+\s:\s/ — a space-guarded `?` with a space-guarded `:` at least
/// one character later.
fn looks_ternary(s : Array[Char]) -> Bool {
  for i in 1..<(s.length() - 1) {
    if s[i] == '?' && is_space(s[i - 1]) && is_space(s[i + 1]) {
      for j in (i + 3)..<(s.length() - 1) {
        if s[j] == ':' && is_space(s[j - 1]) && is_space(s[j + 1]) {
          return true
        }
      }
      return false
    }
  }
  false
}

///|
fn contains_any(s : String, needles : Array[String]) -> Bool {
  needles.iter().any(n => s.contains(n))
}

///|
/// Heuristic classifier for raw value strings the value parser rejected.
/// Order matters: ternary first (its `:` would confuse adjacent checks).
fn classify_bad_value(s : String) -> ExprKind? {
  if s == "" {
    return None
  }
  let chars = s.iter().collect()
  if looks_ternary(chars) {
    return Some(Ternary)
  }
  if contains_any(s, ["===", "!==", "==", "!=", "<=", ">="]) ||
    has_space_guarded(chars, '<') ||
    has_space_guarded(chars, '>') {
    return Some(Comparison)
  }
  if contains_any(s, ["&&", "||"]) {
    return Some(Logical)
  }
  // ^[.$][A-Za-z_]\w*\s+\S
  if chars.length() >= 2 && chars[0] is ('.' | '$') && is_ident_start(chars[1]) {
    let mut i = 2
    while i < chars.length() && is_ident_char(chars[i]) {
      i = i + 1
    }
    if i < chars.length() && is_space(chars[i]) {
      while i < chars.length() && is_space(chars[i]) {
        i = i + 1
      }
      if i < chars.length() {
        return Some(CallWithArgs)
      }
    }
  }
  // ^\.[A-Za-z_]\w*\??(\.[A-Za-z_]\w*\??)+$
  if chars.length() >= 2 &&
    chars[0] == '.' &&
    count_path_segments_at(chars, 0, allow_underscore_start=true) >= 2 {
    return Some(FieldPath)
  }
  None
}

///|
/// @name.member.member…: a binding member read more than one level deep
/// (one level is legal and parses as BindMember).
fn binding_member_too_deep(s : String) -> Bool {
  let chars : Array[Char] = s.iter().collect()
  if chars.length() < 2 || chars[0] != '@' {
    return false
  }
  // ^@[a-zA-Z]\w*\??  then (\.[a-zA-Z]\w*\??){2,}$
  guard chars[1] is ('a'..='z' | 'A'..='Z') else { return false }
  let mut i = 2
  while i < chars.length() && is_ident_char(chars[i]) {
    i = i + 1
  }
  if i < chars.length() && chars[i] == '?' {
    i = i + 1
  }
  count_path_segments_at(chars, i, allow_underscore_start=false) >= 2
}

///|
/// Number of complete `.ident?`-shaped segments from `start` to the END of
/// the input; 0 when the run doesn't consume everything (regex `$`).
fn count_path_segments_at(
  chars : Array[Char],
  start : Int,
  allow_underscore_start~ : Bool,
) -> Int {
  let mut i = start
  let mut segments = 0
  while i < chars.length() && chars[i] == '.' {
    i = i + 1
    guard i < chars.length() &&
      (
        chars[i] is ('a'..='z' | 'A'..='Z') ||
        (allow_underscore_start && chars[i] == '_')
      ) else {
      return 0
    }
    i = i + 1
    while i < chars.length() && is_ident_char(chars[i]) {
      i = i + 1
    }
    if i < chars.length() && chars[i] == '?' {
      i = i + 1
    }
    segments = segments + 1
  }
  if i == chars.length() {
    segments
  } else {
    0
  }
}
