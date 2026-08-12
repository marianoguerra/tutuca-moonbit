// The block language's parser. Implements the declares in script_spec.mbt.
//
// Recursive descent over `tokenize_script`'s stream. Two rules do most of the
// work, and both exist so a reader never has to hold a precedence table:
//
//   - **Application is juxtaposition.** A name followed by operands applies to
//     them. A name followed by a separator, an operator or a brace is just a
//     name. Which of the two it is therefore needs no lookahead into a symbol
//     table — arity is the CHECKER's question, and `.label = value` is a name
//     because a separator follows it, not because `value` is known to be a
//     parameter.
//   - **A chain is one family.** Operands joined by operators of one family
//     chain freely; a second family in the same unparenthesized chain is a
//     parse error naming the parentheses to add.
//
// Unary `-` and `not` are deliberately NOT operand starts in argument
// position, so `f - 1` is a subtraction rather than `f` applied to `-1`. An
// argument that wants either takes parentheses, which is the same rule as
// every other place precedence would otherwise be implicit.

///|
/// The parser's cursor over the token stream.
priv struct P {
  toks : Array[ScriptToken]
  mut at : Int
}

///|
fn P::peek(self : P) -> STok {
  self.toks[self.at].tok
}

///|
/// Whether the token at the cursor was separated from the one before it.
fn P::gap(self : P) -> Bool {
  self.toks[self.at].pre_space
}

///|
fn P::peek_at(self : P, n : Int) -> STok {
  let i = self.at + n
  if i < self.toks.length() {
    self.toks[i].tok
  } else {
    TEof
  }
}

///|
fn P::span(self : P) -> Span {
  self.toks[self.at].span
}

///|
fn P::bump(self : P) -> ScriptToken {
  let t = self.toks[self.at]
  if self.at + 1 < self.toks.length() {
    self.at = self.at + 1
  }
  t
}

///|
/// The span from `from` to just before the cursor — what a whole construct
/// covers, for a diagnostic that is about the construct rather than a token
/// inside it.
fn P::since(self : P, from : Span) -> Span {
  let prev = if self.at > 0 { self.toks[self.at - 1].span } else { from }
  { start: from.start, end_: prev.end_ }
}

///|
/// How a token reads in a message.
fn tok_name(t : STok) -> String {
  match t {
    TLBrace => "`{`"
    TRBrace => "`}`"
    TLParen => "`(`"
    TRParen => "`)`"
    TLBracket => "`[`"
    TRBracket => "`]`"
    TComma => "`,`"
    TSep => "the end of the statement"
    TDot => "`.`"
    TAt => "`@`"
    TDollar => "`$`"
    TCaret => "`^`"
    TAmp => "`&`"
    TAssign => "`=`"
    TPlusAssign => "`+=`"
    TMinusAssign => "`-=`"
    TOp(o) => "`\{o}`"
    TIdent(n) => "`\{n}`"
    TNum(_) => "a number"
    TStr(_) => "a string"
    TTpl(_) => "a string template"
    TDoc(_) => "a doc comment"
    TEof => "the end of the block"
  }
}

///|
fn[T] P::fail(self : P, want : String) -> T raise ScriptError {
  raise Unexpected(got=tok_name(self.peek()), want~, span=self.span())
}

///|
fn P::expect(self : P, t : STok, want : String) -> Unit raise ScriptError {
  if self.peek() == t {
    self.bump() |> ignore
  } else {
    self.fail(want)
  }
}

///|
fn P::ident(self : P, want : String) -> (String, Span) raise ScriptError {
  match self.peek() {
    TIdent(n) => {
      let t = self.bump()
      (n, t.span)
    }
    _ => self.fail(want)
  }
}

///|
/// Skip statement separators. Called wherever a construct may be preceded by
/// blank lines, which is everywhere a declaration or a statement can start.
fn P::skip_seps(self : P) -> Unit {
  while self.peek() is TSep {
    self.bump() |> ignore
  }
}

// ---------------------------------------------------------------------------
// The vocabulary

///|
/// The mutating collection methods, receiver-first, with their arity.
pub fn collection_method(name : String) -> Int? {
  match name {
    "push" | "deleteAt" | "add" | "remove" | "toggle" => Some(1)
    "insertAt" | "setAt" => Some(2)
    _ => None
  }
}

