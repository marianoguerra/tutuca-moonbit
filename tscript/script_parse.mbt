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
  /// Which declaration's body is being parsed.
  ///
  /// One question turns on it, and it is the one this family exists to settle:
  /// a `forward` in a `receive` body starts a walk and a `forward` in an
  /// `answer` body continues one. Those are two operations, so they are two
  /// words now — and the parser is where the position is known.
  mut decl_kind : DeclKind
  /// Retired spellings met on the way, in source order.
  ///
  /// A side channel rather than a field on the statement, because the AST is
  /// the CURRENT vocabulary and nothing below the parser should have to know
  /// there was another one. Two consumers read this: the checker, which warns,
  /// and `tutuca migrate`, which rewrites.
  retired : Array[Retirement]
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
  { start: from.start, end_: prev.end_, }
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
///
/// `delete` and `remove` are one method under two names, and so are `deleteAt`
/// and `removeAt`. The generated mutators already spell both
/// (`deleteInXAt` / `removeInXAt`), and a language that took only one of each
/// would make the choice of spelling a thing to look up.
pub fn collection_method(name : String) -> Int? {
  match name {
    "clear" => Some(0)
    "push" | "deleteAt" | "removeAt" | "add" | "remove" | "delete" | "toggle" =>
      Some(1)
    "insertAt" | "setAt" | "set" => Some(2)
    _ => None
  }
}

///|
/// Every effect name, in the order the diagnostics list them.
///
/// The ONE enumeration of the vocabulary. `effect_min_arity` answers for each
/// of these and for nothing else, and the two backends read this rather than
/// restating it — an effect only one of them knows about is a language with
/// two semantics.
/// The reserved root a host binding is read under.
///
/// One place, because three things ask: the parser, the checker refusing a
/// parameter that would shadow it, and the printer.
pub let config_root : String = "host"

///|
pub fn effect_names() -> Array[String] {
  ["send", "sendAt", "ask", "notify", "forward", "reply", "fail", "drop"]
}

///|
/// The current spelling of an effect name.
///
/// A retired spelling still parses for one release, and this is where it stops
/// being one: the parser normalises before it builds the statement, so every
/// backend below sees ONE vocabulary and no `match` on an effect has to carry
/// two arms for a word. `@tutuca.retired(KeywordName, …)` is what says so to
/// the author, once, in the checker.
pub fn current_effect(name : String, kind : DeclKind) -> String {
  match name {
    "stop" => "drop"
    "sendReply" => "reply"
    "intent" => "ask"
    // `forward` used to mean two things by position, which is the collision
    // this family removes. In a `receive` body it STARTED a walk from the
    // message that arrived — that is asking, with the question already in
    // hand, so it is a bare `ask`. In an `answer` body it hands the walk that
    // is already running to the next hop, and there it keeps its name.
    "forward" => if kind is DReceive { "ask" } else { "forward" }
    _ => name
  }
}

///|
/// The effects, and the fewest arguments each takes.
pub fn effect_min_arity(name : String) -> Int? {
  // The retired spellings answer here too, so a block written in them still
  // parses. They are normalised away by `current_effect` before the statement
  // is built.
  match name {
    "drop" | "stop" => Some(0)
    // Bare in a `receive` body — the question is the message that arrived —
    // and named everywhere else. The checker is what says which body a bare
    // one is legal in; the arity table cannot, and should not try.
    "ask" => Some(0)
    // Never bare: a notification names what happened. There is no "notify the
    // thing that arrived", because a message already reached who it named.
    "notify" => Some(1)
    // A name plus whatever the message carries.
    "send" => Some(1)
    "sendReply" => Some(1)
    // A place, then a name, then the payload.
    "sendAt" => Some(2)
    // `intent` takes a name after its leg words; `forward` takes none, because
    // it re-dispatches the one that arrived.
    "intent" => Some(1)
    "forward" => Some(0)
    // `fail` takes the one value it answers with. So does `reply` in an
    // `intent` body — and in a `receive` body its first argument is the NAME,
    // because a message's sender declared no arms for the runtime to derive
    // one from. One word, one meaning ("answer whoever asked"), and the bucket
    // decides where the name comes from.
    "reply" | "fail" => Some(1)
    _ => None
  }
}

