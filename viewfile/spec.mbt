// Spec for the view-file splitter: the public data types plus `declare`
// stubs. The implementation lives in split.mbt.
//
//   source text --split_file--> ViewFile   (raw per-view HTML, styles, blocks)
//
// One stage, and it is the only one in the pipeline that knows what an `.html`
// file looks like. Everything above it — the generator, the checker, the card
// runtime — takes a `ViewFile` and never sees a tokenizer.

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
/// A raw block lifted out of the file, with where it came from.
///
/// Both positions are kept because they answer different questions. `offset`
/// is a character index into the original source, so a diagnostic carrying a
/// span INSIDE the block can be rebased onto the file exactly, column
/// included. `line` is the 1-based line of that offset, which is what a
/// message says out loud.
pub(all) struct Block {
  text : String
  offset : Int
  line : Int
} derive(Eq, @debug.Debug)

///|
/// One `<script type="tutuca/script">` block and the component it answers for.
///
/// `comp` is the block's `for=` attribute, or "" for a file that declares a
/// single component. It is the SAME device `<template id="Counter:row">`
/// already uses one element over: the block language is written about one
/// component — a `.field` means this component's state and nothing else — so
/// a file holding four of them needs four blocks, exactly as it needs four
/// sets of templates.
pub(all) struct ScriptBlock {
  comp : String
  block : Block
} derive(Eq, @debug.Debug)

///|
/// A whole view file: the components it declares plus the macros they share.
///
/// One file per MoonBit module rather than per component, because components
/// cluster — the example library has files defining eight and thirteen of
/// them, and a file each would bury the module in fragments.
///
/// **Why the state block is parsed here and the script block is not.** A state
/// block is self-contained: text in, `StateDef` out, and the only thing the
/// splitter adds is mapping a schema error onto the line of the HTML file the
/// author has open, which needs the line map it already owns. A script block
/// is not self-contained — checking it needs the schema AND the argument types
/// inferred from the views' call sites, neither of which exists at split time.
/// So it is handed back as raw text with its position, and whoever holds the
/// rest of the context parses it.
pub(all) struct ViewFile {
  components : Array[ViewSet]
  macros : Array[MacroDef]
  /// The `<script type="tutuca/state">` schema, one entry per component it
  /// declares. Empty when the file has no block.
  state : Array[@statedef.StateDef]
  /// The `<script type="tutuca/init">` fixtures, each paired with the
  /// component whose schema it was checked against.
  init : Array[(String, @statedef.InitState)]
  /// The `<script type="tutuca/script">` blocks, unparsed, in file order.
  /// Empty for every file that predates the language.
  scripts : Array[ScriptBlock]
} derive(Eq, @debug.Debug)

///|
/// The script block for one component, or None when the file writes none.
///
/// A bare block answers for the file's single component, so a file with one
/// unnamed block and one component matches whatever that component is called.
declare pub fn ViewFile::script_for(self : ViewFile, comp : String) -> Block?

///|
/// Anything that makes a file unsplittable: its structure is wrong, or a
/// block it carries does not describe what it claims to.
///
/// Separate from the generator's own failures because these are facts about
/// the FILE, and every consumer of a file hits them — the card runtime that
/// never generates a line of MoonBit reports the same duplicate view.
pub suberror FileError {
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
  /// Two `<script type="tutuca/state">` blocks in one file.
  DuplicateStateBlock
  /// Two `<script type="tutuca/script">` blocks answer for the same component
  /// — the name is the `for=` attribute, or "" for an unqualified block.
  DuplicateScriptBlock(String)
  /// The state block does not describe component state. `line` is the line in
  /// the HTML file, not in the block, because that is the file the author has
  /// open.
  BadStateBlock(line~ : Int, message~ : String)
  /// The init block does not fit the schema.
  BadInitBlock(line~ : Int, message~ : String)
}

///|
/// The user-facing one-line message for a file failure.
declare pub fn FileError::message(self : FileError) -> String

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
declare pub fn split_file(
  source : String,
  name? : String,
) -> ViewFile raise FileError

///|
/// The component name for a ViewSet: its own, or the caller's fallback for a
/// file that declares a single unnamed component.
declare pub fn ViewSet::component_name(
  self : ViewSet,
  fallback : String,
) -> String
