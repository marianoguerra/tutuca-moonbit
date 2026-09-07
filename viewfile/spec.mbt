// The view file's public data types, plus `declare` stubs for the three
// questions asked of one. The implementation lives in file.mbt.
//
//   `.tutu` source --@viewgen.read_file--> ViewFile
//
// Everything above it — the generator, the checker, the card runtime — takes a
// `ViewFile` and never sees a reader.

///|
/// One view of a component: its tree, and the style scoped to it.
pub(all) struct RawView {
  name : String
  /// Empty, and kept for the one consumer that still reads a view as markup:
  /// `@anode.View::new`, which a MoonBit caller uses to build a view by hand.
  /// A view READ from a file is the tree below and nothing else.
  source : String
  style : String
  /// The tree. `tutufile/toanode` reads a `.tutu` straight into
  /// `@anode.ANode`, so there is no notation in between and nothing to parse a
  /// second time.
  tree : CompiledTree?
}

///|
/// A view already compiled: its tree and the event table its elements point
/// into by `data-eid`.
///
/// The pair travels together because neither is usable alone — an element
/// carries an index and the table is what it indexes.
pub(all) struct CompiledTree {
  root : @anode.ANode
  events : Array[@anode.NodeEvents]
  /// How much SOURCE this view is, in bytes.
  ///
  /// A number and not the text it measures. A compiled card's manifest carries
  /// it so that a host's quota can refuse a view before reading one — a
  /// refusal is meant to cost no parsing — and only the reader is in a
  /// position to say, because it is the only thing that ever held the slice.
  bytes : Int
}

///|
/// A macro declared in the `view:` section as `macro name(~p: default):`.
///
/// Declaring macros in the view file rather than registering them from
/// MoonBit is what lets the reader EXPAND them: a macro whose body is a
/// runtime value could never be compiled ahead of time. A view arrives with
/// its calls already grafted, so what a consumer needs of one is its name.
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
}

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
  /// The declarations, when the file was READ rather than split.
  ///
  /// The `logic:` section reads straight into `@tscript.Decl`s, and their
  /// spans point into the `.tutu` — which is the file the author has open,
  /// where the block's own offsets pointed into a block nobody wrote.
  decls : Array[@tscript.Decl]?
}

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
  /// The `<script type="tutuca/fixtures">` blocks, each paired with the
  /// component whose schema it was checked against.
  init : Array[(String, @statedef.InitState)]
  /// The `<script type="tutuca/script">` blocks, unparsed, in file order.
  /// Empty for every file that predates the language.
  scripts : Array[ScriptBlock]
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
}

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
