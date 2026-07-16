// Spec for the lint layer: parse-issue-driven rules (tools/core/lint-check.js
// PARSE_ISSUES table + LintParseContext) and the HTML structural linter
// (tools/core/htmllinter.js). READONLY by convention: concrete public data
// types plus `declare` stubs; implementations live in separate files.
//
// Scope: NO component-model rules (field/method/provide checks need the
// component layer). Findings are plain data; formatting is the caller's job.

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
  BadValue
  UnsupportedExprSyntax
  BindingMemberTooDeep
  XOpIgnoresChildren
  DeprecatedBareXDirective // TEMPORARY, tied to the bare-x-directive nudge
  MaybeAddAtPrefix
  MaybeDropAtPrefix
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
/// Machine-applicable fix suggestions (JS suggestion objects, one variant per
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
/// One lint finding. `info` is freeform key/value detail (JS ad-hoc info
/// objects); `location` is set by the structural linter (source positions
/// come from the HTML tokenizer).
pub(all) struct Finding {
  code : LintCode
  level : LintLevel
  info : Array[(String, String)]
  location : Location?
  suggestion : Suggestion?
} derive(Debug, Eq)

///|
/// One recorded on_attributes callback (JS LintParseContext.attrs entries).
pub(all) struct AttrsRecord {
  result : @anode.AttrParseResult
  is_macro_call : Bool
  tag : String
} derive(Debug)

///|
/// ParseHandler that records everything the parser reports, for rule checks
/// after parsing (JS LintParseContext).
pub(all) struct LintCollector {
  parse_issues : Array[(@anode.ParseIssue, String?)]
  deprecations : Array[(@anode.DeprecatedSyntax, String?)]
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
/// host bare-directive attrs) to findings (JS checkParseIssues +
/// checkHostBareDirectives).
declare pub fn check_collected(collector : LintCollector) -> Array[Finding]

///|
/// Structural HTML linter (tools/core/htmllinter.js): tokenizes `html` once
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
