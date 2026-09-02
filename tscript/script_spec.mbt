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
/// The nine declaration kinds, one per bucket a component answers.
///
/// `when` is deliberately absent. A `@when` filter and a boolean `compute` are
/// the same construct — a name, one expression, no statements — and the three
/// things that look like differences are not: what is in scope belongs to the
/// SLOT (a `@show` inside a loop already sees `@value`), the routing is picked
/// by the generator, and the `(S, key, value, iterData)` signature is a
/// MoonBit calling convention rather than something a body says. So `when`
/// joins `@show` and `@hide` as a USE of a predicate.
pub(all) enum DeclKind {
  /// An ADDRESSED name: a case of the schema's `receive` variant, or a name a
  /// view writes. One word for both, because a view's name is addressed at the
  /// component the view belongs to and that is exactly what `send` means — the
  /// message is the same message whoever raised it.
  DReceive
  /// A ROUTED name: a case of the schema's `intent` variant. It names a JOB
  /// rather than a component, and the route decides who is asked — travelling
  /// up the tree and searching the registration scope chain are two legs of
  /// one mechanism, not two kinds of name. The ANSWER is not declared here: it
  /// arrives at the sender as an ordinary addressed message.
  DIntent
  /// A `$name` in a value position. One expression.
  DCompute
  /// A complex public property getter. Its name fixes the property and its
  /// signature is always `(state) -> property-type`; no parameter list is
  /// written.
  DGet
  /// A complex public property setter. Its implicit `value` parameter has the
  /// property's declared type and its result is a synchronous state
  /// transition. Effects are forbidden.
  DSet
  /// A named boolean. One expression, and the subset of `compute` whose
  /// return type is declared — which is what lets a condition slot be
  /// type-checked and what a contract attaches to.
  DPred
  /// A `pred` the component keeps: checked after EVERY transition the block
  /// declares, and callable from a slot like any other.
  ///
  /// A kind rather than a `pred` named by some ninth clause, because "after
  /// every handler" is not a fact about a handler and has nowhere per-handler
  /// to be written. `requires` and `ensures` attach BY NAME because what they
  /// say is local; an invariant's attachment point is the component, so the
  /// component's top level is where it goes.
  DInvariant
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
/// A `pred` a transition attaches, by name.
///
/// The name and nothing else — no arguments, no expression. A clause that took
/// an expression would be an `if` with a second spelling, and the whole value
/// of a contract is that the rule has a NAME: the same name the badge in a view
/// reads, the same name a test asserts, and the same name the runtime prints
/// when the rule does not hold.
pub(all) struct Attach {
  name : String
  span : Span
} derive(Debug, Eq)

///|
/// One declaration: a kind, a name, its parameters, its contracts and its body.
pub(all) struct Decl {
  kind : DeclKind
  name : String
  params : Array[Param]
  /// `on push requires canPush { … }` — the `pred` asked BEFORE the body runs,
  /// against the state as it arrived. A precondition that does not hold is a
  /// transition that does not happen, which is the answer a declining `if`
  /// already gives; what the clause adds is that the decline has a name, so it
  /// can be reported instead of being another silent no-op.
  ///
  /// Transitions only — `on`, `receive`, `bubble`, `response`. An `enrich`
  /// writes bindings rather than state, and a `compute` is a value.
  requires_ : Attach?
  /// `on push ensures moved { … }` — the `pred` asked AFTER the body ran,
  /// against the successor. There is no way to name the state BEFORE it: a
  /// language with no `old` is one where a postcondition is a fact about where
  /// the transition landed, which is the half a reader can check by looking.
  ensures_ : Attach?
  /// `pred publishedNeedsTitle format $'Cannot publish "{.slug}"…' { … }` — the
  /// sentence to say when this rule does NOT hold, evaluated against the state
  /// that was rejected and carried out on the refusal record.
  ///
  /// Predicates only. A `format` describes the FALSE case, because a predicate
  /// is true when things are fine, and only a `pred` and an `invariant` declare
  /// that their answer is a yes or a no — a `compute` whose answer might be the
  /// string "ok" has no false case to describe.
  ///
  /// It is an ordinary expression, and almost always a `$'…'` template: the one
  /// the views already interpolate with, so there is no second interpolation
  /// syntax to learn.
  ///
  /// The `///` comment and this do different jobs, which is why a rule can want
  /// both. The comment says what the rule IS, statically, and travels into the
  /// schema and into what an agent is told before it acts; the format says what
  /// went wrong THIS time, with the values that made it go wrong.
  format : @tutuca.Expr?
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
  /// Statements: `receive` / `intent` / `set` / `enrich` / `enrichScope`.
  Stmts(Array[Stmt])
  /// One expression: `compute` / `pred` / `invariant`, and every body written
  /// in a slot.
  Value(@tutuca.Expr)
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
  SAssign(
    place~ : @tutuca.Place,
    op~ : AssignOp,
    value~ : @tutuca.Expr,
    span~ : Span
  )
  /// A mutating collection method, receiver first: `.items.push v`. These
  /// mirror the runtime-generic mutators one for one, with the `In<Field>At`
  /// infix dropped because the receiver is written.
  SMethod(
    place~ : @tutuca.Place,
    call~ : String,
    args~ : Array[@tutuca.Expr],
    span~ : Span
  )
  /// `send 'flash' .msg`, `stop`, `sendAt &.status 'flash' 'Saved'`,
  /// `intent dyn 'picked' @key`, `forward lex`.
  ///
  /// `route` is the leg words, in the order written, and it is empty for every
  /// effect except `intent` and `forward` — the two that HAVE a route. Empty
  /// means "not written", not "no legs": a bare `intent 'save'` takes the
  /// default route, and where that default is written is `@tutuca.IntentOpts::new`
  /// and not here. A parser that resolved it would be a second place for the
  /// default to live and a second place for it to drift.
  SEffect(
    name~ : String,
    args~ : Array[@tutuca.Expr],
    route~ : Array[@tutuca.Leg],
    span~ : Span
  )
  /// `if cond { … } else { … }`.
  SIf(
    cond~ : @tutuca.Expr,
    then_~ : Array[Stmt],
    else_~ : Array[Stmt],
    span~ : Span
  )
  /// `new Label`, `new Array[String]` — the zero of a declared type, and the
  /// ACTIVE TARGET the statements under it fill in.
  ///
  /// A statement rather than an expression because the language has no
  /// literals to fill one in with: a value is built by mutating it, so the
  /// thing being built has to be somewhere a statement can name. `@cur` is
  /// that somewhere, and `new` is what puts a value there.
  SNew(ty~ : TyRef, span~ : Span)
} derive(Debug, Eq)

///|
/// The name a `new` was applied to, in the `tutuca/spec` spelling:
/// `Label`, `Array[String]`, `Map[String, Int]`.
///
/// The NAME, not the type. Resolving it needs the `StateDef`, which this
/// package does not see and should not — it ships to a browser twice over and
/// carries nothing a parse does not need. `check`, `emit_mbt` and the card
/// runtime each have one in hand and resolve it there.
pub(all) struct TyRef {
  name : String
  /// `Array[String]`'s `String`. Empty for a name applied to nothing.
  args : Array[TyRef]
  span : Span
} derive(Debug, Eq)

///|
/// The binding name `new` writes and the statements under it read: `@cur`.
///
/// Reserved, and named here rather than spelled in five packages, because the
/// checker refuses to let an `enrich` bind it, the interpreter refuses to let
/// it escape into a view, and both are talking about the same name.
pub let target_bind : String = "cur"

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
/// Parse ONE expression, with no declaration around it — the entry a
/// conditional slot parses through, so that a slot and a block body are the
/// same language rather than two that resemble each other.
declare pub fn parse_expr_source(
  source : String,
) -> @tutuca.Expr raise ScriptError

///|
/// Print a declaration back as canonical source. Round-tripping through this
/// is how the grammar is pinned: parse, print, parse again, and the two ASTs
/// agree.
declare pub fn Decl::to_source(self : Decl) -> String

///|
/// Whether a declaration is a TRANSITION — the four kinds that answer a
/// dispatch by producing a successor state, and therefore the four a contract
/// can attach to.
///
/// Here rather than matched separately in the checker, the interpreter and the
/// MoonBit backend, because all three are answering the same question and a
/// fifth kind would otherwise have to be remembered in three places.
declare pub fn is_transition(k : DeclKind) -> Bool

///|
/// Whether a declaration is a PREDICATE — the kinds a `requires` or an
/// `ensures` may name, and the kinds whose answer is declared to be a yes or a
/// no.
declare pub fn is_predicate(k : DeclKind) -> Bool

///|
/// Print a type reference back as canonical source: `Map[String, Int]`.
///
/// The spelling matches `@statedef.StateTy::show_source`, so a finding about a
/// `new` and a finding about a field can name the same type the same way.
declare pub fn TyRef::to_source(self : TyRef) -> String

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
/// as in `receive init { intent lex 'loadData'; .isLoading = true }`. There is
/// no `walk_path` and no way to name an intent's answer arms here: those and
/// walking the dispatch path are the parts a small language would model badly,
/// and they stay in MoonBit.
declare pub fn effect_min_arity(name : String) -> Int?
