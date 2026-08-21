// Slot parsing. Implements the declares in
// spec.mbt. The kind bitmasks become an enum plus per-group membership
// matches; callers only see the named parse_* functions.
//
// Every diagnostic now carries the span of the TOKEN it is about, which is
// what lets `@show="empty? Foo"` point at `Foo` rather than at the attribute.
// Spans are token-level and stop there: a failure inside a `$'…'` placeholder
// reports the template token, because the interior is re-parsed from a
// substring and threading a base offset through that would buy a column in
// the one place the language has no operands to distinguish.

///|
pub fn ParseCtx::new(
  macro_vars? : Map[String, String],
  config_vars? : Map[String, String],
) -> ParseCtx {
  {
    macro_vars: macro_vars.unwrap_or(Map([])),
    config_vars: config_vars.unwrap_or(Map([])),
    issues: [],
  }
}

///|
fn ParseCtx::issue(
  self : ParseCtx,
  role : IssueRole,
  value : String,
  span : Span,
) -> Unit {
  self.issues.push({ kind: BadValue, role, value, span })
}

///|
/// One kind per parsed value (the K_* bits).
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
  /// A name applied to arguments. Admitted in the CONDITION group only: a
  /// condition slot asks a yes/no question, which is what an application
  /// answers, and a value slot spells a call with `$`. Widening it further is
  /// what the expression language does, not this table.
  KApp
  /// `e.<path>` — a read of the event being handled.
  ///
  /// Admitted in the EVENT ARGUMENT group and nowhere else, which is the whole
  /// of what makes it safe to have. A `@text="e.value"` would be a render-time
  /// read of an event that is not happening, and the group table below is
  /// where that is refused rather than in a special case somewhere.
  KEvent
}

///|
/// One group per parsing context (the G_* masks).
priv enum Group {
  GBool
  GText
  GComponent
  GSequence
  GProvide
  GField
  /// What an `@on` handler ARGUMENT may be.
  ///
  /// It is the ONE group an event read belongs to: a `@text="e.value"` would
  /// be a render-time read of an event that is not happening, and this table
  /// is where that is refused — not a special case somewhere downstream.
  GEventArg
  GAll
}

///|
fn kind_of(val : @tutuca.Val) -> Kind? {
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
    App(..) => Some(KApp)
    EventPath(_) => Some(KEvent)
  }
}

