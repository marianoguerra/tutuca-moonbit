// The check itself, on a file converted by hand.
//
// `tutucard/examples/Guarded.tutu` is the smallest card that has all five
// sections, which is why it is the one the migration page works through and the
// one this test holds both halves of.

///|
let guarded_html : String =
  #|<script type="tutuca/spec">
  #|  /// A counter with a rule, and a test block that watches the rule hold.
  #|  state Guarded {
  #|    /// How far it has counted.
  #|    n: Int
  #|
  #|    /// True while there is room left.
  #|    pred room
  #|      format $'the counter is full at {.n}' { .n < 3 }
  #|  }
  #|</script>
  #|
  #|<script type="tutuca/script">
  #|  /// Count one more, while there is room.
  #|  receive bump requires room {
  #|    .n += 1
  #|  }
  #|</script>
  #|
  #|<script type="tutuca/fixtures">
  #|{
  #|  "nearly full": {
  #|    "value": { "n": 2 },
  #|    "doc": "One press from the rule declining."
  #|  }
  #|}
  #|</script>
  #|
  #|<script type="tutuca/test">
  #|{
  #|  "the guard stops it at three": {
  #|    "steps": [
  #|      { "click": "button" },
  #|      { "expect": "text", "at": "output", "is": "3" }
  #|    ]
  #|  }
  #|}
  #|</script>
  #|
  #|<template id="Guarded">
  #|  <div>
  #|    <button @on.click="bump">+</button>
  #|    <output @text=".n"></output>
  #|  </div>
  #|</template>
  #|

///|
let guarded_tutu : String =
  #|spec:
  #|  /// A counter with a rule, and a test block that watches the rule hold.
  #|  Guarded:
  #|    /// How far it has counted.
  #|    field n :: Int
  #|
  #|    /// True while there is room left.
  #|    pred room:
  #|      ~format: @str{the counter is full at @(it.n)}
  #|      it.n < 3
  #|
  #|logic:
  #|  Guarded:
  #|    /// Count one more, while there is room.
  #|    receive bump:
  #|      ~requires: room
  #|      it.n += 1
  #|
  #|view:
  #|  Guarded:
  #|    @div{
  #|      @button(~on_click: bump){+}
  #|      @output{@(it.n)}
  #|    }
  #|
  #|fixtures:
  #|  "nearly full":
  #|    ~doc: "One press from the rule declining."
  #|    it.n = 2
  #|
  #|tests:
  #|  "the guard stops it at three":
  #|    click("button")
  #|    expect text("output") == "3"
  #|

///|
test "a hand-converted card is equivalent to the file it replaces" {
  let diffs = compare(guarded_html, guarded_tutu, name="Guarded")
  let lines = diffs.map(d => d.line())
  @debug.assert_eq(lines, [])
}

///|
/// The check has to be able to FAIL, or a green sweep says nothing.
///
/// Renaming a field is caught before any comparison runs: the fixture still
/// sets the old name, so the lowered file does not even split. That is the
/// better answer of the two — it names the field and suggests the new one —
/// and it is why the check reports what went wrong rather than only that
/// something did.
test "a conversion that renames a field is caught" {
  let broken = guarded_tutu.replace(old="field n :: Int", new="field m :: Int")
  let diffs = compare(guarded_html, broken, name="Guarded")
  assert_eq(diffs.length(), 1)
  assert_true(diffs[0].what.contains("which the schema does not declare"))
}

///|
/// A rule whose body changed IS a spec difference, and it is caught by meaning
/// rather than by text: the two notations parenthesise differently, so the
/// comparison parses both bodies (`compare_rules`).
test "a conversion that changes a rule's body is caught" {
  let broken = guarded_tutu.replace(old="it.n < 3", new="it.n < 4")
  let diffs = compare(guarded_html, broken, name="Guarded")
  assert_true(diffs.map(d => d.section).contains("spec"))
  assert_true(diffs.map(d => d.what).join(" ").contains("rule `room` body"))
}

///|
/// And a handler whose body changed is a `logic` difference.
test "a conversion that changes a handler is caught" {
  let broken = guarded_tutu.replace(old="it.n += 1", new="it.n += 2")
  let diffs = compare(guarded_html, broken, name="Guarded")
  assert_true(diffs.map(d => d.section).contains("logic"))
}

///|
/// And a view that lost a node is caught in `view`, which is the half the
/// direct reader answers for.
test "a conversion that loses a node is caught" {
  let broken = guarded_tutu.replace(
    old="@output{@(it.n)}",
    new="@output{@(it.count)}",
  )
  let diffs = compare(guarded_html, broken, name="Guarded")
  assert_true(diffs.map(d => d.section).contains("view"))
}
