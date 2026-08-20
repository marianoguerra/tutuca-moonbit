// The data types a `<script type="tutuca/test">` block parses into, plus the
// `declare` stubs. The implementation lives in parse.mbt and errors.mbt.
//
//   block text --parse_scenes--> Array[Scene]
//
// Every verb below is one call on the headless harness, and that is deliberate
// rather than incidental: the block is a way to WRITE what a test already
// could, not a second testing story with semantics of its own. Adding a verb
// means adding a row here and a row in the runner's match; it never means
// teaching this package what a DOM is.

///|
/// One named scene: how to build the component, how to drive it, and what to
/// expect of it afterwards.
pub(all) struct Scene {
  name : String
  /// The component to mount. Empty means the card's root, which is the only
  /// answer a single-component card has.
  component : String
  /// A `tutuca/init` fixture to start from. Empty means none.
  init : String
  /// Field values to start from, merged over the fixture (or over the
  /// schema's zero when there is no fixture). The inline form of `init`.
  args : Map[String, @tutuca.Value]
  /// Intents this scene answers, by name.
  ///
  /// A card raises an intent at a HOST, and in a test the scene is the host.
  /// They answer synchronously — a page's fixtures answer late on purpose,
  /// because that is the half of asynchrony a card author has to write for,
  /// and a runner that returns has nothing to wait with.
  intents : Map[String, Answer]
  /// Keep the renderer's `data-cid` / `§…§` bookkeeping in the reported HTML.
  /// Off by default: a snapshot that moves because a component id moved is a
  /// snapshot nobody can read.
  raw : Bool
  steps : Array[Step]
} derive(Eq, @debug.Debug)

///|
/// What a scene's intent fixture answers. The three an intent has
/// (`@component.IntentAnswer`), as data rather than as a closure, so this
/// package needs no component runtime.
pub(all) enum Answer {
  AOk(@tutuca.Value)
  AFailed(@tutuca.Value)
  /// Declines. The route walks on, and if nothing else answers the sender
  /// hears `<name>Unhandled` — a different sentence from a failure's, and the
  /// path a test is likeliest to leave uncovered.
  APass
} derive(Eq, @debug.Debug)

///|
/// One step of a scene: something done, or something read.
///
/// `nth` picks among matches and is 0 when the block does not say.
pub(all) enum Step {
  Click(sel~ : String, nth~ : Int)
  Type(sel~ : String, value~ : String, nth~ : Int)
  Key(sel~ : String, key~ : String, value~ : @tutuca.Value?, nth~ : Int)
  Check(sel~ : String, checked~ : Bool, nth~ : Int)
  Fire(
    sel~ : String,
    event~ : String,
    value~ : @tutuca.Value?,
    key~ : String,
    nth~ : Int
  )
  Drag(sel~ : String, from~ : Int, to~ : Int)
  /// A host dispatch at the root. `init` is the one every card needs, since
  /// tutuca has no lifecycle and the host is what runs it.
  Send(name~ : String, args~ : Array[@tutuca.Value])
  Read(Expect)
} derive(Eq, @debug.Debug)

///|
/// A read, and what it should answer.
pub(all) struct Expect {
  reader : Reader
  /// The selector, or — for `RState` — the dotted place, already parsed.
  sel : String
  place : Array[@tutuca.Step]
  /// The attribute or property name, for the two readers that take one.
  name : String
  nth : Int
  /// What it should answer, or None for RECORD: the runner reads it and hands
  /// the answer back instead of judging it. That is `moon test --update` for a
  /// card, and it is what makes writing one of these worth an agent's time —
  /// drive first, read what the component actually did, keep what you meant.
  want : Want?
} derive(Eq, @debug.Debug)

///|
/// The readers. Each is one `Harness` call.
pub(all) enum Reader {
  RText
  RTexts
  RAttr
  RProp
  RValue
  RChecked
  /// How many elements match. The one reader with no counterpart on the
  /// harness, because `find_all(sel).length()` did not need a name until a
  /// block had to spell it.
  RCount
  /// The settled root state, whole or at a place.
  RState
  RHtml
  /// Renders so far — what a batching assertion is written against.
  RRenders
  /// The refusals raised since the previous step.
  ///
  /// The host-side channel: a message no component claims, a path that does not
  /// resolve. For a CARD it is usually empty and that is not a bug — a compiled
  /// guest is asked about every `receive` by name and answers `unhandled`
  /// rather than declining, so the host has nothing to refuse. What a card says
  /// instead is `RLog`.
  RRefused
  /// What the card LOGGED since the previous step.
  ///
  /// This is the reader that makes a scene about a guarded button mean
  /// something, and it has to be a second one because a card and a host
  /// component report a declined rule differently. A host component raises a
  /// structured `Refusal`; a compiled card has no shape to put one in on the
  /// guest boundary, so a `requires`, an `ensures` or an `invariant` that did
  /// not hold crosses as `control.log` — the one call on the control interface
  /// no capability gates — carrying the rule's own `format` sentence evaluated
  /// over the state that was rejected.
  ///
  /// Without it, a declined guard and a click that missed are the same thing
  /// seen from the DOM: nothing moved.
  RLog
} derive(Eq, @debug.Debug)

