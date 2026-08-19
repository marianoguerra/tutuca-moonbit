// Spec for the checker: what it reports, and what it needs in hand to report
// it. READONLY by convention; the implementation is in check.mbt.

///|
/// One finding. Collected rather than raised: a type error does not cascade
/// the way a syntax error does, and an author fixing one field at a time
/// because the checker stops at the first is the thing `dyncomp`'s `coerce`
/// already refuses to do to a caller.
pub(all) struct Finding {
  /// A short machine-readable label, so a host can filter and a test can
  /// assert on the RULE rather than on its wording.
  code : String
  message : String
  /// Whether a build should stop for this.
  ///
  /// Every finding was fatal until v2, and every finding still IS except one:
  /// `NO_VIEW_HANDLER` reports a view name the block neither answers nor
  /// forwards, and that code behaves exactly as v1 behaves — it does nothing.
  /// A rule whose warned-about code is already correct cannot be an error
  /// without breaking every project that upgrades, which is why the design
  /// (`totuka-v2.md` section 7) lands it as a warning and leaves the strict
  /// mode to be decided from a corpus rather than from a document.
  severity : Severity
  /// Where, in the block's own coordinates. `@viewfile.Block` carries the
  /// offset that rebases it onto the file.
  span : @tscript.Span
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
} derive(Debug, Eq)

///|
/// A surface that knows nothing — every `on` handler's arguments opaque.
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
) -> Array[Finding]
