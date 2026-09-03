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
/// **Why the spec block is parsed here and the script block is not.** A spec
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
  /// The `<script type="tutuca/spec">` declaration, one entry per component it
  /// declares. Empty when the file has no block.
  state : Array[@statedef.StateDef]
  /// Where that block came from, or None when the file has none.
  ///
  /// Parsed AND kept as raw text, which is the one block that is both. The
  /// `StateDef`s above are what every consumer reads; this is what a consumer
  /// needs when it has to point INTO the block — a rule's body is the block
  /// language, and whoever parses one has a span relative to the block and
  /// nowhere to put it without the block's own offset.
  state_block : Block?
  /// The `<script type="tutuca/init">` fixtures, each paired with the
  /// component whose schema it was checked against.
  init : Array[(String, @statedef.InitState)]
  /// The `<script type="tutuca/script">` blocks, unparsed, in file order.
  /// Empty for every file that predates the language.
  scripts : Array[ScriptBlock]
  /// The `<script type="tutuca/wax">` blocks — hand-written Wax, unparsed, in
  /// file order.
  ///
  /// The ESCAPE HATCH, and read by exactly one consumer: `tutucard/wasm`
  /// compiles a card into a Wax module and this is source it splices in. The
  /// interpreter has no Wax to run and `gen` has no module to put it in,
  /// so for both of those a file carrying one is a file with a block they
  /// ignore — which is what makes this additive rather than a fourth thing
  /// every backend has to answer for.
  wax : Array[ScriptBlock]
  /// The `<script type="tutuca/test">` scenes, parsed, in block order.
  ///
  /// Parsed here rather than handed back raw, and that puts it on the state
  /// and init side of this file's one asymmetry rather than the script side.
  /// The rule is the same one: a block is parsed here when it is
  /// SELF-CONTAINED. A scene is — JSON in, `Scene`s out — because what it
  /// names are selectors and message names, and neither is checkable against a
  /// schema this package would have to grow a checker to hold.
  ///
  /// Not per component. A scene NAMES the component it mounts, because a card
  /// declaring two of them has scenes that drive one and scenes that drive the
  /// other, and a `for=` would say the second could not exist.
  tests : Array[@scenedef.Scene]
  /// The component a host mounts when it is told no other name — the one whose
  /// `<template>` carries `data-root`. Empty when no template does, and then
  /// the root is `components[0]`, the first in the file.
  ///
  /// A NAME rather than a reordering of `components`, because that list's order
  /// is load-bearing elsewhere: a file-level `<style>` belongs to the component
  /// at index 0, so moving the root to the front would move a stylesheet as a
  /// side effect of saying which component is the interesting one.
  root : String
  /// The file spelled its spec block `tutuca/spec`, the name that block used
  /// to have.
  ///
  /// A fact about the file and not a failure, which is why it rides here rather
  /// than in `FileError`: the block parsed, the components are complete, and
  /// nothing downstream behaves differently. What it is for is letting the ONE
  /// consumer that talks to an author — `gen` — say so, without every
  /// other consumer of a `ViewFile` having to grow a warning channel to ignore.
  legacy_spec : Bool
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
  /// Two spec blocks in one file — including one written `tutuca/spec` and one
  /// written `tutuca/spec`, which are two blocks however they are spelled.
  DuplicateStateBlock
  /// Two `<script type="tutuca/script">` blocks answer for the same component
  /// — the name is the `for=` attribute, or "" for an unqualified block.
  DuplicateScriptBlock(String)
  /// Two `<script type="tutuca/wax">` blocks answer for the same component.
  /// Same rule as the script block and for the same reason: a component's
  /// escapes are one body of source, and two would have to be concatenated in
  /// an order the file does not state.
  DuplicateWaxBlock(String)
  /// The spec block does not describe a component. `line` is the line in
  /// the HTML file, not in the block, because that is the file the author has
  /// open.
  BadStateBlock(line~ : Int, message~ : String)
  /// The init block does not fit the schema.
  BadInitBlock(line~ : Int, message~ : String)
  /// Two `<template>`s carry `data-root`. A file has one root, and two markers
  /// do not say which — the same reason two state blocks are refused.
  TwoRoots(String, String)
  /// Two `<script type="tutuca/test">` blocks in one file. The same rule the
  /// state block has, and for a plainer reason: the block is one JSON object,
  /// and two of them would have to be merged in an order the file does not
  /// state.
  DuplicateTestBlock
  /// The test block does not read as scenes. `line` is the line in the HTML
  /// file, not in the block, for the reason `BadInitBlock` gives.
  BadTestBlock(line~ : Int, message~ : String)
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

///|
/// The schema entry for a component, or None when the file declares none.
///
/// The pairing rule is `component_name`'s on both sides, so a consumer that
/// walks `components` and one that walks `state` agree on which pairs with
/// which.
declare pub fn ViewFile::state_of(
  self : ViewFile,
  comp : String,
  fallback~ : String,
) -> @statedef.StateDef?