///|
/// The effects, and the fewest arguments each takes.
pub fn effect_min_arity(name : String) -> Int? {
  match name {
    "stop" => Some(0)
    "request" => Some(1)
    // A name plus whatever the message carries.
    "send" | "bubble" => Some(1)
    // A place, then a name, then the payload.
    "sendAt" => Some(2)
    _ => None
  }
}

///|
/// The source spelling of a kind — for a message, and for the printer.
pub fn kind_word(k : DeclKind) -> String {
  match k {
    DOn => "on"
    DReceive => "receive"
    DBubble => "bubble"
    DResponse => "response"
    DCompute => "compute"
    DPred => "pred"
    DEnrich => "enrich"
    DEnrichScope => "enrichScope"
  }
}

///|
fn kind_of_word(w : String) -> DeclKind? {
  match w {
    "on" => Some(DOn)
    "receive" => Some(DReceive)
    "bubble" => Some(DBubble)
    "response" => Some(DResponse)
    "compute" => Some(DCompute)
    "pred" => Some(DPred)
    "enrich" => Some(DEnrich)
    "enrichScope" => Some(DEnrichScope)
    _ => None
  }
}

///|
/// True when a declaration's body holds statements rather than one expression.
fn kind_takes_stmts(k : DeclKind) -> Bool {
  match k {
    DCompute | DPred => false
    _ => true
  }
}

///|
fn family_of(op : String) -> OpFamily {
  match op {
    "and" | "or" => FLogic
    "implies" => FImplies
    "is" | "is not" | "<" | "<=" | ">" | ">=" => FCompare
    "+" | "-" => FAdd
    _ => FMul
  }
}

///|
fn family_name(f : OpFamily) -> String {
  match f {
    FLogic => "logical"
    FCompare => "comparison"
    FImplies => "implication"
    FAdd => "additive"
    FMul => "multiplicative"
  }
}

///|
/// A family whose operators take exactly two operands, so `a < b < c` and
/// `a implies b implies c` are refused rather than silently associated.
fn is_binary_only(f : OpFamily) -> Bool {
  f is (FCompare | FImplies)
}

// ---------------------------------------------------------------------------
// Declarations

///|
pub fn parse_script(source : String) -> Array[Decl] raise ScriptError {
  let p : P = { toks: tokenize_script(source), at: 0 }
  let out : Array[Decl] = []
  // One name per bucket: a name answered twice is refused rather than ordered,
  // in the spirit of `Path::update`'s "one lookup, by exact name, with no
  // fallback sentinel behind it".
  let seen : Map[String, Unit] = Map([])
  for ;; {
    p.skip_seps()
    if p.peek() is TEof {
      break
    }
    let d = parse_decl(p)
    let key = kind_word(d.kind) + "/" + d.name
    if seen.contains(key) {
      raise DuplicateDecl(name=d.name, span=d.name_span)
    }
    seen[key] = ()
    out.push(d)
  }
  out
}

///|
fn parse_decl(p : P) -> Decl raise ScriptError {
  // Consecutive `///` lines are ONE doc comment. They arrive as separate
  // tokens with a separator between, because a newline is a token here — so
  // the joining is the parser's, and the lexer stays a lexer.
  let doc_lines : Array[String] = []
  while p.peek() is TDoc(text) {
    doc_lines.push(text)
    p.bump() |> ignore
    p.skip_seps()
  }
  let doc = doc_lines.join("\n")
  let from = p.span()
  let (word, word_span) = match p.peek() {
    TIdent(w) => {
      let t = p.bump()
      (w, t.span)
    }
    _ =>
      p.fail(
        "a declaration: on, receive, bubble, response, compute, pred, enrich or enrichScope",
      )
  }
  guard kind_of_word(word) is Some(kind) else {
    raise UnknownKind(got=word, span=word_span)
  }
  let (name, name_span) = p.ident("the name this declaration answers")
  let params : Array[Param] = []
  if p.peek() is TLParen {
    p.bump() |> ignore
    if !(p.peek() is TRParen) {
      for ;; {
        let (pn, ps) = p.ident("a parameter name")
        params.push({ name: pn, span: ps })
        if p.peek() is TComma {
          p.bump() |> ignore
          continue
        }
        break
      }
    }
    p.expect(TRParen, "`)` closing the parameter list")
  }
  let body = parse_body(p, stmts=kind_takes_stmts(kind))
  { kind, name, params, body, doc, span: p.since(from), name_span }
}

