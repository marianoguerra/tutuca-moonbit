// Spec for the view generator: the public data types plus `declare` stubs.
// Implementations live in split.mbt / surface.mbt / names.mbt / emit.mbt.
//
// The pipeline is three pure stages:
//
//   source text --split_views--> ViewSet  (raw per-view HTML + styles)
//               --view_surface-> Surface  (handler names, arg shapes, ids, …)
//               --emit_module--> String   (the generated .mbt)
//
// Each stage is independently testable; `generate` is the composition.

///|
/// One view recovered from the input file: its raw HTML source with any
/// `<style>` elements lifted out.
pub(all) struct RawView {
  name : String
  source : String
  style : String
} derive(Eq, @debug.Debug)

///|
/// Every view in one input file, `main` first, plus the file-level styles.
pub(all) struct ViewSet {
  views : Array[RawView]
  common_style : String
  global_style : String
} derive(Eq, @debug.Debug)

///|
/// What a generated payload position decodes to. `VValue` is the escape
/// hatch: the argument is not statically known (a field read, a `$method`,
/// an unrecognized `@bind`) or the call sites disagree.
pub(all) enum ArgType {
  VDouble
  VString
  VBool
  VValue
} derive(Eq, @debug.Debug)

///|
/// One `@on.<event>` handler name as referenced across all views, with the
/// argument shape inferred from its call sites. `args` is None when the call
/// sites disagree on arity — the variant then carries the raw argument list.
pub(all) struct InputSig {
  name : String
  args : Array[ArgType]?
  /// "@on.click" call sites, in document order — used for the doc comment.
  sites : Array[String]
} derive(Eq, @debug.Debug)

///|
/// Everything the generator extracts from one file's compiled views.
pub(all) struct Surface {
  /// Bare `@on` handler names (the Input namespace), sorted.
  inputs : Array[InputSig]
  /// `$name` references anywhere in the views, sorted.
  methods : Array[String]
  /// State fields read at a view's root scope (see the caveat in emit.mbt).
  fields : Array[String]
  /// Constant `id` attributes, sorted.
  ids : Array[String]
} derive(Eq, @debug.Debug)

///|
/// Anything that makes generation impossible. Rendered by `Show` into the
/// message the CLI reports.
pub suberror GenError {
  /// Non-whitespace text outside every `<template>` in a file that has some.
  StrayText(String)
  /// Two `<template>` elements claim the same view name.
  DuplicateView(String)
  /// Every `<template>` carries an id, so no view is the main one.
  NoMainView
  /// A `<template>` is never closed.
  UnclosedTemplate(String)
  /// The view does not parse, or parses with issues (a view that would warn
  /// at runtime is a generation failure — the types would be built on sand).
  ViewParseIssue(view~ : String, issue~ : String)
  /// A view is empty, so it has no root node to compile.
  EmptyView(String)
  /// Two source names capitalize to the same MoonBit variant.
  NameCollision(variant~ : String, first~ : String, second~ : String)
  /// `--name` is not usable as a MoonBit type prefix.
  BadComponentName(String)
}

///|
/// The user-facing one-line message for a generation failure.
declare pub fn GenError::message(self : GenError) -> String

///|
/// Split an input file into its views. With no `<template>` elements the
/// whole file is the `main` view; otherwise every top-level `<template>` is a
/// view named by its `id`, and the one without an id is `main`.
///
/// `<style>` elements are lifted out of the emitted source: inside a template
/// it becomes that view's style; at file level it is the component's common
/// style, or its global style with `data-global`.
declare pub fn split_views(source : String) -> ViewSet raise GenError

///|
/// Compile the views and extract the typed surface. Every view is parsed into
/// a FRESH @anode.ParseContext with a collecting handler — the same shadow
/// discipline cli/lint_component.mbt uses, so no live component is touched.
declare pub fn view_surface(views : Array[RawView]) -> Surface raise GenError

///|
/// Emit the generated MoonBit module.
declare pub fn emit_module(
  name : String,
  source_file : String,
  views : ViewSet,
  surface : Surface,
) -> String raise GenError

///|
/// The whole pipeline: input file text -> generated MoonBit source.
declare pub fn generate(
  source : String,
  name~ : String,
  source_file~ : String,
) -> String raise GenError
