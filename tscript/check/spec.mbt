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
  /// Where, in the block's own coordinates. `@viewfile.Block` carries the
  /// offset that rebases it onto the file.
  span : @tscript.Span
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
/// Check a block against a schema.
///
/// Answers every finding rather than the first, in source order.
declare pub fn check(
  decls : Array[@tscript.Decl],
  def : @statedef.StateDef,
  surface? : Surface,
) -> Array[Finding]
