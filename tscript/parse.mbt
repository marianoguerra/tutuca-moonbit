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
  self.issues.push({ kind: BadValue, role, value, span, })
}

///|
/// Whether this expression may stand in `pos`.
///
/// The table is `core`'s (`Position`, `Expr::admitted_in`) and this is the one
/// call that reads it for the answer a slot's caller wants: a yes or a no, with
/// the sentence — when there is one — reported as a bad-expression issue
/// against the span the form covers.
fn val_in_position(val : @tutuca.Val, pos : @tutuca.Position) -> Bool {
  val.admitted_in(pos) is Admitted
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
fn const_str(s : String, span : Span) -> @tutuca.Val {
  @tutuca.Expr::lit(LStr(s), span~)
}

///|
/// The public entry: a bare string with no position of its own, so anything
/// it reports spans the whole of it.
pub fn parse_token(s : String, ctx : ParseCtx) -> @tutuca.Val? {
  parse_tok({ text: s, span: { start: 0, end_: s.to_array().length(), }, }, ctx)
}

///|
/// One token into the richest @tutuca.Val it can be, reporting against its span.
fn parse_tok(tok : Token, ctx : ParseCtx) -> @tutuca.Val? {
  let s = tok.text
  let span = tok.span
  guard s.get_char(0) is Some(c0) else { return None }
  // Quoted tokens first: their brackets/braces are literal content.
  if c0 == '\'' {
    // '…' string literal
    return if s.length() >= 2 && s.get_char(s.length() - 1) is Some('\'') {
      Some(const_str(unescape_str(s[1:s.length() - 1].to_owned()), span))
    } else {
      None
    }
  }
  if c0 == '$' && s.get_char(1) is Some('\'') {
    // $'…' string template
    return if s.length() >= 3 && s.get_char(s.length() - 1) is Some('\'') {
      Some(parse_str_tpl(s[2:s.length() - 1].to_owned(), ctx, span))
    } else {
      None
    }
  }
  // Sequence access `.seq[.key]` — before the prefix switch, the token
  // starts with the `.` of its left-hand field.
  if s.contains("[") || s.contains("]") {
    return parse_seq_access(s, ctx, span)
  }
  // A bare `{…}` is not a template; use `$'…'`.
  if s.contains("{") || s.contains("}") {
    return None
  }
  match c0 {
    '^' => resolve_macro_var(s[1:].to_owned(), s, tok.span, ctx)
    '$' =>
      if s.get_char(1) is Some('$') {
        resolve_config_var(s[2:].to_owned(), s, tok.span, ctx)
      } else {
        mk_id(s[1:].to_owned(), n => @tutuca.Expr::method_(n, span~))
      }
    '@' => {
      // @name bind, or @name.member — one-level member read on a binding.
      let rest = s[1:].to_owned()
      match find_char(rest, '.') {
        None => mk_id(rest, n => @tutuca.Expr::bind(n, span~))
        Some(dot) => {
          let name = rest[0:dot].to_owned()
          let member_name = rest[dot + 1:].to_owned()
          if is_valid_val_id(name) && is_valid_val_id(member_name) {
            Some(@tutuca.Expr::bind_member(name, member_name, span~))
          } else {
            None
          }
        }
      }
    }
    '*' => mk_id(s[1:].to_owned(), n => @tutuca.Expr::dyn_(n, span~))
    '.' => mk_id(s[1:].to_owned(), n => @tutuca.Expr::field(n, span~))
    _ => {
      if is_float_literal(s) {
        let n : Double = @string.from_str(s) catch { _ => return None }
        return Some(@tutuca.Expr::lit(LNum(n), span~))
      }
      if s == "true" || s == "false" {
        return Some(@tutuca.Expr::lit(LBool(s == "true"), span~))
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
          Some(@tutuca.Expr::event_path(segments, span~))
        }
      }
      if c0 is ('a'..='z') {
        return mk_id(s, n => @tutuca.Expr::name(n, span~))
      }
      if c0 is ('A'..='Z') {
        return mk_id(s, n => @tutuca.Expr::type_name(n, span~))
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
fn parse_seq_access(s : String, ctx : ParseCtx, span : Span) -> @tutuca.Val? {
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
    (Some(l), Some(r)) =>
      match (l.as_field(), r.as_field()) {
        (Some(seq), Some(key)) =>
          Some(@tutuca.Expr::seq_access(seq, key, span~))
        _ => None
      }
    _ => None
  }
}

///|
/// The interior of `$'…'`: unescape once, split on `{…}` groups (text
/// between becomes constants, brace interiors parse via parse_text), then
/// trim empty constant bookends — keeping macro-var-bound empties, which are
/// real placeholders the linter must see.
fn parse_str_tpl(s : String, ctx : ParseCtx, span : Span) -> @tutuca.Val {
  let interior = unescape_str(s)
  let chars : Array[Char] = interior.iter().collect()
  let parts : Array[@tutuca.TplPart] = []
  let text = StringBuilder()
  fn flush_text() {
    parts.push(TText(text=text.to_string(), from_macro=false))
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
        let expr = StringBuilder()
        for k in (i + 1)..<j {
          expr.write_char(chars[k])
        }
        // A placeholder that resolved to a STRING is text in the template that
        // holds it — it prints as text and reads as text — so it joins the
        // text case, carrying whose source it was.
        //
        // One that did not parse becomes an explicit NULL, which is the only
        // safe shape for a hole. It evaluates to the empty string, which is
        // what a hole always did; and it is not TEXT, which matters more —
        // `pinned_prefix` (`dyncomp/policy/external_url.mbt`) concatenates the
        // literal head of a template to decide whether it pins an origin, and
        // a hole that vanished would let `$'https://{$$unbound}.evil/'` read as
        // a literal `https://.evil/`. The parse issue was already recorded.
        match parse_text(expr.to_string(), ctx) {
          Some(ELit(lit=LStr(t), from_macro~, ..)) =>
            parts.push(TText(text=t, from_macro~))
          Some(v) => parts.push(TExpr(v))
          None => parts.push(TExpr(@tutuca.Expr::lit(LNull, span~)))
        }
        i = j + 1
        continue
      }
    }
    text.write_char(chars[i])
    i = i + 1
  }
  flush_text()
  // Trim empty text bookends left by the split — keeping macro-var-bound
  // empties, which are real placeholders the linter must see.
  fn trimmable(part : @tutuca.TplPart) -> Bool {
    part is TText(text="", from_macro=false)
  }

  let mut lo = 0
  let mut hi = parts.length()
  while lo < hi && trimmable(parts[lo]) {
    lo = lo + 1
  }
  while hi > lo && trimmable(parts[hi - 1]) {
    hi = hi - 1
  }
  @tutuca.Expr::tpl(
    if lo == 0 && hi == parts.length() {
      parts
    } else {
      parts[lo:hi].to_owned()
    },
    span~,
  )
}

///|
/// `^name` — re-tokenize and re-parse the source the CALLER bound.
///
/// A constant result is marked `from_macro` so an enclosing template is not
/// mistaken for a hand-written placeholderless literal — and, more to the
/// point, so it cannot pin a URL origin: the caller is the guest, and the
/// origin rule was only ever about the host (`dyncomp/policy/external_url.mbt`).
///
/// The expansion is required to be exactly ONE token. That is what makes a
/// `^name` usable where an operand goes: a single token cannot regroup the
/// expression around it.
///
/// `said` is the token as WRITTEN (`^name`), which is what a diagnostic quotes.
fn resolve_macro_var(
  name : String,
  said : String,
  at : Span,
  ctx : ParseCtx,
) -> @tutuca.Val? {
  match ctx.macro_vars.get(name) {
    Some(new_s) => {
      let tokens = tokenize(new_s)
      if tokens.length() != 1 {
        return None
      }
      // The expansion is parsed against THIS token's span: its own offsets
      // index the macro's source, which is a different file position than the
      // one the reader is looking at.
      match parse_tok({ text: tokens[0].text, span: at, }, ctx) {
        Some(ELit(lit~, span~, ..)) =>
          Some(@tutuca.Expr::lit(lit, from_macro=true, span~))
        other => other
      }
    }
    None => {
      ctx.issue(BadMacroVar, said, at)
      None
    }
  }
}

///|
/// `$$name` — a string the HOST bound, substituted here as a literal.
///
/// The mirror of `resolve_macro_var`, and the marking is the whole difference
/// between them. A `^name` constant is the CALLER's string wearing a literal's
/// shape, and the caller is the guest, so it is `from_macro=true` and cannot
/// pin a URL origin. A `$$name` constant is the HOST's string wearing a
/// literal's shape, and the host is the one party the origin rule was ever
/// about — so it is `from_macro=false` and pins, which is the point.
///
/// The value is substituted rather than re-parsed: it is text the host decided,
/// not source the guest wrote, and re-parsing it would let the host's table
/// smuggle in an expression nobody asked it for.
fn resolve_config_var(
  name : String,
  said : String,
  at : Span,
  ctx : ParseCtx,
) -> @tutuca.Val? {
  guard is_valid_val_id(name) else { return None }
  match ctx.config_vars.get(name) {
    Some(v) => Some(@tutuca.Expr::lit(LStr(v)))
    None => {
      ctx.issue(BadConfigVar, said, at)
      None
    }
  }
}

///|
/// Parse `s` as a single value and accept it only if its kind is in `group`.
fn parse_single(
  s : String,
  ctx : ParseCtx,
  pos : @tutuca.Position,
) -> @tutuca.Val? {
  // Not `s.trim()` first: the tokenizer already skips whitespace, and
  // trimming would shift every span off the string the caller handed in.
  let tokens = tokenize(s)
  if tokens.length() != 1 {
    return None
  }
  match parse_tok(tokens[0], ctx) {
    Some(val) => if val_in_position(val, pos) { Some(val) } else { None }
    None => None
  }
}

///|
/// A conditional slot: ONE expression, in the block's grammar.
///
/// A single token still goes through `parse_tok`, so `.isOpen`, `$canSubmit`
/// and `@isSelected` cost nothing and `^name` / `$$name` keep the substitution
/// semantics only that path implements. Anything longer is handed to
/// `parse_expr_source` and lowered — which is what makes a slot and a
/// block body the same language rather than two that resemble each other.
pub fn parse_bool(s : String, ctx : ParseCtx) -> @tutuca.Val? {
  let tokens = tokenize(s)
  if tokens.length() != 1 {
    if tokens.length() == 0 {
      return None
    }
    return parse_expression(s, ctx)
  }
  match parse_tok(tokens[0], ctx) {
    Some(val) =>
      if val_in_position(val, PosCondition) {
        Some(val)
      } else {
        None
      }
    None => None
  }
}

///|
/// The whole of a conditional slot, through the block grammar.
///
/// Spans index `s` directly: `parse_expr_source` tokenizes the attribute
/// value itself, so an operand's position is already the one the reader is
/// looking at and nothing is rebased.
fn parse_expression(s : String, ctx : ParseCtx) -> @tutuca.Val? {
  // `^name` and `$$name` reach here as ORDINARY OPERANDS, and the grammar has
  // a leaf for each. They are resolved by substitution during `resolve_expr`,
  // through the same two functions the single-token path calls, which is what
  // keeps one meaning per sigil rather than two that resemble each other.
  //
  // A `^name` expansion is required to be one token, so splicing it where an
  // operand goes cannot change the grouping around it; and `from_macro` rides
  // on the `Const` itself rather than on the shape above it, so an operator
  // over one does not lose the mark that decides whether it may pin a URL
  // origin (`dyncomp/policy/external_url.mbt`).
  let e = parse_expr_source(s) catch {
    err => {
      ctx.issue(
        BadExpression(why=err.message()),
        s.trim().to_owned(),
        err.span(),
      )
      return None
    }
  }
  resolve_expr(e, ctx, s, PosCondition)
}

///|
/// The slice a span covers. Spans index CHARACTERS, which is what `tokenize`
/// counts, so a diagnostic quotes what the author typed rather than a byte
/// range that happens to line up in ASCII.
fn slice_span(src : String, span : Span) -> String {
  let cs = src.to_array()
  let lo = if span.start < 0 { 0 } else { span.start }
  let hi = if span.end_ > cs.length() { cs.length() } else { span.end_ }
  if hi <= lo {
    return ""
  }
  let b = StringBuilder()
  for i in lo..<hi {
    b.write_char(cs[i])
  }
  b.to_string()
}

///|
/// An expression, resolved for the SLOT position it was written in.
///
/// Nothing is converted: a slot's value and a block's expression are the same
/// tree (`@tutuca.Expr`), and what used to be a lowering is now three things
/// that stayed.
///
///   - SUBSTITUTION. `^name` and `$$name` are replaced by what the caller and
///     the host bound, through the same two resolvers the single-token path
///     calls, so a `^name` in `empty? ^name` means exactly what a `^name`
///     alone means.
///   - ADMISSION. Whether a form may stand in a slot at all is `Position`'s
///     answer (`core/position.mbt`), and the sentence it carries names what to
///     write instead.
///   - NORMALIZATION. An operator chain and a `not` become applications of the
///     operator's own name. That is not a change of language — the vocabulary
///     is where an application's name resolves — and it is what keeps
///     `a and b and c` grouped the way `&&` groups it in the compiled backend.
fn resolve_expr(
  e : @tutuca.Expr,
  ctx : ParseCtx,
  src : String,
  pos : @tutuca.Position,
) -> @tutuca.Val? {
  fn refuse(why : String, span : Span) -> @tutuca.Val? {
    ctx.issue(BadExpression(why~), slice_span(src, span), span)
    None
  }

  // Substituted before it is judged: what a `^name` resolves to is what has to
  // stand here, and the leaf itself stands nowhere.
  match e {
    EMacroVar(name~, span~) =>
      return resolve_macro_var(name, "^" + name, span, ctx)
    EConfigVar(name~, span~) =>
      return resolve_config_var(name, "$$" + name, span, ctx)
    _ => ()
  }
  if e.admitted_in(pos) is Refused(why) {
    return refuse(why, e.span())
  }
  match e {
    EApp(name~, args~, span~) => resolve_app(name, args, span, ctx, src, pos)
    EUnary(op=UNot, operand~, span~) =>
      resolve_app("not", [operand], span, ctx, src, pos)
    // A chain is left-associative nested application. `a and b and c` is
    // `and (and a b) c`, which is the grouping `&&` gives it in the compiled
    // backend, so the two answer alike.
    EChain(ops~, operands~, span~, ..) => {
      let mut acc = match resolve_expr(operands[0], ctx, src, pos) {
        Some(v) => v
        None => return None
      }
      for i, op in ops {
        guard resolve_expr(operands[i + 1], ctx, src, pos) is Some(rhs) else {
          return None
        }
        acc = @tutuca.Expr::app(op, [acc, rhs], span~)
      }
      Some(acc)
    }
    // The block grammar has ONE bare-name leaf; a slot has two, because an
    // Uppercase name is a component type there and a type is in no value
    // position. Kept rather than refused here: letting it through means the
    // group check blames the ARGUMENT it sits in, which is the position the
    // reader is looking at.
    EName(name~, span~) =>
      match name.get_char(0) {
        Some('A'..='Z') => Some(@tutuca.Expr::type_name(name, span~))
        Some('a'..='z') => Some(e)
        _ => refuse("`\{name}` is not a name", span)
      }
    _ => Some(e)
  }
}

///|
/// An application, with its name checked against the one vocabulary and its
/// arity against that name's row.
fn resolve_app(
  name : String,
  args : Array[@tutuca.Expr],
  span : Span,
  ctx : ParseCtx,
  src : String,
  pos : @tutuca.Position,
) -> @tutuca.Val? {
  // The HEAD is what is unknown, so that is what the span covers — the name
  // sits at the start of the application, which is what makes this exact.
  let head : Span = {
    start: span.start,
    end_: span.start + name.to_array().length(),
  }
  guard @tutuca.builtin(name) is Some(b) else {
    ctx.issue(UnknownPredicate, name, head)
    return None
  }
  if args.length() != b.arity {
    // The whole application is what is wrong, so the span runs from the name
    // to the last argument rather than picking one of them to blame.
    ctx.issue(PredicateArity(name~, want=b.arity), slice_span(src, span), span)
    return None
  }
  let out : Array[@tutuca.Val] = []
  for a in args {
    guard resolve_expr(a, ctx, src, pos) is Some(v) else { return None }
    // An argument of an application is itself a condition: it reads a field, a
    // method, a binding, a dynamic, a constant or another application.
    guard val_in_position(v, PosCondition) else {
      let at = a.span()
      ctx.issue(BadPredicateArg, slice_span(src, at), at)
      return None
    }
    out.push(v)
  }
  Some(@tutuca.Expr::app(name, out, span~))
}

///|
pub fn parse_text(s : String, ctx : ParseCtx) -> @tutuca.Val? {
  parse_single(s, ctx, PosText)
}

///|
pub fn parse_component(s : String, ctx : ParseCtx) -> @tutuca.Val? {
  parse_single(s, ctx, PosComponent)
}

///|
pub fn parse_sequence(s : String, ctx : ParseCtx) -> @tutuca.Val? {
  parse_single(s, ctx, PosSequence)
}

///|
pub fn parse_field(s : String, ctx : ParseCtx) -> @tutuca.Val? {
  parse_single(s, ctx, PosField)
}

///|
pub fn parse_provide(s : String, ctx : ParseCtx) -> @tutuca.Val? {
  parse_single(s, ctx, PosProvide)
}

///|
pub fn parse_macro_attr(s : String, ctx : ParseCtx) -> @tutuca.Val? {
  parse_single(s, ctx, PosMacroAttr)
}

///|
pub fn parse_input_handler(s : String, ctx : ParseCtx) -> HandlerParse? {
  match parse_property_action(s, ctx) {
    Some(action) =>
      Some({
        handler: @tutuca.Expr::lit(LNull),
        args: [],
        action: Some(action),
      })
    None => parse_handler(s, ctx, PosEvent, allow_args=true, report=true)
  }
}

///|
/// Parse the one synchronous statement an event slot may carry. The block
/// parser remains the single grammar for assignments and collection methods;
/// this function only narrows its result to a direct component property.
fn parse_property_action(s : String, ctx : ParseCtx) -> PropertyAction? {
  let trimmed = s.trim()
  if !trimmed.has_prefix(".") {
    return None
  }
  let wrapped = "receive eventAction { " + s + " }"
  let parsed = parse_script(wrapped) catch { _ => return None }
  guard parsed is [decl] && decl.body is Stmts([stmt]) else { return None }
  match stmt {
    SAssign(place~, op~, value~, ..) if place.root is PState(name) &&
      place.steps.is_empty() => {
      if op is ASet && value is EName(name="default", ..) {
        return Some(PropertyReset(name))
      }
      guard resolve_action_expr(value, ctx, wrapped) is Some(rhs) else {
        return None
      }
      let assigned = match op {
        ASet => rhs
        AAdd => @tutuca.Expr::app("+", [@tutuca.Expr::field(name), rhs])
        ASub => @tutuca.Expr::app("-", [@tutuca.Expr::field(name), rhs])
      }
      Some(PropertySet(name~, value=assigned))
    }
    SMethod(place~, call~, args~, ..) if place.root is PState(name) &&
      place.steps.is_empty() => {
      let lowered : Array[@tutuca.Val] = []
      for arg in args {
        guard resolve_action_expr(arg, ctx, wrapped) is Some(v) else {
          return None
        }
        lowered.push(v)
      }
      Some(PropertyCall(name~, operation=call, args=lowered))
    }
    _ => None
  }
}

///|
/// Lower an event action operand. The block language sees `e.value` as a
/// parameter path; in an attribute it is instead the event value source.
fn resolve_action_expr(
  expr : @tutuca.Expr,
  ctx : ParseCtx,
  source : String,
) -> @tutuca.Val? {
  match expr {
    ERead(place={ root: PParam("e"), steps, .. }, ..) => {
      let path : Array[String] = []
      for step in steps {
        guard step is PField(name) else { return None }
        path.push(name)
      }
      if path.is_empty() {
        None
      } else {
        Some(@tutuca.Expr::event_path(path))
      }
    }
    _ => resolve_expr(expr, ctx, source, PosEventArg)
  }
}

///|
pub fn parse_alter_handler(s : String, ctx : ParseCtx) -> @tutuca.Val? {
  match parse_handler(s, ctx, PosTrigger, allow_args=false, report=false) {
    Some(h) => Some(h.handler)
    None => None
  }
}

///|
/// A handler slot: `$name`, or a bare name. No field syntax — a `.field`
/// cannot be a handler.
///
/// `pos` is `PosEvent` or `PosTrigger`, and it replaced a NAMESPACE the parsed
/// name used to carry. What the namespace said was which position the name was
/// written in, which the caller already knows — and what it decided,
/// downstream, was how the name is read, which is `Val::eval_as_handler`'s
/// question rather than the value's.
fn parse_handler(
  s : String,
  ctx : ParseCtx,
  pos : @tutuca.Position,
  allow_args~ : Bool,
  report~ : Bool,
) -> HandlerParse? {
  let tokens = tokenize(s)
  let head_tok : Token = tokens
    .get(0)
    .unwrap_or({ text: "", span: { start: 0, end_: 0, }, })
  let head : @tutuca.Val? = if head_tok.text == "" {
    None
  } else {
    parse_tok(head_tok, ctx)
  }
  let handler : @tutuca.Val = match head {
    Some(h) if val_in_position(h, pos) => h
    _ => {
      if report {
        ctx.issue(BadHandlerName, head_tok.text, head_tok.span)
      }
      return None
    }
  }
  if !allow_args {
    return if tokens.length() == 1 {
      Some({ handler, args: [], action: None, })
    } else {
      None
    }
  }
  let args : Array[@tutuca.Val] = []
  for i in 1..<tokens.length() {
    let tok = tokens[i]
    match parse_tok(tok, ctx) {
      Some(val) if val_in_position(val, PosEventArg) => args.push(val)
      _ => {
        if report {
          ctx.issue(BadHandlerArg, tok.text, tok.span)
        }
        // The shared null-const sentinel.
        args.push(@tutuca.Expr::lit(LNull))
      }
    }
  }
  Some({ handler, args, action: None, })
}
