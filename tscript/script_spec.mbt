// Spec for the BLOCK language: what `<script type="tutuca/script">` holds.
//
// READONLY by convention. Implementations live in script_lex.mbt /
// script_parse.mbt / script_print.mbt.
//
//   block text --tokenize_script--> Array[STok]   (fine, punctuation-aware)
//              --parse_script-----> Array[Decl]   (spans on every node)
//
// Two ideas carry the whole grammar: **application is juxtaposition**, and
// **parentheses are required wherever precedence would otherwise be
// implicit**. There is no precedence table to remember and none to get wrong.
//
// The atoms are the view's atoms. `.field`, `@bind`, `$method`, `*dyn`,
// `'text'`, `$'…'`, numbers and booleans are spelled here exactly as a
// template spells them, and that is the property worth protecting: what is
// genuinely new is operators, statements and nesting, so an author who can
// read a tutuca view can read a handler without learning a second vocabulary.
// If this block ever grows its own way to NAME a value, the design has failed.

///|
/// The eight declaration kinds, one per bucket a component answers.
///
/// `when` is deliberately absent. A `@when` filter and a boolean `compute` are
/// the same construct — a name, one expression, no statements — and the three
/// things that look like differences are not: what is in scope belongs to the
/// SLOT (a `@show` inside a loop already sees `@value`), the routing is picked
/// by the generator, and the `(S, key, value, iterData)` signature is a
/// MoonBit calling convention rather than something a body says. So `when`
/// joins `@show` and `@hide` as a USE of a predicate.
pub(all) enum DeclKind {
  /// An `@on` name — the Input arm.
  DOn
  /// A case of the schema's `variant receive` / `bubble` / `response`.
  DReceive
  DBubble
  DResponse
  /// A `$name` in a value position. One expression.
  DCompute
  /// A named boolean. One expression, and the subset of `compute` whose
  /// return type is declared — which is what lets a condition slot be
  /// type-checked and what an invariant would later attach to.
  DPred
  /// `@enrich-with` binds. Statements assigning `@name`.
  DEnrich
  DEnrichScope
} derive(Debug, Eq)

///|
/// One declared parameter. Types are INFERRED, never annotated: an `on`
/// handler's arguments come from what the views write at the call site, and a
/// `receive` handler's from the schema's `MsgDef.payload`.
pub(all) struct Param {
  name : String
  span : Span
} derive(Debug, Eq)

///|
/// One declaration: a kind, a name, its parameters, and its body.
pub(all) struct Decl {
  kind : DeclKind
  name : String
  params : Array[Param]
  body : Body
  /// The `///` comment above it, or "".
  doc : String
  /// The whole declaration, from its kind keyword to its closing brace.
  span : Span
  /// Just the name, for a diagnostic that is about the name rather than the
  /// body — a duplicate, or one the schema does not declare.
  name_span : Span
} derive(Debug, Eq)

///|
/// What a declaration's braces hold.
pub(all) enum Body {
  /// Statements: `on` / `receive` / `bubble` / `response` / `enrich` /
  /// `enrich-scope`.
  Stmts(Array[Stmt])
  /// One expression: `compute` / `pred`, and every body written in a slot.
  Value(Expr)
} derive(Debug, Eq)

///|
pub(all) enum AssignOp {
  ASet // =
  AAdd // +=
  ASub // -=
} derive(Debug, Eq)

///|
/// A statement. Statements end at a newline or a `;`.
pub(all) enum Stmt {
  /// `.count = 0`, `.count += d`, `@name = expr`.
  SAssign(place~ : Place, op~ : AssignOp, value~ : Expr, span~ : Span)
  /// A mutating collection method, receiver first: `.items.push v`. These
  /// mirror the runtime-generic mutators one for one, with the `In<Field>At`
  /// infix dropped because the receiver is written.
  SMethod(place~ : Place, call~ : String, args~ : Array[Expr], span~ : Span)
  /// `send 'flash' .msg`, `stop`, `sendAt &.status 'flash' 'Saved'`.
  SEffect(name~ : String, args~ : Array[Expr], span~ : Span)
  /// `if cond { … } else { … }`.
  SIf(cond~ : Expr, then_~ : Array[Stmt], else_~ : Array[Stmt], span~ : Span)
} derive(Debug, Eq)

///|
/// What a place is rooted at.
pub(all) enum PlaceRoot {
  /// `.field` — a place in this component's state.
  PState(String)
  /// `@name` — a binding. Assignable in `enrich` / `enrich-scope` only;
  /// readable anywhere the slot provides it.
  PBind(String)
} derive(Debug, Eq)

///|
/// A step below the root.
pub(all) enum PathStep {
  /// `.field`
  PField(String)
  /// `[expr]`
  PIndex(Expr)
} derive(Debug, Eq)

///|
/// A PLACE: a position, not a value.
///
/// `.a.b` and `.a[k].b` are the two things a view slot cannot spell — nested
/// reads and nested WRITES. A slot's name lookup stays one level because
/// nothing checks it; a body is checked code and the generator knows every
/// type along the path.
pub(all) struct Place {
  root : PlaceRoot
  steps : Array[PathStep]
  span : Span
} derive(Debug, Eq)

///|
/// The four operator families. **Mixing families in one unparenthesized chain
/// is a parse error**, and the message names the parentheses to add — so
/// `a and b and c` and `a + b - c` chain freely, `a + b * c` is refused, and
/// there is no precedence to get wrong.
pub(all) enum OpFamily {
  /// `and` `or` — associative, chains freely.
  FLogic
  /// `is` `is not` `<` `<=` `>` `>=` — exactly TWO operands, so `a < b < c`
  /// is refused too.
  FCompare
  /// `implies` — `a implies b` is `(not a) or b`. Non-associative like
  /// comparison, so the right-associativity trap never arises. It is the shape
  /// most cross-field rules take.
  FImplies
  /// `+` `-`. `+` concatenates two strings and adds two numbers; the operands'
  /// static types decide and a mixed pair is a type error, not a coercion.
  FAdd
  /// `*` `/` `mod`
  FMul
} derive(Debug, Eq)