///|
fn in_group(kind : Kind, group : Group) -> Bool {
  match group {
    GBool => kind is (KField | KMethod | KBind | KDyn | KConst | KApp)
    GText => kind is (KField | KMethod | KBind | KDyn | KConst | KStrTpl)
    // `$m` is in every value-read group but never in a path-bearing one: a
    // method result has no addressable path.
    GComponent => kind is (KField | KSeq | KDyn)
    GSequence => kind is (KField | KDyn)
    GProvide => kind is (KField | KSeq)
    GField => kind is (KField | KMethod | KConst | KSeq)
    GEventArg =>
      kind
      is (KField | KMethod | KBind | KDyn | KName | KType | KConst | KEvent)
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
fn val_in_group(val : @tutuca.Val, group : Group) -> Bool {
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
/// Matches ^-?[0-9]+(\.[0-9]+)?$
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
fn const_str(s : String) -> @tutuca.Val {
  Const(lit=LStr(s), from_macro=false)
}

///|
/// The public entry: a bare string with no position of its own, so anything
/// it reports spans the whole of it.
pub fn parse_token(s : String, ctx : ParseCtx) -> @tutuca.Val? {
  parse_tok({ text: s, span: { start: 0, end_: s.to_array().length() } }, ctx)
}

///|
/// One token into the richest @tutuca.Val it can be, reporting against its span.
fn parse_tok(tok : Token, ctx : ParseCtx) -> @tutuca.Val? {
  let s = tok.text
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
          let tokens = tokenize(new_s)
          if tokens.length() != 1 {
            return None
          }
          // The expansion is parsed against THIS token's span: its own
          // offsets index the macro's source, which is a different file
          // position than the one the reader is looking at.
          match parse_tok({ text: tokens[0].text, span: tok.span }, ctx) {
            Some(Const(lit~, ..)) => Some(Const(lit~, from_macro=true))
            other => other
          }
        }
        None => {
          ctx.issue(BadMacroVar, s, tok.span)
          None
        }
      }
    }
    '$' =>
      if s.get_char(1) is Some('$') {
        // $$name config variable: a string the HOST bound, substituted here as
        // a literal. The mirror of `^name` above, and the marking is the whole
        // difference between them. A `^name` constant is the CALLER's string
        // wearing a literal's shape, and the caller is the guest, so it is
        // `from_macro=true` and cannot pin a URL origin. A `$$name` constant is
        // the HOST's string wearing a literal's shape, and the host is the one
        // party the origin rule was ever about — so it is `from_macro=false`
        // and pins, which is the point (dyncomp/policy/external_url.mbt).
        //
        // The value is substituted rather than re-parsed: it is text the host
        // decided, not source the guest wrote, and re-parsing it would let the
        // host's table smuggle in an expression nobody asked it for.
        let name = s[2:].to_owned()
        guard is_valid_val_id(name) else { return None }
        match ctx.config_vars.get(name) {
          Some(v) => Some(Const(lit=LStr(v), from_macro=false))
          None => {
            ctx.issue(BadConfigVar, s, tok.span)
            None
          }
        }
      } else {
        mk_id(s[1:].to_owned(), n => Method(n))
      }
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
      // `e.<path>` — a read of the event being handled. Recognized HERE, in
      // the bare-name arm, and only for the exact root `e.`: a field named
      // `each` or a name `event` is an ordinary name, and the check is on the
      // dot rather than on the prefix so it cannot swallow one.
      //
      // Every segment must be an identifier. `e.` with nothing after it, or a
      // segment that is not a name, is None — the caller reports it as a bad
      // handler argument, which is what it is.
      if s.has_prefix("e.") {
        let segments : Array[String] = []
        for seg in s[2:].to_owned().split(".") {
          let name = seg.to_owned()
          if !is_valid_val_id(name) {
            return None
          }
          segments.push(name)
        }
        return if segments.is_empty() {
          None
        } else {
          Some(EventPath(segments))
        }
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
fn mk_id(name : String, make : (String) -> @tutuca.Val) -> @tutuca.Val? {
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
fn parse_seq_access(s : String, ctx : ParseCtx) -> @tutuca.Val? {
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
fn parse_str_tpl(s : String, ctx : ParseCtx) -> @tutuca.Val {
  let interior = unescape_str(s)
  let chars : Array[Char] = interior.iter().collect()
  let vals : Array[@tutuca.Val?] = []
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
  fn trimmable(v : @tutuca.Val?) -> Bool {
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
fn parse_single(s : String, ctx : ParseCtx, group : Group) -> @tutuca.Val? {
  // Not `s.trim()` first: the tokenizer already skips whitespace, and
  // trimming would shift every span off the string the caller handed in.
  let tokens = tokenize(s)
  if tokens.length() != 1 {
    return None
  }
  match parse_tok(tokens[0], ctx) {
    Some(val) => if val_in_group(val, group) { Some(val) } else { None }
    None => None
  }
}

///|
pub fn parse_bool(s : String, ctx : ParseCtx) -> @tutuca.Val? {
  let tokens = tokenize(s)
  if tokens.length() != 1 {
    return if tokens.length() == 0 {
      None
    } else {
      // The trimmed source is what an arity message QUOTES; the spans it
      // reports with come from the tokens, which index `s` itself.
      parse_application(s.trim().to_owned(), tokens, ctx)
    }
  }
  match parse_tok(tokens[0], ctx) {
    Some(val) => if val_in_group(val, GBool) { Some(val) } else { None }
    None => None
  }
}

///|
pub fn parse_text(s : String, ctx : ParseCtx) -> @tutuca.Val? {
  parse_single(s, ctx, GText)
}

///|
pub fn parse_component(s : String, ctx : ParseCtx) -> @tutuca.Val? {
  parse_single(s, ctx, GComponent)
}

///|
pub fn parse_sequence(s : String, ctx : ParseCtx) -> @tutuca.Val? {
  parse_single(s, ctx, GSequence)
}

///|
pub fn parse_field(s : String, ctx : ParseCtx) -> @tutuca.Val? {
  parse_single(s, ctx, GField)
}

///|
pub fn parse_provide(s : String, ctx : ParseCtx) -> @tutuca.Val? {
  parse_single(s, ctx, GProvide)
}

///|
pub fn parse_macro_attr(s : String, ctx : ParseCtx) -> @tutuca.Val? {
  parse_single(s, ctx, GAll)
}

///|
pub fn parse_input_handler(s : String, ctx : ParseCtx) -> HandlerParse? {
  parse_handler(s, ctx, Receive, allow_args=true, report=true)
}

///|
pub fn parse_alter_handler(s : String, ctx : ParseCtx) -> @tutuca.Val? {
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
  ns : @tutuca.HandlerNamespace,
  allow_args~ : Bool,
  report~ : Bool,
) -> HandlerParse? {
  let tokens = tokenize(s)
  let head_tok : Token = tokens
    .get(0)
    .unwrap_or({ text: "", span: { start: 0, end_: 0 } })
  let head : @tutuca.Val? = if head_tok.text == "" {
    None
  } else {
    parse_tok(head_tok, ctx)
  }
  let handler : @tutuca.Val = match head {
    Some(Method(_) as m) => m
    Some(Name(name)) => HandlerName(name~, ns~)
    _ => {
      if report {
        ctx.issue(BadHandlerName, head_tok.text, head_tok.span)
      }
      return None
    }
  }
  if !allow_args {
    return if tokens.length() == 1 { Some({ handler, args: [] }) } else { None }
  }
  let args : Array[@tutuca.Val] = []
  for i in 1..<tokens.length() {
    let tok = tokens[i]
    match parse_tok(tok, ctx) {
      Some(val) if val_in_group(val, GEventArg) => args.push(val)
      _ => {
        if report {
          ctx.issue(BadHandlerArg, tok.text, tok.span)
        }
        // The shared null-const sentinel.
        args.push(Const(lit=LNull, from_macro=false))
      }
    }
  }
  Some({ handler, args })
}

///|
/// Head token names the callable, tail are its args parsed individually as
/// boolean-group values (tokens.length > 1 here).
///
/// The name resolves against the builtin vocabulary rather than a closed enum,
/// so the arity is looked up rather than matched. An argument is itself a
/// boolean-group value, which now includes another application — but only one
/// written as a single token, so nesting still needs the parenthesised grammar
/// the expression language brings rather than arriving here by accident.
fn parse_application(
  s : String,
  tokens : Array[Token],
  ctx : ParseCtx,
) -> @tutuca.Val? {
  let head = tokens[0]
  let name = head.text
  guard @tutuca.builtin(name) is Some(b) else {
    ctx.issue(UnknownPredicate, name, head.span)
    return None
  }
  let arity = tokens.length() - 1
  if arity != b.arity {
    // The whole application is what is wrong, so the span runs from the name
    // to the last argument rather than picking one of them to blame.
    let last = tokens[tokens.length() - 1]
    ctx.issue(PredicateArity(name~, want=b.arity), s, {
      start: head.span.start,
      end_: last.span.end_,
    })
    return None
  }
  let args : Array[@tutuca.Val] = []
  for i in 1..<=arity {
    let tok = tokens[i]
    match parse_tok(tok, ctx) {
      Some(val) if val_in_group(val, GBool) => args.push(val)
      _ => {
        ctx.issue(BadPredicateArg, tok.text, tok.span)
        return None
      }
    }
  }
  Some(App(name~, args~))
}
