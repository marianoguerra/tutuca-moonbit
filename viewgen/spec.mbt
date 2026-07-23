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
/// A macro declared in the view file as `<template id="macro:name">`. Its
/// `data-*` attributes are the defaults for the `^var` references in the body
/// (values are tutuca source, so a literal string default is `'24'`).
///
/// Declaring macros in the view file rather than registering them from
/// MoonBit is what lets the generator EXPAND them: a macro whose body is a
/// runtime value could never be compiled ahead of time.
pub(all) struct MacroDef {
  name : String
  defaults : Map[String, String]
  source : String
} derive(Eq, @debug.Debug)

///|
/// One component's views, `main` first.
///
/// `name` is empty for a file that declares a single unnamed component (no
/// `Comp:` prefix on any template) — the CLI's `--name` supplies it then.
pub(all) struct ViewSet {
  name : String
  views : Array[RawView]
  common_style : String
  global_style : String
} derive(Eq, @debug.Debug)

///|
/// A whole view file: the components it declares plus the macros they share.
///
/// One file per MoonBit module rather than per component, because components
/// cluster — the example library has files defining eight and thirteen of
/// them, and a file each would bury the module in fragments.
pub(all) struct ViewFile {
  components : Array[ViewSet]
  macros : Array[MacroDef]
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
  /// Two `<template id="macro:...">` elements claim the same macro name.
  DuplicateMacro(String)
  /// `id="macro:"` with nothing after the colon.
  BadMacroName(String)
  /// The file mixes `Comp:view` ids with bare ones, so a bare id could mean
  /// either a view of the unnamed component or a component of its own.
  MixedViewIds
  /// A component in the file declares no `main` view.
  NoMainViewFor(String)
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
/// Split an input file into the components it declares.
///
/// Template `id` conventions:
///
///   (none)          the single unnamed component's `main` view
///   `row`           …its `row` view
///   `Counter:main`  the `Counter` component's `main` view
///   `Counter`       shorthand for `Counter:main`
///   `macro:icon`    a macro shared by every component in the file
///
/// A file either names its components or does not; mixing the two forms is
/// an error, because `row` would then be ambiguous between a view of the
/// unnamed component and a component called `row`.
///
/// `<style>` elements are lifted out of the emitted source: inside a template
/// it becomes that view's style; at file level it is the first component's
/// common style, or its global style with `data-global`.
declare pub fn split_file(source : String) -> ViewFile raise GenError

///|
/// Compile the views and extract the typed surface. Every view is parsed into
/// a FRESH @anode.ParseContext with a collecting handler — the same shadow
/// discipline cli/lint_component.mbt uses, so no live component is touched.
declare pub fn view_surface(
  views : Array[RawView],
  macros? : Array[MacroDef],
) -> Surface raise GenError

///|
/// Emit the generated MoonBit module.
declare pub fn emit_module(
  name : String,
  source_file : String,
  file : ViewFile,
  debug_derive? : Bool,
) -> String raise GenError

///|
/// True when every view can be emitted as a compiled tree. A view whose tree
/// still holds a macro call cannot: macros are registered from MoonBit at
/// runtime, so the generator cannot expand them.
declare pub fn ir_supported(file : ViewFile) -> Bool

///|
/// Emit the companion IR module: the @anode.ANode tree and event table each
/// view parses into, plus the `<v>_views()` builder (passed as `views~`). Only
/// valid when `ir_supported` holds.
declare pub fn emit_ir_module(
  name : String,
  source_file : String,
  file : ViewFile,
) -> String raise GenError

///|
/// Build the compiled views directly, skipping codegen — the same value the
/// emitted IR module reconstructs.
declare pub fn build_views(
  views : ViewSet,
  macros? : Array[MacroDef],
) -> Map[String, @anode.View] raise GenError

///|
/// The whole pipeline: input file text -> generated MoonBit source.
declare pub fn generate(
  source : String,
  name~ : String,
  source_file~ : String,
) -> String raise GenError

///|
/// The component name for a ViewSet: its own, or the fallback the CLI passes
/// for a file that declares a single unnamed component.
declare pub fn ViewSet::component_name(
  self : ViewSet,
  fallback : String,
) -> String