///|
/// Whether an `ask` is naming a QUESTION or amending the one already in hand.
///
/// The one ambiguity merging `forward` into `ask` creates, and it is settled
/// by a rule that was already there: a message name has to be a literal or a
/// declared protocol operation, because a name that is not one cannot be
/// checked against anything nor routed by the generator. So `ask 'save' .text`
/// names a question and `ask .text` amends the one that arrived, and there is
/// no third reading for either.
///
/// See `takes_route` below for the other half of the parse.

///|
/// Whether an effect may be written with leg words before its arguments.
///
/// Two of them, and the same two the design gives a route: `intent` chooses one
/// for a new dispatch, and `forward` chooses one for a message that has not had
/// one yet — or narrows the one a walk is already on.
pub fn ask_names_a_question(args : Array[@tutuca.Expr]) -> Bool {
  match args.get(0) {
    Some(ELit(lit=LStr(_), ..)) | Some(EName(..)) => true
    _ => false
  }
}

///|
pub fn takes_route(name : String) -> Bool {
  name is ("ask" | "notify" | "forward" | "intent")
}

///|
/// A leg word, or nothing.
///
/// `dyn` and `lex` are CONTEXTUAL keywords: the lexer hands them over as plain
/// identifiers, so `pred dyn { … }` and a parameter named `lex` keep working,
/// and only the two positions above ever ask this question.
pub fn leg_of_word(w : String) -> @tutuca.Leg? {
  match w {
    "dyn" => Some(Dyn)
    "lex" => Some(Lex)
    _ => None
  }
}

///|
/// The source spelling of a kind — for a message, and for the printer.
pub fn kind_word(k : DeclKind) -> String {
  match k {
    DReceive => "receive"
    DAnswer => "answer"
    DCompute => "compute"
    DGet => "get"
    DSet => "set"
    DPred => "pred"
    DInvariant => "invariant"
    DEnrich => "enrich"
    DBindWith => "bindWith"
  }
}

///|
/// Every declaration kind, in the order the diagnostics list them.
///
/// The ONE place the vocabulary is enumerated. Two sentences below and the
/// card compiler's role scan all read it, so a kind added to `DeclKind` and to
/// `kind_word` is a kind those three already know about.
pub fn all_decl_kinds() -> Array[DeclKind] {
  [
    DReceive,
    DAnswer,
    DCompute,
    DGet,
    DSet,
    DPred,
    DInvariant,
    DEnrich,
    DBindWith,
  ]
}

///|
/// The kinds as an English list — `a, b, c or z`.
fn decl_kind_list() -> String {
  let words = all_decl_kinds().map(kind_word)
  match words {
    [] => ""
    [one] => one
    [.. init, last] => init.join(", ") + " or " + last
  }
}

///|
/// The kind a word names, or nothing.
pub fn kind_of_word(w : String) -> DeclKind? {
  match w {
    "receive" => Some(DReceive)
    "answer" => Some(DAnswer)
    "intent" => Some(DAnswer)
    "compute" => Some(DCompute)
    "get" => Some(DGet)
    "set" => Some(DSet)
    "pred" => Some(DPred)
    "invariant" => Some(DInvariant)
    "enrich" => Some(DEnrich)
    "bindWith" => Some(DBindWith)
    // The retired spelling, still parsing for one release. It is recorded on
    // the parser's side channel where it is READ, so that this table stays a
    // table: what to write instead lives in `@tutuca.retired`.
    "enrichScope" => Some(DBindWith)
    _ => None
  }
}

///|
/// True when a declaration's body holds statements rather than one expression.
fn kind_takes_stmts(k : DeclKind) -> Bool {
  match k {
    DCompute | DGet | DPred | DInvariant => false
    _ => true
  }
}

///|
pub fn is_transition(k : DeclKind) -> Bool {
  k is (DReceive | DAnswer)
}

///|
/// The kinds a `requires` or an `ensures` may name: a `pred`, and an
/// `invariant`, which IS a pred with a role. A `compute` is not one — nothing
/// declares that its answer is a yes or a no, and a contract whose rule might
/// be the string "ok" is a contract that holds by accident.
pub fn is_predicate(k : DeclKind) -> Bool {
  k is (DPred | DInvariant)
}

