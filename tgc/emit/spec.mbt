// READONLY by convention: the public types plus `declare` stubs.

///|
/// What a compile produced.
///
/// `wax` is checked in to the answer rather than thrown away because it is the
/// discovery path: a card author who wants to know what a handler became reads
/// it, and an author writing an escape copies its idioms. `wasm` is what a host
/// instantiates.
pub(all) struct Compiled {
  /// The root component — what a host mounts when told no other name.
  component : String
  /// Every component the card declares, root first.
  components : Array[String]
  wasm : Bytes
  wax : String
  /// Declarations this backend could not lower. The rest of the card still
  /// runs, and the manifest leaves a refused name out — a host is never told a
  /// component answers something it does not.
  refusals : Array[Refusal]
  /// The declared fields of the root, in order.
  fields : Array[String]
  /// The manifest as JSON, for tooling. The MODULE carries its own
  /// (`tgc.describe`) and that one is authoritative; this is a projection.
  manifest : Json
}

///|
/// A card checked and not compiled.
pub(all) struct Checked {
  component : String
  components : Array[String]
  issues : Array[Issue]
} derive(Eq, Debug)

///|
/// One thing wrong with a card, from `tscript/check`.
pub(all) struct Issue {
  comp : String
  code : String
  message : String
  line : Int
  span : @tutuca.Span
} derive(Eq, Debug)

///|
/// One declaration this backend did not lower.
///
/// REFUSED is not REJECTED. A rejected card does not check and is turned away
/// whole; a refusal is per-declaration, leaves the rest of the card running,
/// and the host hears "unhandled" for that name and falls back to whatever the
/// declared field implies — exactly as it would for a handler nobody wrote.
pub(all) struct Refusal {
  comp : String
  kind : String
  name : String
  reason : String
  line : Int
  span : @tutuca.Span
} derive(Eq, Debug)

///|
/// The card being turned away whole.
pub suberror GenError {
  /// The file did not split into blocks.
  BadCard(String)
  /// The script block did not parse, or did not check.
  BadScript(Array[String])
  /// The generated Wax did not compile. This is a `tgc/emit` bug rather than
  /// an input error, and the message says so — a card that checks cannot
  /// produce a module that does not.
  BadModule(Array[String])
}

///|
declare pub fn GenError::message(self : GenError) -> String

///|
pub impl Show for GenError

///|
/// Check a card without compiling it: does it split, parse and check?
declare pub fn check_card(
  source : String,
  name~ : String,
) -> Checked raise GenError

///|
/// Compile a card to a `tgc` module.
declare pub fn compile(
  source : String,
  name~ : String,
) -> Compiled raise GenError

///|
/// Compile from declarations already in hand, for a caller that has them —
/// `tscript/conformance`'s adapter does, and building an HTML file around a
/// corpus row only to split it again would be a round trip through a format
/// neither side wanted.
declare pub fn compile_decls(
  states : Array[@statedef.StateDef],
  scripts : Map[String, Array[@tscript.Decl]],
  name~ : String,
  root~ : String,
) -> Compiled raise GenError
