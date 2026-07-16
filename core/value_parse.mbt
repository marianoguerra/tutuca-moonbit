// Value parsing (src/value.js parse functions). Implements the declares in
// spec.mbt. The JS kind bitmasks become an enum plus per-group membership
// matches; callers only see the named parse_* functions, as in JS.

///|
pub fn ParseCtx::new(macro_vars? : Map[String, String]) -> ParseCtx {
  { macro_vars: macro_vars.unwrap_or({}), issues: [] }
}

///|
fn ParseCtx::issue(self : ParseCtx, role : IssueRole, value : String) -> Unit {
  self.issues.push({ kind: BadValue, role, value })
}

///|
/// One kind per parsed value (JS K_* bits). Predicates have no kind: they
/// never pass through a group check (parse_bool builds them directly).
priv enum Kind {
  KConst
  KStrTpl
  KField
  KBind
  KDyn
  KName
  KType
  KSeq
  KMethod
}

///|
/// One group per parsing context (JS G_* masks).
priv enum Group {
  GBool
  GText
  GComponent
  GSequence
  GProvide
  GField
  GValue
  GAll
}

///|
fn kind_of(val : Val) -> Kind? {
  match val {
    Const(..) => Some(KConst)
    // A placeholderless, non-macro template is a literal written the long
    // way and takes the single literal kind; a real placeholder makes it a
    // dynamic template confined to text/all contexts.
    StrTpl(_) => if val.is_literal() { Some(KConst) } else { Some(KStrTpl) }
    SeqAccess(..) => Some(KSeq)
    Field(_) => Some(KField)
    Method(_) => Some(KMethod)
    Bind(_) | BindMember(..) => Some(KBind)
    Dyn(_) => Some(KDyn)
    TypeName(_) => Some(KType)
    Name(_) | HandlerName(..) => Some(KName)
    Predicate(..) => None
  }
}

///|
fn in_group(kind : Kind, group : Group) -> Bool {
  match group {
    GBool => kind is (KField | KMethod | KBind | KDyn | KConst)
    GText => kind is (KField | KMethod | KBind | KDyn | KConst | KStrTpl)
    // `$m` is in every value-read group but never in a path-bearing one: a
    // method result has no addressable path.
    GComponent => kind is (KField | KSeq | KDyn)
    GSequence => kind is (KField | KDyn)
    GProvide => kind is (KField | KSeq)
    GField => kind is (KField | KMethod | KConst | KSeq)
    GValue => kind is (KField | KMethod | KBind | KDyn | KName | KType | KConst)
    GAll =>
      kind
      is (KField
      | KMethod
      | KBind
      | KDyn
      | KName
      | KType
      | KConst
      | KStrTpl
      | KSeq)
  }
}

///|
fn val_in_group(val : Val, group : Group) -> Bool {
  match kind_of(val) {
    Some(k) => in_group(k, group)
    None => false
  }
}

///|
/// An identifier: a letter then letters/digits/underscores, with an optional
/// trailing `?` (lets predicate names parse as ordinary Name tokens).
fn is_valid_val_id(s : String) -> Bool {
  let chars : Array[Char] = s.iter().collect()
  guard chars.get(0) is Some('a'..='z' | 'A'..='Z') else { return false }
  let mut i = 1
  while i < chars.length() &&
        chars[i] is ('a'..='z' | 'A'..='Z' | '0'..='9' | '_') {
    i = i + 1
  }
  if i < chars.length() && chars[i] == '?' {
    i = i + 1
  }
  i == chars.length()
}

///|
/// JS VALID_FLOAT_RE: ^-?[0-9]+(\.[0-9]+)?$
fn is_float_literal(s : String) -> Bool {
  let chars : Array[Char] = s.iter().collect()
  let mut i = if chars.get(0) is Some('-') { 1 } else { 0 }
  let int_start = i
  while i < chars.length() && chars[i] is ('0'..='9') {
    i = i + 1
  }
  if i == int_start {
    return false
  }
  if i < chars.length() && chars[i] == '.' {
    i = i + 1
    let frac_start = i
    while i < chars.length() && chars[i] is ('0'..='9') {
      i = i + 1
    }
    if i == frac_start {
      return false
    }
  }
  i == chars.length()
}

///|
fn const_str(s : String) -> Val {
  Const(lit=LStr(s), from_macro=false)
}

