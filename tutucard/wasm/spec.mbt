// What compiling a card answers.
//
// READONLY by convention: the implementation is in compile.mbt / expr.mbt /
// stmt.mbt, and the fixed runtime those two emit calls into is runtime.mbt.

///|
/// One thing this generator would not compile, and why.
///
/// A refusal is not an error. tutuca's own view generator already works this
/// way — "a handler the block cannot compile is REFUSED by name, with the
/// reason, and comes back as an `update~` argument" — and the same shape is
/// the honest one here: a card whose `toggle` handler pushes to a list still
/// has four other handlers, a schema and a set of views, and a module that
/// carries those is worth more than a failure that carries nothing.
///
/// What a refused declaration DOES at runtime is nothing: the name is not in
/// the dispatch table, so the guest answers `unhandled` and the host falls
/// back to the mutator the declared field implies — which is exactly what a
/// guest that never declared the handler would do.
pub(all) struct Refusal {
  /// The declaration's kind word: `on`, `receive`, `compute`, … or `field`
  /// for a state field whose type has no cell representation.
  kind : String
  name : String
  /// One sentence, in the same voice as a `CardIssue`: what could not be
  /// compiled, and what would work instead.
  reason : String
  /// 1-based in the FILE, so an editor can put it beside the line.
  line : Int
  span : @tscript.Span
} derive(Debug, Eq)

///|
/// A compiled card: the bytes, and everything a host needs to mount them.
///
/// `manifest` and `descriptor` are here rather than left to the caller because
/// they are not independent of the wasm — the descriptor states the string
/// encoding the module was built with, and the manifest's field list is the
/// order `get-field` answers in. A bundle whose three parts were assembled
/// separately is a bundle whose parts can disagree.
pub(all) struct Compiled {
  component : String
  /// A `tutuca:component@0.7.0` core module. No component wrapper, no
  /// JavaScript: `dyncomp/host/wasm/abi.mjs` instantiates this directly.
  wasm : Bytes
  /// The same module printed as WAT. Nothing reads it — it is what makes the
  /// generator inspectable, and what a playground shows beside the card.
  wat : String
  /// And printed as WAX, which is the language it was built in.
  ///
  /// The AST goes back through `marianoguerra/wax`'s own formatter, so what a
  /// reader sees is the source a hand-writer would have had to type — the
  /// stdlib, the card runtime and the generated half, in the order they are
  /// concatenated. It is the more useful of the two panels by a distance: WAT
  /// is what the module IS, and this is what the generator SAID.
  wax : String
  refusals : Array[Refusal]
  /// The state fields, in the order their cells are laid out.
  fields : Array[String]
  /// The `DynManifest` JSON `dyncomp/host.register_bundle` parses.
  manifest : Json
  /// `{ world, encoding, core }` — what an archive carries in place of the
  /// 200KB of JavaScript `jco transpile` used to put in one.
  descriptor : Json
}

///|
/// Anything that leaves no module at all.
///
/// The same split `tutucard.CardError` makes, and for the same reason: a file
/// that does not divide into blocks, or a script that does not parse, has no
/// declarations to refuse one at a time.
pub suberror GenError {
  /// The card itself is not loadable. Carries the message rather than the
  /// error, because the caller has already been told this by `tutucard.load`.
  BadCard(String)
  /// The script parses but does not CHECK: a name that resolves to nothing, a
  /// builtin called with the wrong arity, a `@show` that never hides.
  ///
  /// A rejection rather than a per-declaration refusal, and the difference
  /// matters. A refusal says "this backend cannot compile that yet" and leaves
  /// the host to fall back; this says "that is not a card", which is true of
  /// every backend and would be true of a hand-written one. Emitting a module
  /// with a hole where the handler should be would turn a mistake into a
  /// silent fallback.
  BadScript(Array[String])
  /// The file declares no `state` block, so there are no fields, no zero and
  /// nothing for a handler to change. A card like that is a set of views,
  /// which the host can render without a guest at all.
  NoState
  /// Wax rejected the module this generator built. Always a bug HERE — the
  /// card's own mistakes were found before a single instruction was emitted —
  /// so it carries the diagnostics verbatim rather than a friendly summary.
  BadModule(Array[String])
}

///|
pub fn GenError::message(self : GenError) -> String {
  match self {
    BadCard(m) => m
    NoState =>
      "a compiled card needs a <script type=\"tutuca/state\"> block: the state is what an instance IS, and a guest with no fields has nothing to answer get-field with"
    BadScript(fs) => "this card does not check: " + fs.join("; ")
    BadModule(ds) =>
      "the generated module did not type-check (this is a cardwasm bug): " +
      ds.join("; ")
  }
}
