// Spec for tutuca script: the public data types plus `declare` stubs.
// Implementations live in lex.mbt / parse.mbt.
//
// READONLY by convention, like `core/spec.mbt`: this file and the test suites
// beside it define the contract.
//
//   source text --tokenize--> Array[Token]   (spans)
//               --parse_*---> @tutuca.Val?   (the runtime AST, span-free)
//
// The two halves of that arrow are the whole design. The AST is `core`'s and
// carries no positions, because it is embedded in `Step` (which derives Eq)
// and emitted into the checked-in IR modules, where a source position would be
// bytes nobody reads. Positions live on the TOKENS and on the diagnostics, and
// they are what the parser reports with.

///|
/// A half-open character range in the source that was parsed.
///
/// Character indices, not bytes: they index `source.to_array()`, the same
/// `Array[Char]` `viewfile` slices with and the WHATWG tokenizer counts in, so
/// a span from a slot value and a span from the file agree for any input,
/// astral characters included.
///
/// A span is relative to the string handed to the parser — one attribute's
/// value, or one script block. Rebasing it onto the file is the caller's job,
/// and `@viewfile.Block` carries the offset that does it.
pub(all) struct Span {
  start : Int
  end_ : Int
} derive(Debug, Eq)

///|
/// The empty span, for a diagnostic about a value with no source of its own —
/// a `^macro` variable's expansion, or a value built by hand.
pub let no_span : Span = { start: 0, end_: 0, }

///|
/// One lexical run, and where it came from.
///
/// The value language's tokens are famously coarse — a `$'…'` template is ONE
/// token however much it contains — and that is deliberate: the slot grammar
/// is application of a name to whitespace-separated operands, so a finer
/// tokenizer would have nothing to say. What the span adds is the ability to
/// point at the operand that was wrong instead of at the whole attribute.
pub(all) struct Token {
  text : String
  span : Span
} derive(Debug, Eq)

///|
/// Parse-issue kind — only "bad-value" occurs here; other kinds
/// (x-op, x-attr, …) join this enum when their modules are ported.
pub(all) enum IssueKind {
  BadValue
} derive(Debug, Eq)

///|
/// What was malformed (the `info.role`)
pub(all) enum IssueRole {
  BadMacroVar // "macro-var": unknown ^name
  /// "config-var": a `$$name` the host bound nothing to. Separate from
  /// `BadMacroVar` because the two name different parties: an unknown `^name`
  /// is the view's mistake, an unknown `$$name` is a view asking for something
  /// the HOST did not hand over, and the fix is in a different file.
  BadConfigVar
  BadHandlerName // "handler-name"
  BadHandlerArg // "handler-arg"
  UnknownPredicate // "predicate": no builtin (and no declaration) of that name
  /// "predicate-arity": wrong argument count. Carries the name and what the
  /// vocabulary says it takes, because with an open table the reader cannot
  /// look the arity up in an enum.
  PredicateArity(name~ : String, want~ : Int)
  BadPredicateArg // "predicate-arg"
  /// "expression": a conditional slot whose expression the grammar refused,
  /// or which parsed into something a slot cannot hold. Carries the sentence
  /// rather than a code, because the sentence comes from the BLOCK grammar —
  /// the two languages are one, so a slot reports what a body would report
  /// instead of a translation of it.
  BadExpression(why~ : String)
} derive(Debug, Eq)

///|
/// A parse issue, collected on the ParseCtx.
///
/// `span` is where in the parsed string it went wrong. Before this the whole
/// diagnostic was `{kind, role, value}` — a role and the offending text, with
/// no position anywhere in the value language, so the best a caller could do
/// was name the enclosing tag. `value` stays: it is the text to QUOTE, and a
/// span alone would make every message go and re-read the source to say what
/// it is about.
pub(all) struct Issue {
  kind : IssueKind
  role : IssueRole
  value : String // offending token / source string
  span : Span
} derive(Debug, Eq)

///|
/// Parse context (`px`): macro variables in scope plus collected issues
///
/// `config_vars` is the HOST's table, and it is separate from `macro_vars` for
/// the reason the two sigils are separate: a `^name` resolves to the CALLER's
/// string and a `$$name` resolves to the host's, and the difference decides
/// whether the result may pin a URL origin. See `parse_tok`.
pub struct ParseCtx {
  macro_vars : Map[String, String]
  config_vars : Map[String, String]
  issues : Array[Issue]
}

///|
declare pub fn ParseCtx::new(
  macro_vars? : Map[String, String],
  config_vars? : Map[String, String],
) -> ParseCtx

///|
/// Split a value source string into tokens: `$'…'` template runs and `'…'`
/// literal runs (escapes kept) stay single tokens; otherwise maximal
/// non-whitespace runs. An unterminated quote falls back to a plain run.
declare pub fn tokenize(s : String) -> Array[Token]

///|
/// Parse a single token into the richest Val it can be, with no context/kind
/// filtering. None when the token is not a well-formed value.
declare pub fn parse_token(s : String, ctx : ParseCtx) -> @tutuca.Val?

///|
/// Conditionals (@show, @hide, @if.<attr>, …): a single token is a plain
/// boolean-group value; multiple tokens are an application `empty? .items`.
declare pub fn parse_bool(s : String, ctx : ParseCtx) -> @tutuca.Val?

///|
/// Text values (:attr, @text, <x text>, @then/@else, @push-view, @html)
declare pub fn parse_text(s : String, ctx : ParseCtx) -> @tutuca.Val?

///|
/// A single component to render (<x render>)
declare pub fn parse_component(s : String, ctx : ParseCtx) -> @tutuca.Val?

///|
/// A sequence to iterate (@each, <x render-each>)
declare pub fn parse_sequence(s : String, ctx : ParseCtx) -> @tutuca.Val?

///|
/// A `provide:` field definition or `lookup` default: field, seq-access,
/// method reference, or constant.
declare pub fn parse_field(s : String, ctx : ParseCtx) -> @tutuca.Val?

///|
/// A `provide:` value — addressable kinds only (field or seq-access)
declare pub fn parse_provide(s : String, ctx : ParseCtx) -> @tutuca.Val?

///|
/// Pass-through values on a macro-call element (:attr on a macro)
declare pub fn parse_macro_attr(s : String, ctx : ParseCtx) -> @tutuca.Val?

///|
/// A synchronous virtual-property action authored directly in an event slot.
/// The target is always a property of the component that owns the view.
pub(all) enum PropertyAction {
  PropertySet(name~ : String, value~ : @tutuca.Val)
  PropertyReset(String)
  PropertyCall(name~ : String, operation~ : String, args~ : Array[@tutuca.Val])
} derive(Debug, Eq)

///|
/// Handler reference plus parsed args for @on.<event>, or a property action.
pub(all) struct HandlerParse {
  handler : @tutuca.Val
  args : Array[@tutuca.Val]
  action : PropertyAction?
} derive(Debug, Eq)

///|
/// `$name` → Method, bare name → HandlerName(Receive); args allowed, a bad arg
/// becomes Const(LNull) and reports an issue.
declare pub fn parse_input_handler(s : String, ctx : ParseCtx) -> HandlerParse?

///|
/// Handler for @when/@enrich-with/@loop-with: no args, silent on failure
declare pub fn parse_alter_handler(s : String, ctx : ParseCtx) -> @tutuca.Val?