///|
pub fn parse_token(s : String, ctx : ParseCtx) -> Val? {
  guard s.get_char(0) is Some(c0) else { return None }
  // Quoted tokens first: their brackets/braces are literal content.
  if c0 == '\'' {
    // '…' string literal
    return if s.length() >= 2 && s.get_char(s.length() - 1) is Some('\'') {
      Some(const_str(unescape_str(s[1:s.length() - 1].to_owned())))
    } else {
      None
    }
  }
  if c0 == '$' && s.get_char(1) is Some('\'') {
    // $'…' string template
    return if s.length() >= 3 && s.get_char(s.length() - 1) is Some('\'') {
      Some(parse_str_tpl(s[2:s.length() - 1].to_owned(), ctx))
    } else {
      None
    }
  }
  // Sequence access `.seq[.key]` — before the prefix switch, the token
  // starts with the `.` of its left-hand field.
  if s.contains("[") || s.contains("]") {
    return parse_seq_access(s, ctx)
  }
  // A bare `{…}` is not a template; use `$'…'`.
  if s.contains("{") || s.contains("}") {
    return None
  }
  match c0 {
    '^' => {
      // ^name macro variable: re-tokenize + re-parse the bound source. A
      // constant result is marked from_macro so an enclosing template isn't
      // mistaken for a hand-written placeholderless literal.
      let name = s[1:].to_owned()
      match ctx.macro_vars.get(name) {
        Some(new_s) => {
          let tokens = tokenize_value(new_s.trim().to_owned())
          if tokens.length() != 1 {
            return None
          }
          match parse_token(tokens[0], ctx) {
            Some(Const(lit~, ..)) => Some(Const(lit~, from_macro=true))
            other => other
          }
        }
        None => {
          ctx.issue(BadMacroVar, s)
          None
        }
      }
    }
    '$' => mk_id(s[1:].to_owned(), n => Method(n))
    '@' => {
      // @name bind, or @name.member — one-level member read on a binding.
      let rest = s[1:].to_owned()
      match find_char(rest, '.') {
        None => mk_id(rest, n => Bind(n))
        Some(dot) => {
          let name = rest[0:dot].to_owned()
          let member_name = rest[dot + 1:].to_owned()
          if is_valid_val_id(name) && is_valid_val_id(member_name) {
            Some(BindMember(name~, prop=member_name))
          } else {
            None
          }
        }
      }
    }
    '*' => mk_id(s[1:].to_owned(), n => Dyn(n))
    '.' => mk_id(s[1:].to_owned(), n => Field(n))
    _ => {
      if is_float_literal(s) {
        let n : Double = @string.from_str(s) catch { _ => return None }
        return Some(Const(lit=LNum(n), from_macro=false))
      }
      if s == "true" || s == "false" {
        return Some(Const(lit=LBool(s == "true"), from_macro=false))
      }
      if c0 is ('a'..='z') {
        return mk_id(s, n => Name(n))
      }
      if c0 is ('A'..='Z') {
        return mk_id(s, n => TypeName(n))
      }
      None
    }
  }
}

///|
fn mk_id(name : String, make : (String) -> Val) -> Val? {
  if is_valid_val_id(name) {
    Some(make(name))
  } else {
    None
  }
}

///|
fn find_char(s : String, c : Char) -> Int? {
  let mut i = 0
  for ch in s {
    if ch == c {
      return Some(i)
    }
    i = i + 1
  }
  None
}

///|
/// `seq[key]`: exactly one `[`, a closing `]` as the last char, both sides
/// plain fields. Anything else (nested/unbalanced brackets) is rejected.
fn parse_seq_access(s : String, ctx : ParseCtx) -> Val? {
  let chars : Array[Char] = s.iter().collect()
  let mut open = -1
  let mut second_open = -1
  let mut close = -1
  for i in 0..<chars.length() {
    match chars[i] {
      '[' =>
        if open == -1 {
          open = i
        } else if second_open == -1 {
          second_open = i
        }
      ']' => if close == -1 { close = i }
      _ => ()
    }
  }
  if open < 1 ||
    close != chars.length() - 1 ||
    close < open ||
    second_open != -1 {
    return None
  }
  let left = parse_token(s[0:open].to_owned(), ctx)
  let right = parse_token(s[open + 1:close].to_owned(), ctx)
  match (left, right) {
    (Some(Field(seq)), Some(Field(key))) => Some(SeqAccess(seq~, key~))
    _ => None
  }
}

///|
/// The interior of `$'…'`: unescape once, split on `{…}` groups (text
/// between becomes constants, brace interiors parse via parse_text), then
/// trim empty constant bookends — keeping macro-var-bound empties, which are
/// real placeholders the linter must see.
fn parse_str_tpl(s : String, ctx : ParseCtx) -> Val {
  let interior = unescape_str(s)
  let chars : Array[Char] = interior.iter().collect()
  let vals : Array[Val?] = []
  let text = StringBuilder::new()
  fn flush_text() {
    vals.push(Some(const_str(text.to_string())))
    text.reset()
  }

  let mut i = 0
  while i < chars.length() {
    if chars[i] == '{' {
      // Find the first `}`; a group needs at least one interior char.
      let mut j = i + 1
      while j < chars.length() && chars[j] != '}' {
        j = j + 1
      }
      if j < chars.length() && j > i + 1 {
        flush_text()
        let expr = StringBuilder::new()
        for k in (i + 1)..<j {
          expr.write_char(chars[k])
        }
        vals.push(parse_text(expr.to_string(), ctx))
        i = j + 1
        continue
      }
    }
    text.write_char(chars[i])
    i = i + 1
  }
  flush_text()
  // Trim empty Const bookends left by the split.
  fn trimmable(v : Val?) -> Bool {
    v is Some(Const(lit=LStr(""), from_macro=false))
  }

  let mut lo = 0
  let mut hi = vals.length()
  while lo < hi && trimmable(vals[lo]) {
    lo = lo + 1
  }
  while hi > lo && trimmable(vals[hi - 1]) {
    hi = hi - 1
  }
  StrTpl(
    if lo == 0 && hi == vals.length() {
      vals
    } else {
      vals[lo:hi].to_owned()
    },
  )
}