///|
/// A braced body. `stmts` is the SLOT's decision, not the body's: a handler
/// slot takes statements and a value slot takes one expression.
fn parse_body(p : P, stmts~ : Bool) -> Body raise ScriptError {
  p.expect(TLBrace, "`{` opening the body")
  if stmts {
    let ss = parse_stmts(p)
    p.expect(TRBrace, "`}` closing the body")
    Stmts(ss)
  } else {
    p.skip_seps()
    let e = parse_expr(p)
    p.skip_seps()
    p.expect(TRBrace, "`}` closing the body")
    Value(e)
  }
}

///|
pub fn parse_slot_body(
  source : String,
  stmts~ : Bool,
) -> Body raise ScriptError {
  let p : P = { toks: tokenize_script(source), at: 0 }
  p.skip_seps()
  let b = parse_body(p, stmts~)
  p.skip_seps()
  if !(p.peek() is TEof) {
    p.fail("the end of the body")
  }
  b
}

// ---------------------------------------------------------------------------
// Statements

///|
fn parse_stmts(p : P) -> Array[Stmt] raise ScriptError {
  let out : Array[Stmt] = []
  for ;; {
    p.skip_seps()
    if p.peek() is (TRBrace | TEof) {
      break
    }
    out.push(parse_stmt(p))
    // A statement ends at a separator or at the closing brace; anything else
    // means the statement did not finish where the author thought it did.
    if p.peek() is (TRBrace | TEof) {
      break
    }
    if p.peek() is TSep {
      continue
    }
    p.fail("the end of the statement — a newline or a `;`")
  }
  out
}

///|
fn parse_stmt(p : P) -> Stmt raise ScriptError {
  let from = p.span()
  // `if cond { … } else { … }`
  if p.peek() is TIdent("if") {
    p.bump() |> ignore
    let cond = parse_expr(p)
    let then_ = parse_stmt_block(p)
    let else_ : Array[Stmt] = if p.peek() is TIdent("else") {
      p.bump() |> ignore
      parse_stmt_block(p)
    } else {
      []
    }
    return SIf(cond~, then_~, else_~, span=p.since(from))
  }
  // An effect: a bare name the effect table knows.
  if p.peek() is TIdent(name) && effect_min_arity(name) is Some(min) {
    p.bump() |> ignore
    let args : Array[Expr] = []
    // `sendAt`'s first argument is a PLACE, and it is the only position in the
    // language where `&` is legal.
    if name == "sendAt" && p.peek() is TAmp {
      let amp = p.span()
      p.bump() |> ignore
      let place = parse_place(p, for_ref=true)
      args.push(ERef(place~, span={ start: amp.start, end_: place.span.end_ }))
    }
    while starts_argument(p.peek()) {
      args.push(parse_atom(p))
    }
    // `&` is not an argument start, so it lands here rather than in
    // `parse_operand`. Saying what it actually is beats "unexpected token".
    if p.peek() is TAmp {
      raise MisplacedRef(span=p.span())
    }
    if args.length() < min {
      raise Unexpected(
        got="\{args.length()} argument(s)",
        want="at least \{min} for `\{name}`",
        span=p.since(from),
      )
    }
    return SEffect(name~, args~, span=p.since(from))
  }
  // Otherwise it is a place: an assignment, or a collection method on it.
  if !(p.peek() is (TDot | TAt)) {
    p.fail(
      "a statement: an assignment, a collection method, an effect or an `if`",
    )
  }
  let place = parse_place(p, for_ref=false)
  let assign : AssignOp? = match p.peek() {
    TAssign => Some(ASet)
    TPlusAssign => Some(AAdd)
    TMinusAssign => Some(ASub)
    _ => None
  }
  match assign {
    Some(op) => {
      p.bump() |> ignore
      let value = parse_expr(p)
      SAssign(place~, op~, value~, span=p.since(from))
    }
    None => {
      // A method call, so the last step has to BE the method: `.items.push`
      // is the `items` place and the `push` method, and there is nothing else
      // a place followed by operands could mean.
      guard place.steps.last() is Some(PField(m_name)) else {
        p.fail("`=`, `+=`, `-=`, or a collection method on this place")
      }
      guard collection_method(m_name) is Some(arity) else {
        raise Unexpected(
          got="`\{m_name}`",
          want="a collection method: push, insertAt, setAt, deleteAt, add, remove or toggle",
          span=place.span,
        )
      }
      let receiver : Place = {
        root: place.root,
        steps: place.steps[0:place.steps.length() - 1].to_owned(),
        span: place.span,
      }
      let args : Array[Expr] = []
      while starts_argument(p.peek()) {
        args.push(parse_atom(p))
      }
      if args.length() != arity {
        raise Unexpected(
          got="\{args.length()} argument(s)",
          want="\{arity} for `\{m_name}`",
          span=p.since(from),
        )
      }
      SMethod(place=receiver, call=m_name, args~, span=p.since(from))
    }
  }
}

