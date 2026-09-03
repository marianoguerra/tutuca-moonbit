// Spec for the checker: what it reports, and what it needs in hand to report
// it. READONLY by convention; the implementation is in check.mbt.

///|
/// One finding. Collected rather than raised: a type error does not cascade
/// the way a syntax error does, and an author fixing one field at a time
/// because the checker stops at the first is the thing `tgc`'s `coerce`
/// already refuses to do to a caller.
pub(all) struct Finding {
  /// A short machine-readable label, so a host can filter and a test can
  /// assert on the RULE rather than on its wording.
  code : String
  message : String
  /// Whether a build should stop for this.
  ///
  /// Every finding is fatal except one: `NO_VIEW_HANDLER` reports a view name
  /// the block neither answers nor forwards, and such a name is not broken —
  /// it does nothing, which is sometimes exactly what was meant. A rule whose
  /// reported code still behaves correctly is a warning, and whether a strict
  /// mode should promote it is a question for the corpus to answer.
  severity : Severity
  /// Where, in the block's own coordinates. `@viewfile.Block` carries the
  /// offset that rebases it onto the file.
  span : @tutuca.Span
} derive(Debug, Eq)

///|
/// Whether a finding stops a build.
pub(all) enum Severity {
  SError
  SWarning
} derive(Debug, Eq)

///|
/// What the views contribute to checking a block, which the schema cannot
/// say.
///
/// An `on` handler's argument types are INFERRED from what the templates write
/// at the call site — `@on.click="add 1"` makes `add`'s first argument a
/// number — so they arrive from whoever compiled the views. `None` in the
/// array is the join of two call sites that disagreed, which is opaque and
/// therefore unchecked, exactly as `viewgen`'s own `join_arg` decides.
///
/// A name absent from the map is a handler no view calls. That is not an
/// error: a name can be raised from MoonBit, and the block is allowed to
/// answer one the templates never mention.
pub(all) struct Surface {
  inputs : Map[String, Array[@statedef.StateTy?]]
  /// Whether the caller HAS the views, or merely has none to show.
  ///
  /// An empty `inputs` means two different things and the checker has to tell
  /// them apart. From `viewgen` it means "I walked the templates and they send
  /// nothing" — a `receive` with no schema case is then answering a message
  /// nothing can send, which is the finding. From a caller with no views in
  /// hand (a block on its own, a card, a test) it means "I do not know", and
  /// reporting the same finding would be the checker asserting knowledge it
  /// has just said it lacks.
  ///
  /// It only became load-bearing when `on` merged into `receive`: an `on`
  /// handler's name was never checked against anything, so an absent surface
  /// cost nothing.
  knows_views : Bool
  /// Whether a message can arrive from OUTSIDE this file.
  ///
  /// `knows_views` says whether the views are known; this says whether they
  /// are the only senders. For a MoonBit component they are all that matters:
  /// a parent dispatches a TYPED value, so a `receive` that no view sends and
  /// no schema declares is answering a message nothing can send, which is the
  /// finding. A CARD is mounted by a host that dispatches a STRING, driven by
  /// scenes that `{"send": …}` it one, and shares a file with siblings that
  /// `sendAt` and `sendReply` — none of which this surface can see, so the
  /// same silence would be a false accusation rather than a missing rule.
  ///
  /// It changes NOTHING else: `NO_VIEW_HANDLER` still fires (the views send a
  /// name and the block does not answer it, which is true either way), and a
  /// name the views DO send still takes its parameter types and its arity
  /// from the call sites.
  open_senders : Bool
  /// The SIBLING components declared beside this one, so `new TodoItem` reads
  /// as "build the child" rather than as a type this block does not declare.
  ///
  /// Names only. What a sibling's fields are is a thing the checker could be
  /// told and is not: a pending child's fields are its own, and checking them
  /// here would mean carrying every sibling's schema through a surface that
  /// exists to describe THIS one. `TySet(None)` — opaque — is the honest answer
  /// until that is worth paying for.
  comps : Array[String]
} derive(Debug, Eq)

///|
/// A surface that knows nothing — every handler's arguments opaque, and no
/// claim about which names the views send.
///
/// What a caller with no views in hand passes, and what makes the checker
/// usable on a block alone.
declare pub fn Surface::empty() -> Surface

///|
/// The type a `new`'s reference names, or None when the schema declares none.
///
/// Here rather than in `tscript` because resolving a name needs a schema, and
/// here rather than in each backend because the checker and the MoonBit
/// emitter must agree about what `new Array[String]` is.
declare pub fn resolve_ty_ref(
  def : @statedef.StateDef,
  t : @tscript.TyRef,
) -> @statedef.StateTy?

///|
/// Check a block against a schema.
///
/// Answers every finding rather than the first, in source order.
declare pub fn check(
  decls : Array[@tscript.Decl],
  def : @statedef.StateDef,
  surface? : Surface,
  retired? : Array[@tscript.Retirement],
) -> Array[Finding]

///|
/// Check the SPEC block's rules — every `pred` and `invariant` — against the
/// schema they are about.
///
/// A second entry point rather than a branch inside `check`, because the two
/// answer about different TEXTS. A `Finding` carries a span in the block it
/// came from and a caller rebases it with that block's offset, so a finding
/// about a `pred` in the spec block and one about a `receive` in the script
/// block cannot ride in one list without landing in the wrong file position.
///
/// Every span here is relative to the spec block; rebase with
/// `@viewfile.ViewFile::state_block`.
declare pub fn check_rules(def : @statedef.StateDef) -> Array[Finding]

///|
/// The spec block's `pred`s and `invariant`s, as declarations a backend can
/// walk like any other, plus the names whose body did not parse.
///
/// Here rather than in either backend because BOTH need it and they must not
/// drift. A rule the SCRIPT block also declares is skipped, so the deprecation
/// window changes nothing about what a file already compiles to; `check`
/// reports that pair as `RULE_IN_BOTH`.
declare pub fn rule_decls(
  def : @statedef.StateDef,
  decls : Array[@tscript.Decl],
) -> (Array[@tscript.Decl], Array[String])