///|
fn family_of(op : String) -> @tutuca.OpFamily {
  match op {
    "and" | "or" => FLogic
    "implies" => FImplies
    "is" | "is not" | "<" | "<=" | ">" | ">=" => FCompare
    "+" | "-" => FAdd
    _ => FMul
  }
}

///|
fn family_name(f : @tutuca.OpFamily) -> String {
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
fn is_binary_only(f : @tutuca.OpFamily) -> Bool {
  f is (FCompare | FImplies)
}

// ---------------------------------------------------------------------------
// Declarations

///|
/// One expression, whole — the grammar above with no declaration around it.
///
/// This is what lets a CONDITIONAL SLOT be the same language as a block body
/// rather than a second one that looks like it. `parse_expr` carries no
/// context: it reaches `parse_operand` / `parse_value` / `parse_place` and
/// never the declaration or statement vocabulary, so there is nothing for a
/// slot to supply and nothing for the two callers to disagree about.
///
/// The shape is `parse_tpl_parts`'s, which has always parsed an interpolation
/// this way — a fresh cursor over a bare substring, and a demand that the
/// whole of it was consumed.
pub fn parse_expr_source(source : String) -> @tutuca.Expr raise ScriptError {
  let p : P = {
    toks: tokenize_script(source),
    at: 0,
    retired: [],
    decl_kind: DReceive,
  }
  let e = parse_expr(p)
  if !(p.peek() is TEof) {
    raise Unexpected(
      got=tok_name(p.peek()),
      want="the end of the expression",
      span=p.span(),
    )
  }
  e
}

///|
pub fn parse_script(source : String) -> Array[Decl] raise ScriptError {
  parse_script_retiring(source).0
}

///|
/// Parse a block, and say which retired spellings it was written with.
///
/// The parse is the ONE thing that knows where a keyword can appear: `stop` is
/// a retired effect at the head of a statement and an ordinary field name
/// everywhere else, and only something that has parsed as far as the statement
/// can tell the two apart. So both consumers of a retirement — the checker's
/// warning and `tutuca migrate`'s edit — come from here rather than from a
/// scan over the text.
pub fn parse_script_retiring(
  source : String,
) -> (Array[Decl], Array[Retirement]) raise ScriptError {
  let p : P = {
    toks: tokenize_script(source),
    at: 0,
    retired: [],
    decl_kind: DReceive,
  }
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
  (out, p.retired)
}

///|
/// The retired spellings a block is written with, for a block that need not
/// parse.
///
/// `migrate` calls this: a file mid-rename is a file somebody is about to fix,
/// and refusing to rewrite the part that lexed because a later declaration has
/// a typo in it would make the tool useless exactly when it is wanted. What
/// was found before the failure is still true about the text before it.
pub fn retired_spellings(source : String) -> Array[Retirement] {
  let toks = tokenize_script(source) catch { _ => return [] }
  let p : P = { toks, at: 0, retired: [], decl_kind: DReceive, }
  for ;; {
    p.skip_seps()
    if p.peek() is TEof {
      break
    }
    let _ = parse_decl(p) catch { _ => break }
  }
  p.retired
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
    _ => p.fail("a declaration: " + decl_kind_list())
  }
  guard kind_of_word(word) is Some(kind) else {
    raise UnknownKind(got=word, span=word_span)
  }
  // Every effect below is parsed knowing which body it is in, because one of
  // them means two things by position and this is where the position is.
  p.decl_kind = kind
  // A declaration kind can be retired too, and it is recorded the same way an
  // effect is: the AST below carries only `kind`, so nothing under the parser
  // knows there was another spelling.
  if kind_word(kind) != word {
    p.retired.push({
      word,
      replacement: kind_word(kind),
      advice: @tutuca.retired(KeywordName, word).unwrap_or(
        "write `\{kind_word(kind)}`",
      ),
      span: word_span,
    })
  }
  let (name, name_span) = p.ident("the name this declaration answers")
  let params : Array[Param] = []
  if kind is DSet {
    // Fixed by the property type: every setter body sees exactly `value` and
    // an author never restates or renames it.
    params.push({ name: "value", span: name_span, })
  } else if p.peek() is TLParen {
    p.bump() |> ignore
    if !(p.peek() is TRParen) {
      for ;; {
        let (pn, ps) = p.ident("a parameter name")
        params.push({ name: pn, span: ps, })
        if p.peek() is TComma {
          p.bump() |> ignore
          continue
        }
        break
      }
    }
    p.expect(TRParen, "`)` closing the parameter list")
  }
  let (requires_, ensures_, format) = parse_clauses(p, kind)
  // A separator between the clauses and the body. A newline ends a STATEMENT,
  // and a declaration's head is not one: `pred needsTitle` / `format $'…'` /
  // `{ … }` on three lines is the spelling a rule with a sentence wants, and
  // the one-line form is the same declaration.
  p.skip_seps()
  let body = parse_body(p, stmts=kind_takes_stmts(kind))
  {
    kind,
    name,
    params,
    requires_,
    ensures_,
    format,
    body,
    doc,
    span: p.since(from),
    name_span,
  }
}

