// Spec for the lint layer: parse-issue-driven rules (the PARSE_ISSUES
// table + LintParseContext) and the HTML structural linter.
// READONLY by convention: concrete public data
// types plus `declare` stubs; implementations live in separate files.
//
// Scope: this package RUNS no component-model rules (field/method/provide
// checks need the component layer). It still owns their vocabulary —
// `UndeclaredMethod` and `InertConstraint` are raised by the dyncomp host,
// which has the manifest in hand, and named/worded here so one finding does not
// print in a second format. Findings are plain data; formatting is the caller's
// job.

///|
pub(all) enum LintLevel {
  Error
  Warn
  Hint
} derive(Debug, Eq)

///|
/// Lint rule codes: the parse-issue-driven subset of the component linter
/// plus every HTML_* structural code.
pub(all) enum LintCode {
  UnknownDirective
  UnknownXOp
  UnknownXAttr
  LoopDirectiveOnXOp
  BadValue
  UnsupportedExprSyntax
  BindingMemberTooDeep
  XOpIgnoresChildren
  MaybeAddAtPrefix
  MaybeDropAtPrefix
  UndeclaredMethod
  /// The four below are the NAME-WIRING rules: what a component published,
  /// what it asked for, and whether the two can find each other. They are
  /// raised by `component`'s `ComponentStack::check_names` rather than here,
  /// for the reason this file already gives — a component-model rule needs the
  /// component layer, and lint owns the vocabulary rather than the check.
  ProvideNotAddressable
  ProvideTypeBadShape
  LookupNoProvider
  UnknownComponentName
  /// A `$name` in an `@on` position. The same refusal the generator raises as
  /// `METHOD_IN_EVENT`, said for a view that arrives at RUNTIME — a runtime
  /// macro expansion, or a guest's manifest — where no generator ran. Raised
  /// by `component`'s `ComponentStack::check_names` for the same reason the
  /// four above are.
  MethodInEventPosition
  /// An `e.<path>` handler argument traverses a step off the event-path
  /// allowlist (`e.target.form.action`). A HINT for an author's own views —
  /// the path resolves under the open profile — because the same step is
  /// REFUSED for guest-supplied views: a dyncomp host running the safe
  /// profile refuses the bundle at registration naming this step. See
  /// `@eventpath.EventPathProfile`.
  EventPathUnsafeStep
  /// A declared bound the field's type cannot carry — a `max-len` on a number,
  /// a `min`/`max` on text. Raised by the dyncomp host at load.
  InertConstraint
  HtmlTagNameHasUppercase
  HtmlSvgTagWillLowercase
  HtmlSvgAttrWillLowercase
  HtmlMathmlAttrWillLowercase
  HtmlTagNotAllowedInParent
  HtmlTextNotAllowedInParent
  HtmlVoidElementHasCloseTag
  HtmlDuplicateForm
  HtmlNestedInteractive
  HtmlMisnestedFormatting
  HtmlUnexpectedEndTag
  HtmlDuplicateAttribute
  HtmlAttributesOnEndTag
  HtmlSelfClosingEndTag
  HtmlMissingAttributeValue
  HtmlCdataInHtmlNamespace
  HtmlBogusComment
  HtmlUnclosedBeforeEnd
} derive(Debug, Eq)

///|
/// Machine-applicable fix suggestions (one variant per
/// `kind`).
pub(all) enum Suggestion {
  ReplaceName(from~ : String, to~ : String)
  AddPrefix(from~ : String, to~ : String)
  DropPrefix(from~ : String, to~ : String)
  Remove(what~ : String)
  Rephrase(from~ : String, text~ : String)
  Rewrite(from~ : String, to~ : String)
  Wrap(from~ : String, to~ : String)
} derive(Debug, Eq)

///|
/// 1-based line/column plus 0-based char offset into the linted source.
pub(all) struct Location {
  line : Int
  column : Int
  offset : Int
} derive(Debug, Eq)

///|
/// One lint finding. `info` is freeform key/value detail; `location` is set
/// by the structural linter (source positions
/// come from the HTML tokenizer).
pub(all) struct Finding {
  code : LintCode
  level : LintLevel
  info : Array[(String, String)]
  location : Location?
  suggestion : Suggestion?
} derive(Debug, Eq)

///|
/// One recorded on_attributes callback (an attrs entry).
pub(all) struct AttrsRecord {
  result : @anode.AttrParseResult
  is_macro_call : Bool
  tag : String
} derive(Debug)

///|
/// ParseHandler that records everything the parser reports, for rule checks
/// after parsing.
pub(all) struct LintCollector {
  parse_issues : Array[(@anode.ParseIssue, String?)]
  attrs : Array[AttrsRecord]
}

///|
declare pub fn LintCollector::new() -> LintCollector

///|
declare pub impl @anode.ParseHandler for LintCollector

///|
/// Damerau-Levenshtein "did you mean": closest candidate within max_distance
/// edits; case-insensitive match wins outright; exact match returns None.
declare pub fn closest_name(
  name : String,
  candidates : Array[String],
  max_distance? : Int = 2,
) -> String?

///|
/// Map everything a LintCollector captured (parse issues, deprecation nudges,
/// host bare-directive attrs) to findings.
declare pub fn check_collected(collector : LintCollector) -> Array[Finding]

///|
/// Structural HTML linter: tokenizes `html` once
/// with the WHATWG tokenizer and runs an insertion-mode prediction machine
/// over the tokens — no DOM is built. Reports HTML_* findings in source
/// order. `fragment_context` picks the initial insertion mode (§13.2.4.4;
/// tutuca lints "template"); `transparent_tag_prefixes` marks templating
/// tags (`<x>`, `<x:macro>`) as phantom: case checks apply, parent rules
/// don't.
declare pub fn lint_html(
  html : String,
  fragment_context? : String = "template",
  transparent_tag_prefixes? : Array[String] = ["x"],
) -> Array[Finding]
