// The rules, and the one function that runs them.
//
// A rule is a function from the file's source to edits over it. They compose
// by concatenation and nothing else — no rule sees another's output, and no
// rule may depend on running before or after another — which is what makes
// `apply`'s overlap check a real check rather than a formality: two rules
// wanting the same span is a contradiction the tool must report, not resolve.
//
// A rule that needs a BLOCK works from the block's own text and rebases its
// spans by `Block.offset`. That is the only reason the file is split at all.

///|
/// Every rule, in the order they are declared. The order does not matter to
/// the result — see above — and is kept stable so `--diff` output is stable.
fn rules() -> Array[(String) -> Array[Edit]] {
  [retired_spec_block, retired_fixtures_block]
}

// A `Instance[X]` → `Instance[X]` rule belongs here and is not written yet:
// the spec block has no retirement channel, because `statedef`'s lexer is
// private and a literal scan would rewrite the word in prose. It goes in with
// the rest of the spec-block family.

///|
/// The rules that need a BLOCK, run per block with its offset.
///
/// Separate from `rules()` because their spans come back in the block's own
/// coordinates and have to be rebased onto the file. That rebasing is the one
/// thing all of them share and the one thing every one of them could get
/// wrong, so it happens once, here.
fn block_rules() -> Array[(String) -> Array[Edit]] {
  [retired_script_keywords]
}

///|
pub fn migrate_file(
  source : String,
  name? : String = "",
) -> Migration raise MigrateError {
  // The file must split before any rule runs, even the ones that never look at
  // a block. A file that cannot be sliced is one whose `<template>` boundaries
  // are not where they appear to be, and a rule aimed at "inside a template"
  // would be aimed at the wrong text.
  //
  // `name` is the fallback component name, and it is passed for the same
  // reason `gen-views` passes it: a file whose single `state {}` block is
  // unnamed answers for the component the FILE is named after, and without it
  // a `handle Counter` beside it reads as naming a state block that is not
  // there.
  let file = @viewfile.split_file(source, name~) catch {
    e => raise Unsplittable(e.message())
  }
  let edits : Array[Edit] = []
  for rule in rules() {
    for e in rule(source) {
      edits.push(e)
    }
  }
  for sb in file.scripts {
    for rule in block_rules() {
      for e in rule(sb.block.text) {
        edits.push(rebase(e, sb.block.offset))
      }
    }
  }
  { out: apply(source, edits), edits, }
}

// ---------------------------------------------------------------------------
// Rules
// ---------------------------------------------------------------------------

///|
/// `<script type="tutuca/state">` is `<script type="tutuca/spec">`.
///
/// The first rule, and it is a rename that has ALREADY happened: the block is
/// spelled `spec` everywhere the repo writes one, and `state` still parses
/// because files outside the repo have not been rewritten. This is what
/// rewrites them.
///
/// It is also the rule with the best evidence for why the tool is worth
/// having. Two places in this repo went on matching the retired spelling long
/// after nothing wrote it — the benchmark corpus builder, which then kept
/// every schema block it was meant to strip, and the card playground's
/// structured editor, which then found no spec block in any card. Neither was
/// a file that failed to parse. Both were code reading for a word the language
/// had moved off.
fn retired_spec_block(source : String) -> Array[Edit] {
  literal_edits(source, "tutuca/state", "tutuca/spec", "tutuca/state")
}

///|
/// `<script type="tutuca/init">` is `<script type="tutuca/fixtures">`.
///
/// `init` was the wrong word twice over: the block holds SEVERAL named states
/// rather than one initial one, and `receive init` is an unrelated convention
/// a host dispatches after mounting — two things one word, in a file that
/// often has both.
fn retired_fixtures_block(source : String) -> Array[Edit] {
  literal_edits(source, "tutuca/init", "tutuca/fixtures", "tutuca/init")
}

///|
/// The retired words of the block language, from the parser that knows where
/// one can appear.
///
/// Not a text scan: `stop` is a retired effect at the head of a statement and
/// an ordinary field name three characters later. Only something that has
/// parsed as far as the statement can tell the two apart, so this asks the
/// parser — the same call the checker makes to warn about them.
fn retired_script_keywords(block : String) -> Array[Edit] {
  let out : Array[Edit] = []
  for r in @tscript.retired_spellings(block) {
    out.push({ span: r.span, from: r.word, to: r.replacement, rule: r.word, })
  }
  out
}

// ---------------------------------------------------------------------------
// Rule helpers
// ---------------------------------------------------------------------------

///|
/// A block-relative edit, moved onto the file.
fn rebase(e : Edit, offset : Int) -> Edit {
  { ..e, span: { start: e.span.start + offset, end_: e.span.end_ + offset, }, }
}

///|
/// Every occurrence of a literal, as edits.
///
/// The blunt instrument, and it is only ever right for a string that cannot
/// occur as anything else — a `type=` attribute value, not a keyword. A rule
/// over a WORD of the block language goes through that block's lexer, because
/// `stop` is also a field name, a class name and a word in a doc comment.
fn literal_edits(
  source : String,
  from : String,
  to : String,
  rule : String,
) -> Array[Edit] {
  let out : Array[Edit] = []
  let hay = source.to_array()
  let needle = from.to_array()
  let n = hay.length()
  let m = needle.length()
  if m == 0 || m > n {
    return out
  }
  let mut i = 0
  while i <= n - m {
    let mut k = 0
    while k < m && hay[i + k] == needle[k] {
      k = k + 1
    }
    if k == m {
      out.push({ span: { start: i, end_: i + m, }, from, to, rule, })
      i = i + m
    } else {
      i = i + 1
    }
  }
  out
}
