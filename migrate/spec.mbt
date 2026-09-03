// What a migration IS, before any rule says what it does.
//
// One edit is a span in the original file and the text that replaces it. That
// is the whole vocabulary, and it is deliberately smaller than an AST rewrite:
// a rule that can only replace a range cannot move a declaration, cannot
// reorder arguments and cannot reformat a body it does not understand. Those
// are the three ways a migration tool eats a file, and none of them is
// reachable from here.

///|
/// One replacement: where, what was there, and what goes in its place.
///
/// `from` is carried rather than re-sliced because it is what a `--diff` line
/// shows and what a test pins. A rule that reports a `from` the file does not
/// hold at `span` is a rule with a span bug, and `apply` says so rather than
/// writing the damage.
///
/// `rule` names the retirement, in the form a reader can look up — `stop`,
/// `tutuca/state`. It is the only reason `--diff` output is worth reading
/// twice: a file with nine edits from one rule is a different situation from
/// one with nine rules touching it once each.
pub(all) struct Edit {
  span : @tutuca.Span
  from : String
  to : String
  rule : String
} derive(Eq, @debug.Debug)

///|
/// A file, rewritten, and what was done to it.
///
/// `out` is the whole file — not a patch — because that is what a caller
/// writes back and what an idempotence test re-feeds. `edits` is empty exactly
/// when `out` equals the input, which is the check `--diff` reports nothing on.
pub(all) struct Migration {
  out : String
  edits : Array[Edit]
} derive(Eq, @debug.Debug)

///|
/// Anything that stops a file being migrated at all.
///
/// Separate from an edit that does not apply: this is a fact about the FILE.
/// A file whose blocks cannot be found is one no rule can be aimed at, and
/// saying so beats rewriting the parts that were legible.
pub suberror MigrateError {
  /// The file does not split into blocks — an unclosed `<template>`, two spec
  /// blocks, a `<script type="tutuca/spec">` that does not describe a
  /// component. The message is the file error's own.
  Unsplittable(String)
  /// Two rules claimed overlapping spans. A bug in a rule rather than in the
  /// file, and it stops the migration because applying either one silently
  /// would make the other's `from` a lie.
  Overlap(first~ : String, second~ : String, at~ : Int)
  /// An edit's `from` is not what the file holds at its span. Also a rule bug,
  /// and the one that would corrupt a file if it were let through.
  Mismatch(rule~ : String, at~ : Int, want~ : String, got~ : String)
}

///|
/// Rewrite one file's source, and say what was rewritten.
///
/// `name` is the component a file's unnamed `state {}` block answers for, the
/// same fallback `gen-views` derives from the basename.
///
/// The file must SPLIT — the blocks have to be findable — but it need not
/// otherwise be valid: a card whose script block has a syntax error still gets
/// its template and spec rules applied, because those rules never looked
/// inside the script block. A rule that needs a block to lex says so by
/// declining, not by failing the file.
declare pub fn migrate_file(
  source : String,
  name? : String,
) -> Migration raise MigrateError

///|
/// Apply edits to `source`, right-to-left so an earlier span is not moved by a
/// later replacement.
///
/// Public because it is the half worth testing on its own: every rule below
/// produces edits, and exactly one thing applies them.
declare pub fn apply(
  source : String,
  edits : Array[Edit],
) -> String raise MigrateError

///|
/// The edits as a reviewable list, one line each.
///
/// `path:offset  rule  from -> to`. Not a unified diff: an edit is a word, and
/// three lines of context around a word is nine lines of noise. A caller that
/// wants a real diff has `out` and the original.
declare pub fn diff_lines(path : String, m : Migration) -> Array[String]