///|
fn parse_stmt_block(p : P) -> Array[Stmt] raise ScriptError {
  p.expect(TLBrace, "`{` opening the branch")
  let ss = parse_stmts(p)
  p.expect(TRBrace, "`}` closing the branch")
  ss
}

// ---------------------------------------------------------------------------
// Places

///|
/// `.field`, `.a.b`, `.rows[k].note`, `@value`, `@value.completed`.
///
/// `for_ref` applies the one constraint the runtime `Path` imposes: a step is
/// field-then-key, so `&.a[0][1]` has no representation. A plain READ is not
/// constrained, because the MoonBit backend rebuilds the struct and never
/// builds a `Path` at all.
fn parse_place(p : P, for_ref~ : Bool) -> Place raise ScriptError {
  let from = p.span()
  let root : PlaceRoot = match p.peek() {
    TDot => {
      p.bump() |> ignore
      let (n, _) = p.ident("a state field after `.`")
      PState(n)
    }
    TAt => {
      p.bump() |> ignore
      let (n, _) = p.ident("a binding name after `@`")
      PBind(n)
    }
    _ => p.fail("a place: `.field` or `@binding`")
  }
  let steps : Array[PathStep] = []
  let mut prev_was_index = false
  for ;; {
    match p.peek() {
      // `.name` continues the path — but only when it is ATTACHED, and only
      // when a name follows. Detached, it is the next ARGUMENT: `min .a .b`
      // is two operands and `.a.b` is one place, and whitespace is the only
      // thing that tells them apart.
      TDot =>
        if !p.gap() && p.peek_at(1) is TIdent(n) {
          p.bump() |> ignore
          p.bump() |> ignore
          steps.push(PField(n))
          prev_was_index = false
        } else {
          break
        }
      TLBracket => {
        if p.gap() {
          break
        }
        let br = p.span()
        if for_ref && prev_was_index {
          raise BadPlace(
            why="a path step is a field and then a key, so two keys in a row have no step — write `.a[0].b[1]`",
            span=br,
          )
        }
        p.bump() |> ignore
        let key = parse_expr(p)
        p.expect(TRBracket, "`]` closing the key")
        steps.push(PIndex(key))
        prev_was_index = true
      }
      _ => break
    }
  }
  { root, steps, span: p.since(from) }
}

// ---------------------------------------------------------------------------
// Expressions

///|
/// Whether a token can begin an ARGUMENT of a juxtaposed application.
///
/// `-`, `not` and `*` are excluded on purpose: with them admitted, `f - 1`
/// would be `f` applied to `-1` and `a * b` would be `a` applied to `*b`, so
/// in each case the commoner reading would lose to the rarer one. One that
/// wants either takes parentheses — `clamp .x (-1) 5`, `len (*theme)` — which
/// is the same rule as everywhere else precedence would be implicit.
///
/// `^` is excluded because a macro variable inside a body is unexplored: `^x`
/// substitutes SOURCE TEXT, and what that means for a body that reads state is
/// an open question rather than something to answer by accident.
fn starts_argument(t : STok) -> Bool {
  match t {
    TNum(_) | TStr(_) | TTpl(_) | TDot | TAt | TDollar => true
    TLParen => true
    TIdent(_) => true
    _ => false
  }
}