///|
/// Parse `s` as a single value and accept it only if its kind is in `group`.
fn parse_single(s : String, ctx : ParseCtx, group : Group) -> Val? {
  let tokens = tokenize_value(s.trim().to_owned())
  if tokens.length() != 1 {
    return None
  }
  match parse_token(tokens[0], ctx) {
    Some(val) => if val_in_group(val, group) { Some(val) } else { None }
    None => None
  }
}

///|
pub fn parse_bool(s : String, ctx : ParseCtx) -> Val? {
  let t = s.trim().to_owned()
  let tokens = tokenize_value(t)
  if tokens.length() != 1 {
    return if tokens.length() == 0 {
      None
    } else {
      parse_predicate(t, tokens, ctx)
    }
  }
  match parse_token(tokens[0], ctx) {
    Some(val) => if val_in_group(val, GBool) { Some(val) } else { None }
    None => None
  }
}

///|
pub fn parse_text(s : String, ctx : ParseCtx) -> Val? {
  parse_single(s, ctx, GText)
}

///|
pub fn parse_component(s : String, ctx : ParseCtx) -> Val? {
  parse_single(s, ctx, GComponent)
}

///|
pub fn parse_sequence(s : String, ctx : ParseCtx) -> Val? {
  parse_single(s, ctx, GSequence)
}

///|
pub fn parse_field(s : String, ctx : ParseCtx) -> Val? {
  parse_single(s, ctx, GField)
}

///|
pub fn parse_provide(s : String, ctx : ParseCtx) -> Val? {
  parse_single(s, ctx, GProvide)
}

///|
pub fn parse_handler_arg(s : String, ctx : ParseCtx) -> Val? {
  parse_single(s, ctx, GValue)
}

///|
pub fn parse_macro_attr(s : String, ctx : ParseCtx) -> Val? {
  parse_single(s, ctx, GAll)
}

///|
pub fn parse_input_handler(s : String, ctx : ParseCtx) -> HandlerParse? {
  parse_handler(s, ctx, Input, allow_args=true, report=true)
}

///|
pub fn parse_alter_handler(s : String, ctx : ParseCtx) -> Val? {
  match parse_handler(s, ctx, Alter, allow_args=false, report=false) {
    Some(h) => Some(h.handler)
    None => None
  }
}

///|
/// `$name` → Method (dispatched via eval_as_handler); bare name →
/// HandlerName. No field syntax: a `.field` cannot be a handler.
fn parse_handler(
  s : String,
  ctx : ParseCtx,
  ns : HandlerNamespace,
  allow_args~ : Bool,
  report~ : Bool,
) -> HandlerParse? {
  let tokens = tokenize_value(s.trim().to_owned())
  let head_tok = tokens.get(0).unwrap_or("")
  let head : Val? = if head_tok == "" {
    None
  } else {
    parse_token(head_tok, ctx)
  }
  let handler : Val = match head {
    Some(Method(_) as m) => m
    Some(Name(name)) => HandlerName(name~, ns~)
    _ => {
      if report {
        ctx.issue(BadHandlerName, head_tok)
      }
      return None
    }
  }
  if !allow_args {
    return if tokens.length() == 1 { Some({ handler, args: [] }) } else { None }
  }
  let args : Array[Val] = []
  for i in 1..<tokens.length() {
    let tok = tokens[i]
    match parse_token(tok, ctx) {
      Some(val) if val_in_group(val, GValue) => args.push(val)
      _ => {
        if report {
          ctx.issue(BadHandlerArg, tok)
        }
        // The JS shared NULL_CONST_VAL sentinel.
        args.push(Const(lit=LNull, from_macro=false))
      }
    }
  }
  Some({ handler, args })
}

///|
/// Head token is the predicate, tail are its args parsed individually as
/// boolean-group values (tokens.length > 1 here).
fn parse_predicate(s : String, tokens : Array[String], ctx : ParseCtx) -> Val? {
  let pred_name = tokens[0]
  guard Pred::of_name(pred_name) is Some(pred) else {
    ctx.issue(UnknownPredicate, pred_name)
    return None
  }
  let arity = tokens.length() - 1
  if arity != pred.arity() {
    ctx.issue(PredicateArity(pred), s)
    return None
  }
  let args : Array[Val] = []
  for i in 1..<=arity {
    let tok = tokens[i]
    match parse_token(tok, ctx) {
      Some(val) if val_in_group(val, GBool) => args.push(val)
      _ => {
        ctx.issue(BadPredicateArg, tok)
        return None
      }
    }
  }
  Some(Predicate(pred~, args~))
}
