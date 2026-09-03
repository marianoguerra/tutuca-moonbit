// What a migration must never do, and the one thing it must.
//
// The rules will come and go — a keyword family is renamed, its rule lands,
// and one release later both the rule and the old spelling are deleted. What
// stays is the contract underneath them, which is what these are about: the
// file that comes back is the file that went in, minus exactly the spellings a
// rule names; running the tool twice is running it once; and a rule that is
// wrong about a span stops the file rather than writing over it.

///|
/// A card in the retired spelling, with everything a rule must not touch.
fn retired_card() -> String {
  (
    #|<!-- `tutuca/state` in a COMMENT, which is not a block and must not move. -->
    #|<script type="tutuca/state">
    #|  /// A doc comment mentioning tutuca/state, also not a block.
    #|  state Counter {
    #|    n : Int
    #|  }
    #|</script>
    #|
    #|<script type="tutuca/script">
    #|  receive bump { .n += 1 }
    #|</script>
    #|
    #|<template>
    #|  <button @on.click="bump"><x text=".n"></x></button>
    #|</template>
    #|
  )
}

///|
test "the retired block spelling is rewritten, and it is the only edit" {
  let m = @migrate.migrate_file(retired_card())
  @debug.assert_eq(m.edits.map(e => e.rule), [
    "tutuca/state", "tutuca/state", "tutuca/state",
  ])
  // Every occurrence, comment and doc comment included. A `type=` attribute
  // value is not a word the block language can also mean, so a literal rule is
  // the honest one here — and a comment that names the retired spelling is
  // prose that has gone stale exactly as much as the block has.
  assert_true(m.out.contains("tutuca/spec"))
  assert_false(m.out.contains("tutuca/state"))
  // Nothing else moved: the handler, the view and the blank lines are where
  // the author left them.
  assert_true(m.out.contains("receive bump { .n += 1 }"))
  assert_true(m.out.contains("<button @on.click=\"bump\">"))
  assert_eq(m.out.split("\n").count(), retired_card().split("\n").count())
}

///|
/// Running it twice is running it once.
///
/// The property the whole tool rests on: a rule that is not idempotent turns a
/// second `--write` into damage, and a repo where `migrate --write` is run on
/// save would find out in the worst possible way.
test "migration is idempotent" {
  let once = @migrate.migrate_file(retired_card())
  let twice = @migrate.migrate_file(once.out)
  assert_eq(twice.edits.length(), 0)
  assert_eq(twice.out, once.out)
}

///|
/// A file already in the current spelling comes back untouched.
test "a file with nothing to migrate is not rewritten" {
  let src =
    #|<script type="tutuca/spec">
    #|  state Counter { n : Int }
    #|</script>
    #|<template><x text=".n"></x></template>
    #|
  let m = @migrate.migrate_file(src)
  assert_eq(m.edits.length(), 0)
  assert_eq(m.out, src)
}

///|
/// A file that cannot be split is refused rather than half-rewritten.
///
/// Not because a rule would fail on it — the rule above is a literal scan and
/// would happily run — but because a file whose `<template>` boundaries are
/// not where they look is a file where "inside a template" means nothing, and
/// the next rule to land will be aimed at exactly that.
test "an unsplittable file is refused, and nothing is rewritten" {
  let broken =
    #|<script type="tutuca/state">
    #|  state A { n : Int }
    #|</script>
    #|<script type="tutuca/state">
    #|  state B { n : Int }
    #|</script>
    #|<template><p>x</p></template>
  let failed = try {
    let _ = @migrate.migrate_file(broken)
    false
  } catch {
    Unsplittable(_) => true
    _ => false
  }
  assert_true(failed)
}

// ---------------------------------------------------------------------------
// `apply`, on its own
// ---------------------------------------------------------------------------

///|
test "edits apply right to left, so an earlier span is not moved" {
  let src = "aXbXc"
  let out = @migrate.apply(src, [
    { span: { start: 1, end_: 2, }, from: "X", to: "LONGER", rule: "r", },
    { span: { start: 3, end_: 4, }, from: "X", to: "Y", rule: "r", },
  ])
  assert_eq(out, "aLONGERbYc")
}

///|
/// A rule that is wrong about what is there stops the file.
///
/// The failure this check exists for is silent: a span off by one writes a
/// replacement into the middle of a neighbouring word, the file still parses,
/// and the author finds out from a compiler in a file they did not think they
/// had changed.
test "an edit whose `from` is not what the file holds is refused" {
  let failed = try {
    let _ = @migrate.apply("hello", [
      { span: { start: 0, end_: 2, }, from: "XX", to: "yy", rule: "r", },
    ])
    false
  } catch {
    Mismatch(rule~, at~, want~, got~) => {
      assert_eq(rule, "r")
      assert_eq(at, 0)
      assert_eq(want, "XX")
      assert_eq(got, "he")
      true
    }
    _ => false
  }
  assert_true(failed)
}

///|
/// Two rules wanting the same text is a contradiction, and it is reported.
///
/// Resolving it — first rule wins, longest wins — would make the OTHER rule's
/// `from` a lie about the file it ran on, and a migration nobody can read back
/// is worse than one that stops.
test "overlapping edits are refused, naming both rules" {
  let failed = try {
    let _ = @migrate.apply("abcdef", [
      { span: { start: 0, end_: 3, }, from: "abc", to: "x", rule: "first", },
      { span: { start: 2, end_: 5, }, from: "cde", to: "y", rule: "second", },
    ])
    false
  } catch {
    Overlap(first~, second~, at~) => {
      assert_eq(first, "first")
      assert_eq(second, "second")
      assert_eq(at, 2)
      true
    }
    _ => false
  }
  assert_true(failed)
}

///|
test "no edits is the file, unchanged" {
  assert_eq(@migrate.apply("abc", []), "abc")
}

///|
test "the diff names the rule, not just the change" {
  let src =
    #|<script type="tutuca/state">
    #|  state A { n : Int }
    #|</script>
    #|<template><p>x</p></template>
  let m = @migrate.migrate_file(src)
  let lines = @migrate.diff_lines("card.html", m)
  assert_eq(lines.length(), 1)
  assert_true(lines[0].contains("tutuca/state -> tutuca/spec"))
  assert_true(lines[0].has_prefix("card.html:"))
}