///|
pub(all) enum UnOp {
  UNot
  UNeg
} derive(Debug, Eq)

///|
/// One piece of a `$'…'` template: literal text, or an interpolated
/// expression.
pub(all) enum TplPart {
  TText(String)
  TExpr(Expr)
} derive(Debug, Eq)

///|
/// An expression.
pub(all) enum Expr {
  ELit(lit~ : @tutuca.Lit, span~ : Span)
  ETpl(parts~ : Array[TplPart], span~ : Span)
  /// Reading what is AT a place.
  ERead(place~ : Place, span~ : Span)
  /// `$name` — a `compute` result. Its TYPE is opaque to the checker
  /// ("unknown is not wrong", so nothing under it is judged), and written
  /// inside a BODY it is additionally REPORTED: this sigil is answered by the
  /// render stack, a body runs after one, so it reads Null. A body calls a
  /// `compute` or a `pred` bare — `EName` with no arguments.
  EMethod(name~ : String, span~ : Span)
  /// `*name` — a dynamic binding. Opaque for the same reason, and reported in
  /// a body for the same reason, with no bare spelling to fall back on.
  EDyn(name~ : String, span~ : Span)
  /// A bare name. In a declaration body it is a parameter; in a handler slot
  /// it is an event argument, resolved against the closed table in
  /// `render/dom_event.mbt`. Never a value in a value slot.
  EName(name~ : String, span~ : Span)
  /// A name applied to arguments — `len .items`, `clamp .page 0 (.n - 1)`,
  /// `unfinished @value`. Juxtaposition is unambiguous because every callable
  /// has a known fixed arity and the vocabulary is closed.
  EApp(name~ : String, args~ : Array[Expr], span~ : Span)
  /// Two or more operands joined by operators of ONE family.
  EChain(
    family~ : OpFamily,
    ops~ : Array[String],
    operands~ : Array[Expr],
    span~ : Span
  )
  EUnary(op~ : UnOp, operand~ : Expr, span~ : Span)
  /// `if c { a } else { b }` in a value position. Both arms are required:
  /// an expression has to have a value.
  EIf(cond~ : Expr, then_~ : Expr, else_~ : Expr, span~ : Span)
  /// `&.rows[k]` — a reference to a POSITION, legal in exactly one place: the
  /// first argument of `sendAt`.
  ///
  /// `&.rows[k]` denotes the position; `.rows[k]` denotes what is there. That
  /// distinction is the point — a position survives the root being rebuilt,
  /// which is what makes an async response land on the row that asked for it.
  ERef(place~ : Place, span~ : Span)
} derive(Debug, Eq)

///|
/// A syntax error, with the span to point at.
///
/// Fail-fast rather than collected: a syntax error cascades, and every
/// recovery strategy invents a parse the author did not write. The CHECKER
/// collects, because a type error does not cascade.
pub suberror ScriptError {
  /// Something the grammar cannot accept here. `want` says what would have
  /// been legal.
  Unexpected(got~ : String, want~ : String, span~ : Span)
  /// Two operator families in one unparenthesized chain. The message names
  /// the parentheses to add.
  MixedFamilies(first~ : String, second~ : String, span~ : Span)
  /// A comparison or an `implies` with more than two operands.
  NonAssociative(op~ : String, span~ : Span)
  /// A `&` outside the first argument of `sendAt`.
  MisplacedRef(span~ : Span)
  /// A place the runtime `Path` cannot express: `.a[0][1]` is field-then-key,
  /// so two keys in a row have no step.
  BadPlace(why~ : String, span~ : Span)
  /// A declaration kind that does not exist.
  UnknownKind(got~ : String, span~ : Span)
  /// Two declarations answer the same name in the same bucket.
  DuplicateDecl(name~ : String, span~ : Span)
}

///|
/// The user-facing one-line message.
declare pub fn ScriptError::message(self : ScriptError) -> String

///|
/// Where the failure is, for a caller that rebases onto a file.
declare pub fn ScriptError::span(self : ScriptError) -> Span

///|
/// Parse a whole `<script type="tutuca/script">` block.
declare pub fn parse_script(source : String) -> Array[Decl] raise ScriptError

///|
/// Print a declaration back as canonical source. Round-tripping through this
/// is how the grammar is pinned: parse, print, parse again, and the two ASTs
/// agree.
declare pub fn Decl::to_source(self : Decl) -> String

///|
/// Print an expression back as canonical source.
declare pub fn Expr::to_source(self : Expr) -> String

///|
/// The mutating collection methods, receiver-first. Mirrors the
/// runtime-generic mutators one for one with the `In<Field>At` infix dropped:
/// `.items.push v` IS `pushInItems`.
declare pub fn collection_method(name : String) -> Int?

///|
/// The effects a statement may perform, and the fewest arguments each takes.
/// None when the name is not an effect.
///
/// They cover the shape that dominates the corpus — a message plus a flag set,
/// as in `receive init { request 'loadData'; .isLoading = true }`. There is no
/// `walk_path` and no `RequestOpts`: choosing a request's options and walking
/// the dispatch path are the parts a small language would model badly, and
/// they stay in MoonBit.
declare pub fn effect_min_arity(name : String) -> Int?
