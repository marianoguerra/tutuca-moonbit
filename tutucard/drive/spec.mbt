// What driving a card answers. The implementation lives in drive.mbt and
// report.mbt.
//
//   guest + manifest + scenes --run--> a JSON report, one entry per scene
//
// The report carries the rendered HTML and the settled state WHETHER OR NOT
// the scene asserted anything, and that is the point rather than a
// convenience: a scene with no `expect` in it is a DRIVE, and what an agent
// wants from one is to see what the component did. Assertions are what you
// write once you have looked.

///|
/// One step's verdict.
pub(all) struct StepResult {
  /// The step's index in the scene, so a report can be read beside the block.
  at : Int
  ok : Bool
  /// What the step read, for a step that read something. Always present for a
  /// reader — including one that passed, because an agent that wrote no
  /// expectation is asking exactly this.
  got : @tutuca.Value?
  /// What it should have read. None for a drive step, and None for a reader
  /// written with no answer — which is the RECORD form, and never a failure.
  want : @tutuca.Value?
  /// Why it failed, in a sentence. Empty when it did not.
  why : String
} derive(Eq, @debug.Debug)

///|
/// What one scene did.
pub(all) struct SceneResult {
  name : String
  /// The component that was mounted, resolved: the scene's own, or the root.
  component : String
  ok : Bool
  /// The mounted DOM, serialized — cleaned of the renderer's bookkeeping
  /// unless the scene asked for it raw.
  html : String
  /// The settled root state.
  state : @tutuca.Value
  /// The component's compiled CSS.
  styles : String
  /// Every committed transaction, in order.
  activity : Array[Json]
  /// Everything refused while the scene ran, as the lines a refusal prints.
  /// The HOST's channel, and usually empty for a card — see `RLog`.
  refusals : Array[String]
  /// Everything the guest logged while the scene ran, in order. For a card
  /// this is where a declined `requires` / `ensures` / `invariant` shows up.
  log : Array[String]
  steps : Array[StepResult]
  /// Set when the scene could not be mounted at all, which is a different
  /// answer from a scene that ran and disagreed.
  error : String
} derive(Eq, @debug.Debug)

///|
/// How many activity records a scene keeps.
///
/// A bound rather than a budget, the same one the playground's panel has: a
/// scene that drives a hundred steps through a cascade produces a trace nobody
/// reads the middle of, and a report is a thing that gets pasted.
pub const ACTIVITY_CAP : Int = 200

///|
/// Drive every scene against one guest, and answer what each did.
///
/// `root` is the component a scene mounts when it names none — the card's
/// first, which is the only answer a single-component card has. Empty means
/// "the first the manifest declares", which is the same thing said by the
/// manifest rather than by the caller.
///
/// Nothing here raises. A scene that cannot be mounted is a `SceneResult` with
/// an `error` in it, because a block of ten scenes where the fourth names a
/// component that does not exist should still report the other nine — the same
/// argument `check` makes for showing a card with issues rather than refusing
/// to show one at all.
/// `take_log` drains whatever the guest has said since it was last asked —
/// `control.log`, which is where a compiled card reports a rule that did not
/// hold. Empty by default, because a host component has no such channel: it
/// raises a structured `Refusal` instead, and that is what `refused` reads.
declare pub fn run(
  guest : &@dyncomp.Guest,
  manifest : @dyncomp.DynManifest,
  scenes : Array[@scenedef.Scene],
  root? : String,
  take_log? : () -> Array[String],
  on_bundle? : (@dyncomp.Bundle) -> Unit,
) -> Array[SceneResult]

///|
/// Run a scene's steps against an app somebody else mounted. `component` and
/// `activity` come back empty — they are facts about how the app was made, and
/// this is handed one that already exists.
declare pub fn drive_scene(
  h : @harness.Harness,
  scene : @scenedef.Scene,
  take_log? : () -> Array[String],
) -> SceneResult

///|
/// The report as the JSON a page or a build step reads.
declare pub fn report_json(results : Array[SceneResult]) -> Json

///|
/// A mounted DOM as HTML, without the renderer's own bookkeeping.
///
/// `data-cid` and friends are how the dispatch path is reconstructed and the
/// `§…§` comments are where a component's subtree begins; neither is anything
/// a view wrote, and a snapshot that moves because a component id moved is a
/// snapshot nobody can keep. The predicates are `render`'s, so the list of
/// what counts as bookkeeping lives in one place.
declare pub fn clean_html(node : @memdom.MemNode) -> String