///|
fn parse_expr(p : P) -> Expr raise ScriptError {
  let from = p.span()
  let first = parse_operand(p)
  guard p.peek() is TOp(op0) && op0 != "not" else { return first }
  // The family is read from the PEEKED operator: `chain_op` consumes, and
  // consuming here would eat the first operator before the loop below could.
  let family = family_of(op0)
  let operands : Array[Expr] = [first]
  let ops : Array[String] = []
  while p.peek() is TOp(_) && !(p.peek() is TOp("not")) {
    let op_span = p.span()
    let op = chain_op(p)
    let f = family_of(op)
    if f != family {
      raise MixedFamilies(
        first=family_name(family),
        second=family_name(f),
        span=op_span,
      )
    }
    ops.push(op)
    operands.push(parse_operand(p))
    if is_binary_only(family) && operands.length() > 2 {
      raise NonAssociative(op~, span=p.since(from))
    }
  }
  EChain(family~, ops~, operands~, span=p.since(from))
}

///|
/// Read one infix operator, folding `is not` into a single spelling so the
/// family table has one entry rather than a lookahead rule.
fn chain_op(p : P) -> String raise ScriptError {
  guard p.peek() is TOp(op) else { p.fail("an operator") }
  p.bump() |> ignore
  if op == "is" && p.peek() is TOp("not") {
    p.bump() |> ignore
    return "is not"
  }
  op
}

///|

///|
/// An operand: anything that can stand where a value is expected, INCLUDING a
/// juxtaposed application.
fn parse_operand(p : P) -> Expr raise ScriptError {
  parse_value(p, apply=true)
}

///|
/// An ARGUMENT of an application, which is never itself an application.
///
/// This is what makes juxtaposition unambiguous without a symbol table:
/// `.items.insertAt i v` is `insertAt` applied to two atoms, not `insertAt`
/// applied to `i v`. An argument that is itself an application takes
/// parentheses — `contains (lower .name) 'x'` — which is the rule the design
/// states and the same one that governs operators.
fn parse_atom(p : P) -> Expr raise ScriptError {
  parse_value(p, apply=false)
}

///|
fn parse_value(p : P, apply~ : Bool) -> Expr raise ScriptError {
  let from = p.span()
  match p.peek() {
    TOp("not") => {
      p.bump() |> ignore
      let e = parse_operand(p)
      EUnary(op=UNot, operand=e, span=p.since(from))
    }
    TOp("-") => {
      p.bump() |> ignore
      let e = parse_operand(p)
      EUnary(op=UNeg, operand=e, span=p.since(from))
    }
    TLParen => {
      p.bump() |> ignore
      let e = parse_expr(p)
      p.expect(TRParen, "`)` closing the group")
      e
    }
    TNum(v) => {
      p.bump() |> ignore
      ELit(lit=LNum(v), span=p.since(from))
    }
    TStr(sv) => {
      p.bump() |> ignore
      ELit(lit=LStr(sv), span=p.since(from))
    }
    TTpl(raw) => {
      p.bump() |> ignore
      ETpl(parts=parse_tpl_parts(raw, from), span=p.since(from))
    }
    TDot | TAt => {
      let place = parse_place(p, for_ref=false)
      ERead(place~, span=place.span)
    }
    TDollar => {
      p.bump() |> ignore
      let (n, _) = p.ident("a method name after `$`")
      EMethod(name=n, span=p.since(from))
    }
    TOp("*") => {
      p.bump() |> ignore
      let (n, _) = p.ident("a dynamic binding name after `*`")
      EDyn(name=n, span=p.since(from))
    }
    TAmp => raise MisplacedRef(span=from)
    TIdent("true") => {
      p.bump() |> ignore
      ELit(lit=LBool(true), span=p.since(from))
    }
    TIdent("false") => {
      p.bump() |> ignore
      ELit(lit=LBool(false), span=p.since(from))
    }
    TIdent("null") => {
      p.bump() |> ignore
      ELit(lit=LNull, span=p.since(from))
    }
    TIdent("if") if apply => {
      p.bump() |> ignore
      let cond = parse_expr(p)
      let then_ = parse_value_block(p)
      if !(p.peek() is TIdent("else")) {
        p.fail(
          "`else` — an `if` in a value position has to have a value either way",
        )
      }
      p.bump() |> ignore
      let else_ = parse_value_block(p)
      EIf(cond~, then_~, else_~, span=p.since(from))
    }
    TIdent(n) => {
      p.bump() |> ignore
      let args : Array[Expr] = []
      if apply {
        while starts_argument(p.peek()) {
          args.push(parse_atom(p))
        }
      }
      if args.is_empty() {
        EName(name=n, span=p.since(from))
      } else {
        EApp(name=n, args~, span=p.since(from))
      }
    }
    _ => p.fail("a value")
  }
}