///|
/// The two shapes an expectation comes in.
pub(all) enum Want {
  /// `"is": …` — the whole answer, exactly.
  WIs(@tutuca.Value)
  /// `"contains": "…"` — a substring. Only `html` and `text` take one; for
  /// anything else `is` says what is meant with no room to be approximate.
  WContains(String)
} derive(Eq, @debug.Debug)

///|
/// The word a reader is written with, for messages and for round-tripping a
/// recorded scene back into the block.
declare pub fn Reader::word(self : Reader) -> String

///|
/// Anything that makes a test block unusable.
///
/// Every case carries the scene and the step index, because a block is a list
/// and "expected a string" with no position in it is a sentence an author has
/// to go looking for the meaning of.
pub suberror SceneError {
  /// The block is not JSON.
  NotJson(String)
  /// The block is JSON but not an object of named scenes.
  NotScenes
  /// A named scene is not an object.
  SceneNotObject(String)
  /// A scene declares no `steps`, or declares something that is not a list.
  NoSteps(String)
  /// A step is not an object.
  StepNotObject(scene~ : String, at~ : Int)
  /// A step object names no verb this package knows.
  NoVerb(scene~ : String, at~ : Int, suggestion~ : String?)
  /// A step names two. One key is the verb, and a step that says both `click`
  /// and `type` does not say which happens first.
  TwoVerbs(scene~ : String, at~ : Int, first~ : String, second~ : String)
  /// A verb is missing a key it cannot be performed without.
  MissingKey(scene~ : String, at~ : Int, verb~ : String, key~ : String)
  /// A key is present with the wrong shape.
  BadType(
    scene~ : String,
    at~ : Int,
    key~ : String,
    want~ : String,
    got~ : String
  )
  /// `expect` names something that is not a reader.
  NoSuchReader(
    scene~ : String,
    at~ : Int,
    reader~ : String,
    suggestion~ : String?
  )
  /// A selector the harness cannot mean what the author meant by it.
  BadSelector(scene~ : String, at~ : Int, sel~ : String, why~ : String)
  /// A `state` place that does not read as one.
  BadPlace(scene~ : String, at~ : Int, place~ : String, why~ : String)
  /// An intent fixture that is not one of the three answers.
  BadIntent(scene~ : String, name~ : String, why~ : String)
  /// `contains` on a reader that does not answer text.
  NotContainable(scene~ : String, at~ : Int, reader~ : String)
}

///|
/// The one-line message reported beside the card.
declare pub fn SceneError::message(self : SceneError) -> String

///|
/// Parse a `tutuca/test` block into the scenes it declares.
///
/// Scenes come back in the order the block writes them: a block is read
/// top-to-bottom by whoever wrote it, and a report that reorders them is a
/// report that has to be searched.
declare pub fn parse_scenes(source : String) -> Array[Scene] raise SceneError

///|
/// Why a dotted place does not read as one. Its own type rather than a
/// `SceneError` case because `parse_place` is handed a string and knows
/// nothing about which scene or which step it came from; the caller that does
/// know wraps it in `BadPlace`.
pub suberror PlaceError {
  PlaceError(String)
}

///|
declare pub fn PlaceError::message(self : PlaceError) -> String

///|
/// Read a dotted place — `.count`, `.rows[0].label`, `.byId['a'].n` — as the
/// path steps `@tutuca.Path::lookup` walks.
///
/// The block language's own spelling, restricted to what a READ needs: a
/// field, a literal index and a literal key. `&.panes[.sel]` — a key re-read
/// from live state — is deliberately absent, because a scene asserts about a
/// state it already has in front of it.
declare pub fn parse_place(src : String) -> Array[@tutuca.Step] raise PlaceError
