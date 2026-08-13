// Spec for the card runtime: what a card is and what loading one answers.
// READONLY by convention; the implementation is in card.mbt / obj.mbt.

///|
/// Everything wrong with a card, in one list.
///
/// Collected, not raised. A card is edited in a browser with the result beside
/// it, so "here is every problem" is worth far more than "here is the first
/// one"; and a card authored by a model is corrected in one round trip rather
/// than as many as it has mistakes, which is the same argument
/// `dyncomp/jsonschema/coerce.mbt` makes about a tool call.
///
/// `line` is 1-based in the FILE, not in the block — the file is what the
/// author has open.
pub(all) struct CardIssue {
  code : String
  message : String
  line : Int
  /// The character range in the file. Both halves are here because they answer
  /// different questions: a message says the line out loud, and an editor
  /// underlines the range.
  span : @tscript.Span
} derive(Debug, Eq)

///|
/// A card that loaded: its component, and everything that was wrong with it
/// anyway.
///
/// Issues and a component TOGETHER, because a card with a bad handler still
/// has views worth rendering and a state worth showing. Refusing to mount
/// anything until everything is right is what makes a live editor unusable —
/// the one thing a card runtime exists to be good at.
pub(all) struct Card {
  component : @component.Component
  issues : Array[CardIssue]
  /// The schema the card declares, or None for a card with no state block.
  def : @statedef.StateDef?
  /// The `<template id="macro:name">` declarations the file holds.
  ///
  /// Carried rather than expanded here: a macro is expanded when a view is
  /// COMPILED, against the scope the component was registered in, so what the
  /// loader can do is hand them to the host — which passes them to
  /// `ModuleDef::new(macros~)` and lets the ordinary lookup find them. That is
  /// the same path a module's macros take; a card's are not a second kind.
  macros : Map[String, @anode.Macro]
}

///|
/// Anything that stops a card being loaded at all.
///
/// Distinct from `CardIssue` on purpose: these are failures of the FILE and of
/// the SYNTAX, which leave nothing to mount. A type error leaves a component;
/// an unclosed template does not.
pub suberror CardError {
  /// The file does not split.
  BadFile(@viewfile.FileError)
  /// The script block does not parse. `line` is in the file.
  BadScript(line~ : Int, message~ : String, span~ : @tscript.Span)
  /// The file declares no `<template>`, so there is nothing to render.
  NoViews
  /// The file declares several components; a card is one.
  ManyComponents(Array[String])
}

///|
/// The one-line message a host reports.
declare pub fn CardError::message(self : CardError) -> String

///|
/// Load a card from the source of one `.html` file.
///
/// `name` is used when the file's template ids do not name a component, which
/// is the ordinary case for a single-component file.
declare pub fn load(source : String, name~ : String) -> Card raise CardError

///|
/// The card's initial state, as the fields map an instance starts with.
///
/// The zero the schema implies, overlaid with a named `tutuca/init` fixture
/// when one is asked for. A name no fixture answers falls back to the zero
/// rather than failing: a storybook asking for an example a card dropped is
/// not a reason to render nothing.
declare pub fn Card::initial(
  self : Card,
  fixture? : String,
) -> Map[String, @tutuca.Value]