///|
fn parse_value_block(p : P) -> Expr raise ScriptError {
  p.expect(TLBrace, "`{` opening the branch")
  p.skip_seps()
  let e = parse_expr(p)
  p.skip_seps()
  p.expect(TRBrace, "`}` closing the branch")
  e
}

///|
/// The interior of a `$'…'`: text and `{expr}` groups.
///
/// The one interpolation grammar the language has, and the same one a slot
/// template uses — `$'n={.count}'` means the same thing in both places, which
/// is why a predicate lifts out of a `@show` into a `pred` unchanged.
fn parse_tpl_parts(raw : String, at : Span) -> Array[TplPart] raise ScriptError {
  let chars : Array[Char] = raw.iter().collect()
  let out : Array[TplPart] = []
  let text = StringBuilder::new()
  let n = chars.length()
  let mut i = 0
  while i < n {
    if chars[i] == '{' {
      let mut j = i + 1
      while j < n && chars[j] != '}' {
        j = j + 1
      }
      if j < n && j > i + 1 {
        let s = text.to_string()
        if s != "" {
          out.push(TText(s))
        }
        text.reset()
        let inner = StringBuilder::new()
        for k in (i + 1)..<j {
          inner.write_char(chars[k])
        }
        // The interior is its own little expression. Its spans index the
        // interior, so they are rebased onto the template token — a column
        // inside an interpolation is not worth a second offset discipline.
        let ip : P = { toks: tokenize_script(inner.to_string()), at: 0 }
        let e = parse_expr(ip)
        if !(ip.peek() is TEof) {
          raise Unexpected(
            got=tok_name(ip.peek()),
            want="the end of the interpolation",
            span=at,
          )
        }
        out.push(TExpr(e))
        i = j + 1
        continue
      }
    }
    text.write_char(chars[i])
    i = i + 1
  }
  let s = text.to_string()
  if s != "" {
    out.push(TText(s))
  }
  out
}

// ---------------------------------------------------------------------------
// Diagnostics

///|
pub fn ScriptError::message(self : ScriptError) -> String {
  match self {
    Unexpected(got~, want~, ..) => "expected \{want}, found \{got}"
    MixedFamilies(first~, second~, ..) =>
      "a \{second} operator cannot join a \{first} chain without parentheses — write `(a \{first} b) …` to say which grouping you mean"
    NonAssociative(op~, ..) =>
      "`\{op}` takes exactly two operands, so a chain of them has no meaning — parenthesize the pair you mean"
    MisplacedRef(..) =>
      "`&` names a POSITION and is legal in exactly one place: the first argument of `sendAt`"
    BadPlace(why~, ..) => why
    UnknownKind(got~, ..) =>
      "`\{got}` is not a declaration kind — expected on, receive, bubble, response, compute, pred, enrich or enrichScope"
    DuplicateDecl(name~, ..) =>
      "`\{name}` is declared twice in this bucket; a name is answered once, by exact match, with nothing behind it"
  }
}

///|
pub fn ScriptError::span(self : ScriptError) -> Span {
  match self {
    Unexpected(span~, ..)
    | MixedFamilies(span~, ..)
    | NonAssociative(span~, ..)
    | MisplacedRef(span~)
    | BadPlace(span~, ..)
    | UnknownKind(span~, ..)
    | DuplicateDecl(span~, ..) => span
  }
}