///|
/// The clauses between a declaration's name and its body.
///
/// Unambiguous with no lookahead into anything: what follows a declaration's
/// name is `(`, `{`, or a clause word, and a bare name could never have been
/// any of the other two.
///
/// Either order is accepted and the printer writes one — `requires` then
/// `ensures`, the order they happen in — because a canonical form is what makes
/// the round-trip test mean something. At most one of each: two `requires` on
/// one handler is two rules with no name for their conjunction, and `pred
/// canMove { canPush and notBusy }` is the spelling that gives it one.
///
/// `format` sits here rather than inside the braces for the same reason the
/// contracts do: it is a fact about the declaration, and the braces hold the
/// only thing that is a fact about VALUES. It never meets `requires` or
/// `ensures` in one head — a contract is a transition's and a format is a
/// rule's — but they are parsed by one loop so that writing one on the wrong
/// kind is answered by the clause itself rather than by a puzzled `{`.
fn parse_clauses(
  p : P,
  kind : DeclKind,
) -> (Attach?, Attach?, @tutuca.Expr?) raise ScriptError {
  let mut requires_ : Attach? = None
  let mut ensures_ : Attach? = None
  let mut format : @tutuca.Expr? = None
  for ;; {
    // A clause may sit on its own line, which is what the multi-line spelling
    // of a rule with a sentence needs. Skipping here is safe because the only
    // thing that may follow the head is the body, and `parse_decl` skips again
    // before it.
    p.skip_seps()
    guard p.peek() is TIdent(word) &&
      (word == "requires" || word == "ensures" || word == "format") else {
      break
    }
    let at = p.span()
    p.bump() |> ignore
    if word == "format" {
      // A sentence about a false answer needs the answer to be a yes or a no.
      guard is_predicate(kind) else {
        raise Unexpected(
          got="`format` on `\{kind_word(kind)}`",
          want="a `format` on a rule — `pred` or `invariant`, the two kinds whose answer is declared to be a yes or a no",
          span=at,
        )
      }
      guard format is None else {
        raise Unexpected(
          got="a second `format`",
          want="one `format` — a rule says one thing about the failure it describes",
          span=at,
        )
      }
      format = Some(parse_expr(p))
      continue
    }
    // A contract states when a TRANSITION may happen and where it may land.
    // The other kinds have no transition to state it about: an `enrich` writes
    // bindings, and a value body is not a moment.
    guard is_transition(kind) else {
      raise Unexpected(
        got="`\{word}` on `\{kind_word(kind)}`",
        want="a contract on a transition — `on`, `receive`, `bubble` or `response`",
        span=at,
      )
    }
    let (n, ns) = p.ident("the `pred` `\{word}` names")
    let clause : Attach = { name: n, span: ns, }
    if word == "requires" {
      guard requires_ is None else {
        raise Unexpected(
          got="a second `requires`",
          want="one `requires` — two rules become one by naming their `and` in a `pred`",
          span=at,
        )
      }
      requires_ = Some(clause)
    } else {
      guard ensures_ is None else {
        raise Unexpected(
          got="a second `ensures`",
          want="one `ensures` — two rules become one by naming their `and` in a `pred`",
          span=at,
        )
      }
      ensures_ = Some(clause)
    }
  }
  (requires_, ensures_, format)
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
  // `new Label` — the zero of a declared type, into `@cur`.
  //
  // A leading keyword is unambiguous here: a statement starts with `if`, an
  // effect name, `.` or `@`, and never with a bare name of its own. The type
  // is parsed as a NAME, since resolving it needs a schema this package does
  // not see.
  if p.peek() is TIdent("new") {
    p.bump() |> ignore
    let ty = parse_ty_ref(p)
    return SNew(ty~, span=p.since(from))
  }
  // An effect: a bare name the effect table knows.
  if p.peek() is TIdent(name) && effect_min_arity(name) is Some(min) {
    let word_span = p.span()
    p.bump() |> ignore
    // Normalised here and nowhere else: below this point the statement carries
    // the current spelling, so no backend has two arms for one operation.
    let cur = current_effect(name, p.decl_kind)
    if cur != name {
      p.retired.push({
        word: name,
        replacement: cur,
        advice: @tutuca.retired(KeywordName, name).unwrap_or("write `\{cur}`"),
        span: word_span,
      })
    }
    let args : Array[@tutuca.Expr] = []
    // The one new parse rule: read leg words while the next token is one, then
    // parse normally. It adds no ambiguity to juxtaposition, because an
    // `intent`'s name is always a string literal and `forward`'s arguments are
    // values — neither can be the bare word `dyn` or `lex`.
    let route : Array[@tutuca.Leg] = []
    if takes_route(name) {
      while p.peek() is TIdent(w) && leg_of_word(w) is Some(leg) {
        p.bump() |> ignore
        route.push(leg)
      }
    }
    // `sendAt`'s first argument is a PLACE, and it is the only position in the
    // language where `&` is legal.
    if name == "sendAt" && p.peek() is TAmp {
      let amp = p.span()
      p.bump() |> ignore
      let place = parse_place(p, for_ref=true)
      args.push(ERef(place~, span={ start: amp.start, end_: place.span.end_, }))
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
    return SEffect(name=cur, args~, route~, span=p.since(from))
  }
  // Otherwise it is a place: an assignment, or a collection method on it.
  if !(p.peek() is (TDot | TAt)) &&
    !(p.peek() is TIdent(w) && w == @tutuca.target_bind) &&
    !(p.peek() is TIdent("state") && p.peek_at(1) is TDot) {
    // `f.name = 'x'` parses as far as the path and then stops here. Saying
    // what a path into an argument IS beats listing what a statement may be:
    // an argument is a value the caller handed over, and this component owns
    // no position inside it.
    if p.peek() is TIdent(n) && p.peek_at(1) is (TDot | TLBracket) {
      raise Unexpected(
        got="a path into `\{n}`",
        want="a place this component owns — an argument is a value the caller handed over, so assign to a `.field` instead",
        span=p.span(),
      )
    }
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
          want="a collection method: push, insertAt, setAt, deleteAt/removeAt, clear, add, remove/delete, set or toggle",
          span=place.span,
        )
      }
      let receiver : @tutuca.Place = {
        root: place.root,
        steps: place.steps[0:place.steps.length() - 1].to_owned(),
        span: place.span,
      }
      let args : Array[@tutuca.Expr] = []
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
// Type references

///|
/// `Label`, `Array[String]`, `Map[String, Int]` — the `tutuca/spec` spelling
/// of a type, parsed as a name applied to names.
///
/// Every spelling the state block has is a name with arguments or without one,
/// so this needs no table and cannot disagree with the one `statedef` keeps:
/// whether `Frobnicator` is a type at all is answered where the schema is, and
/// answered as a finding rather than as a parse error.
fn parse_ty_ref(p : P) -> TyRef raise ScriptError {
  let from = p.span()
  let (name, name_span) = p.ident("a type name after `new`")
  let args : Array[TyRef] = []
  // Attached, like every other bracket in the language: `Array [String]` is a
  // name and then something else, and saying so here beats a stray `[` landing
  // in the next statement.
  if p.peek() is TLBracket && !p.gap() {
    p.bump() |> ignore
    for ;; {
      args.push(parse_ty_ref(p))
      if p.peek() is TComma {
        p.bump() |> ignore
        continue
      }
      break
    }
    p.expect(TRBracket, "`]` closing the type arguments")
  }
  { name, args, span: if args.is_empty() { name_span } else { p.since(from) }, }
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
fn parse_place(p : P, for_ref~ : Bool) -> @tutuca.Place raise ScriptError {
  let from = p.span()
  let root : @tutuca.PlaceRoot = match p.peek() {
    TIdent("state") => {
      p.bump() |> ignore
      p.expect(TDot, "`.` after the raw state root")
      let (n, _) = p.ident("a state field after `state.`")
      PState(n)
    }
    TDot => {
      p.bump() |> ignore
      let (n, _) = p.ident("a state field after `.`")
      PState(n)
    }
    // `cur` — what a `new` in this body is building. A reserved root, and a
    // bare one: it is not a binding, which is the whole of what `@cur` got
    // wrong. A binding is something an `enrich` produces and a view reads.
    TIdent(w) if w == @tutuca.target_bind => {
      p.bump() |> ignore
      PTarget
    }
    TAt => {
      let at = p.span()
      p.bump() |> ignore
      let (n, span) = p.ident("a binding name after `@`")
      if n == @tutuca.target_bind {
        p.retired.push({
          word: "@" + n,
          replacement: n,
          advice: @tutuca.retired(KeywordName, "@" + n).unwrap_or(
            "write `\{n}`",
          ),
          span: { start: at.start, end_: span.end_, },
        })
        PTarget
      } else {
        PBind(n)
      }
    }
    _ => p.fail("a place: `.field`, `@binding` or `\{@tutuca.target_bind}`")
  }
  let steps = parse_steps(p, for_ref~)
  { root, steps, span: p.since(from), }
}

///|
/// The steps below a root, for whichever root was just read.
///
/// Shared by `.field` / `@bind` and by a parameter path, because a step means
/// the same thing under all three — and because the ATTACHMENT rule that ends
/// the loop has to be one rule rather than two that could drift.
fn parse_steps(
  p : P,
  for_ref~ : Bool,
) -> Array[@tutuca.PathStep] raise ScriptError {
  let steps : Array[@tutuca.PathStep] = []
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
  steps
}

///|
/// Whether an attached step follows — the test that turns a bare name into a
/// parameter path. Attached, because `f.name` and `f .name` are told apart by
/// nothing else.
fn starts_attached_step(p : P) -> Bool {
  if p.gap() {
    return false
  }
  match p.peek() {
    TDot => p.peek_at(1) is TIdent(_)
    TLBracket => true
    _ => false
  }
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
/// `^` IS included. It substitutes the caller's source, which is required to
/// be exactly one token, so an operand position is where it fits and grouping
/// cannot change under it. Whether a BODY may write one is a different
/// question with a different answer, and `tscript/check` is where it is asked
/// — a block has no macro frame to substitute from.
fn starts_argument(t : STok) -> Bool {
  match t {
    TNum(_) | TStr(_) | TTpl(_) | TDot | TAt | TDollar | TCaret => true
    TLParen => true
    TIdent(_) => true
    _ => false
  }
}

///|
fn parse_expr(p : P) -> @tutuca.Expr raise ScriptError {
  let from = p.span()
  let first = parse_operand(p)
  guard p.peek() is TOp(op0) && op0 != "not" else { return first }
  // The family is read from the PEEKED operator: `chain_op` consumes, and
  // consuming here would eat the first operator before the loop below could.
  let family = family_of(op0)
  let operands : Array[@tutuca.Expr] = [first]
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
fn parse_operand(p : P) -> @tutuca.Expr raise ScriptError {
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
fn parse_atom(p : P) -> @tutuca.Expr raise ScriptError {
  parse_value(p, apply=false)
}

///|
fn parse_value(p : P, apply~ : Bool) -> @tutuca.Expr raise ScriptError {
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
      ELit(lit=LNum(v), from_macro=false, span=p.since(from))
    }
    TStr(sv) => {
      p.bump() |> ignore
      ELit(lit=LStr(sv), from_macro=false, span=p.since(from))
    }
    TTpl(raw) => {
      p.bump() |> ignore
      ETpl(parts=parse_tpl_parts(raw, from), span=p.since(from))
    }
    TDot | TAt => {
      let place = parse_place(p, for_ref=false)
      ERead(place~, span=place.span)
    }
    // `cur` — the target, read as a whole or walked into. A reserved word, so
    // it is taken here before the application loop below could read it as a
    // name being applied to what follows.
    TIdent(w) if w == @tutuca.target_bind => {
      let place = parse_place(p, for_ref=false)
      ERead(place~, span=place.span)
    }
    // `$name` is a `compute` this component answers. `$$name` was a value the
    // host bound, and is retired: two sigils that differ by one character for
    // two questions of two different things is a distinction a reader has to
    // count to see. It is `host.name` now, read above.
    TDollar =>
      if p.peek_at(1) is TDollar {
        let word_span = p.span()
        p.bump() |> ignore
        p.bump() |> ignore
        let (n, _) = p.ident("a config variable name after `$$`")
        p.retired.push({
          word: "$$",
          replacement: config_root + ".",
          advice: @tutuca.retired(KeywordName, "$$").unwrap_or(
            "write `\{config_root}.\{n}`",
          ),
          span: word_span,
        })
        EConfigVar(name=n, span=p.since(from))
      } else {
        p.bump() |> ignore
        let (n, _) = p.ident("a method name after `$`")
        EMethod(name=n, span=p.since(from))
      }
    TCaret => {
      p.bump() |> ignore
      let (n, _) = p.ident("a macro variable name after `^`")
      EMacroVar(name=n, span=p.since(from))
    }
    TOp("*") => {
      p.bump() |> ignore
      let (n, _) = p.ident("a dynamic binding name after `*`")
      EDyn(name=n, span=p.since(from))
    }
    TAmp => raise MisplacedRef(span=from)
    TIdent("true") => {
      p.bump() |> ignore
      ELit(lit=LBool(true), from_macro=false, span=p.since(from))
    }
    TIdent("false") => {
      p.bump() |> ignore
      ELit(lit=LBool(false), from_macro=false, span=p.since(from))
    }
    TIdent("null") => {
      p.bump() |> ignore
      ELit(lit=LNull, from_macro=false, span=p.since(from))
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
      // `host.name` — a value the HOST bound, before any of this was parsed.
      // A reserved root like `state`, and read here for the same reason: the
      // step that follows is a name in somebody else's namespace, not a field
      // of anything this component owns.
      if n == config_root && starts_attached_step(p) {
        let steps = parse_steps(p, for_ref=false)
        guard steps is [PField(cfg)] else {
          p.fail(
            "one config variable name after `\{config_root}.` — a host binding is a flat name, so there is nothing under it to reach",
          )
        }
        return EConfigVar(name=cfg, span=p.since(from))
      }
      if n == "state" && starts_attached_step(p) {
        let steps = parse_steps(p, for_ref=false)
        guard steps is [PField(field), .. rest] else {
          p.fail("a state field after `state.`")
        }
        let place : @tutuca.Place = {
          root: PState(field),
          steps: rest.to_owned(),
          span: p.since(from),
        }
        return ERead(place~, span=place.span)
      }
      // `f.name`, `f[0]` — a path into a parameter. Attached only, and read
      // before the application loop, so `len f.items` is `len` applied to one
      // path rather than to two things.
      if starts_attached_step(p) {
        let steps = parse_steps(p, for_ref=false)
        let place : @tutuca.Place = {
          root: PParam(n),
          steps,
          span: p.since(from),
        }
        return ERead(place~, span=place.span)
      }
      let args : Array[@tutuca.Expr] = []
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
fn parse_value_block(p : P) -> @tutuca.Expr raise ScriptError {
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
fn parse_tpl_parts(
  raw : String,
  at : Span,
) -> Array[@tutuca.TplPart] raise ScriptError {
  let chars : Array[Char] = raw.iter().collect()
  let out : Array[@tutuca.TplPart] = []
  let text = StringBuilder()
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
          out.push(TText(text=s, from_macro=false))
        }
        text.reset()
        let inner = StringBuilder()
        for k in (i + 1)..<j {
          inner.write_char(chars[k])
        }
        // The interior is its own little expression. Its spans index the
        // interior, so they are rebased onto the template token — a column
        // inside an interpolation is not worth a second offset discipline.
        let ip : P = {
          toks: tokenize_script(inner.to_string()),
          decl_kind: DReceive,
          at: 0,
          retired: [],
        }
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
    out.push(TText(text=s, from_macro=false))
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
      "`\{got}` is not a declaration kind — expected " + decl_kind_list()
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
