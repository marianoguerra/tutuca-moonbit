// The schema-aware view checks.
//
// Half of these are negative fixtures: each is a view that renders WRONG and
// silently today, and the assertion is that it now fails generation with a
// message naming the fix. The other half guard against the opposite failure
// — a check firing on a view that is fine — which is the way a generator
// like this actually gets abandoned.

///|
/// Generate, returning the error message or "" on success.
fn gen_err(html : String, name : String) -> String {
  try {
    @viewgen.generate(html, name~, source_file="t.html") |> ignore
    ""
  } catch {
    e => e.message()
  }
}

///|
/// A state block wrapping the given declarations for the `Board` component.
fn board(state : String, view : String) -> String {
  "<script type=\"tutuca/spec\">\n" +
  state +
  "\n</script>\n<template>" +
  view +
  "</template>"
}

///|
test "a misspelt root field fails generation and suggests the right name" {
  let msg = gen_err(
    board(
      "state Board { label: String, count: Int }", "<p><x text=\".labelx\"></x></p>",
    ),
    "Board",
  )
  assert_true(msg.contains("`.labelx` is not a field of the Board state"))
  assert_true(msg.contains("did you mean `.label`?"))
}

///|
test "a field with no near miss is told where to declare it" {
  let msg = gen_err(
    board(
      "state Board { label: String }", "<p><x text=\".somethingElse\"></x></p>",
    ),
    "Board",
  )
  assert_true(msg.contains("not a field of the Board state"))
  assert_true(msg.contains("tutuca/spec"))
}

///|
test "reads inside an @each are checked against the ELEMENT type" {
  // The hole this whole stage exists to close: view_surface stops collecting
  // field reads under @each, so before now this was not merely unchecked —
  // it was not even looked at.
  let msg = gen_err(
    board(
      "struct Card { title: String, done: Bool }\nstate Board { cards: Array[Card] }",
      "<ul><li @each=\".cards\"><x text=\".titel\"></x></li></ul>",
    ),
    "Board",
  )
  assert_true(msg.contains("`.titel` is not a field of Card"))
  assert_true(msg.contains("did you mean `.title`?"))
}

///|
test "@value.member inside a loop is checked too" {
  let msg = gen_err(
    board(
      "struct Card { title: String }\nstate Board { cards: Array[Card] }", "<ul><li @each=\".cards\"><x text=\"@value.titel\"></x></li></ul>",
    ),
    "Board",
  )
  assert_true(msg.contains("not a field of the loop item (Card)"))
  assert_true(msg.contains("did you mean `.title`?"))
}

///|
test "a correct loop body generates cleanly" {
  assert_eq(
    gen_err(
      board(
        "struct Card { title: String, done: Bool }\nstate Board { cards: Array[Card] }",
        "<ul><li @each=\".cards\"><x text=\".title\"></x><x text=\"@value.done\"></x></li></ul>",
      ),
      "Board",
    ),
    "",
  )
}

///|
test "@each over a scalar is refused" {
  let msg = gen_err(
    board("state Board { count: Int }", "<ul><li @each=\".count\">x</li></ul>"),
    "Board",
  )
  assert_true(msg.contains("`@each` needs a collection"))
  assert_true(msg.contains("`.count` is Int"))
}

///|
test "@each over a set, a list or an ordered map is fine" {
  for
    expr in [
      ("state Board { tags: Set[String] }", ".tags"),
      ("state Board { xs: Array[Int] }", ".xs"),
      ("state Board { m: Map[String, Any] }", ".m"),
    ] {
    let (state, path) = expr
    assert_eq(
      gen_err(board(state, "<ul><li @each=\"\{path}\">x</li></ul>"), "Board"),
      "",
    )
  }
}

///|
test "<x render> on a non-component is refused" {
  let msg = gen_err(
    board(
      "state Board { label: String }", "<div><x render=\".label\"></x></div>",
    ),
    "Board",
  )
  assert_true(msg.contains("`<x render>` needs a component"))
  assert_true(msg.contains("`.label` is String"))
}

///|
test "<x render> on a declared child slot is fine" {
  let html = "<script type=\"tutuca/spec\">\n" +
    "state Card { title: String }\n" +
    "state Board { lead: Card }\n" +
    "</script>\n" +
    "<template id=\"Card\"><p><x text=\".title\"></x></p></template>\n" +
    "<template id=\"Board\"><div><x render=\".lead\"></x></div></template>"
  assert_eq(gen_err(html, "Ignored"), "")
}

///|
test "an opaque scope silences the checks inside it" {
  // `any` and a child component have no schema this file can see, so a read
  // through either is unknown — and unknown must never mean wrong, or the
  // escape hatch stops being one.
  assert_eq(
    gen_err(
      board(
        "state Board { detail: Any, slot: Component, rows: Array[Any] }",
        "<div><x render=\".slot\"></x>" +
        "<ul><li @each=\".rows\"><x text=\".whatever\"></x></li></ul>" +
        "</div>",
      ),
      "Board",
    ),
    "",
  )
}

///|
test "a file with no state block is checked exactly as before" {
  // No schema, no checks — this is what lets the corpus migrate one file at
  // a time instead of all at once.
  assert_eq(
    gen_err(
      "<template><p><x text=\".anythingAtAll\"></x></p></template>", "Board",
    ),
    "",
  )
}

///|
test "the counter demo's own view passes its schema" {
  // The migrated reference example, checked here as well as by compiling.
  let html = "<script type=\"tutuca/spec\">\n" +
    "state Counter { label: String, count: Int, history: Array[Int] }\n" +
    "</script>\n" +
    "<template>\n" +
    "  <h1><x text=\".label\"></x>: <x text=\".count\"></x></h1>\n" +
    "  <ul><li @each=\".history\"><x text=\"@value\"></x></li></ul>\n" +
    "</template>"
  assert_eq(gen_err(html, "Counter"), "")
}

///|
test "a nested record two levels down is still checked" {
  let msg = gen_err(
    board(
      "struct Inner { deep: String }" +
      "struct Outer { inner: Inner }" +
      "state Board { o: Outer }",
      "<p><x text=\".o\"></x><span @each=\".o\">x</span></p>",
    ),
    "Board",
  )
  // `.o` is a record, which is not iterable.
  assert_true(msg.contains("`@each` needs a collection"))
  assert_true(msg.contains("Outer"))
}

///|
test "@push-view and @enrich-with keep the state scope" {
  // `@push-view` pushes a VIEW NAME onto the render stack, not a value
  // (render/render.mbt:63), and `@enrich-with` pushes binds. The state under
  // both is still this component's, so its fields must stay checkable — and
  // reads that are fine must not be flagged.
  assert_eq(
    gen_err(
      board(
        "state Board { items: Array[Any], view: String, q: String }",
        "<div @push-view=\".view\"><x render-each=\".items\"></x>" +
        "<p><x text=\".q\"></x></p></div>",
      ),
      "Board",
    ),
    "",
  )
  // ...and a typo under a push-view is still caught, which it would not be
  // if the scope went opaque.
  let msg = gen_err(
    board(
      "state Board { items: Array[Any], view: String, q: String }", "<div @push-view=\".view\"><p><x text=\".qq\"></x></p></div>",
    ),
    "Board",
  )
  assert_true(msg.contains("`.qq` is not a field of the Board state"))
}

///|
test "a container in @show is a test that cannot fail" {
  // `Value::is_truthy` answers `true` for List, Map and Obj unconditionally
  // (core/value_eval.mbt:98), so `@show=".alts"` shows the element for an
  // EMPTY list too. It reads as a guard and is not one.
  let msg = gen_err(
    board(
      "state Board { alts: Array[String] }", "<div @show=\".alts\">alternatives</div>",
    ),
    "Board",
  )
  assert_true(msg.contains("always truthy"))
  assert_true(msg.contains("empty? .alts"))
  // A record is the same story, and so is `@hide`.
  let rec = gen_err(
    board(
      "struct Card { title: String }\nstate Board { c: Card }", "<div @hide=\".c\">x</div>",
    ),
    "Board",
  )
  assert_true(rec.contains("`@hide=\".c\"`"))
  assert_true(rec.contains("always truthy"))
}

///|
test "a truthiness test that can decide something is left alone" {
  // The predicate is the fix the message asks for, so it must not itself
  // trip the check.
  assert_eq(
    gen_err(
      board(
        "state Board { alts: Array[String] }", "<div @show=\"empty? .alts\">none</div>",
      ),
      "Board",
    ),
    "",
  )
  // A string, a number and an option are NOT flagged. `@show=".role"` beside
  // `@text=".role"` hides an empty badge and is the idiomatic spelling —
  // storybook/examples/personal_site.html does exactly this.
  assert_eq(
    gen_err(
      board(
        "state Board { role: String, count: Int, note: String?, on: Bool }",
        "<p @show=\".role\">r</p><p @show=\".count\">c</p>" +
        "<p @show=\".note\">n</p><p @hide=\".on\">o</p>",
      ),
      "Board",
    ),
    "",
  )
  // An unknown type still checks nothing: unknown is not wrong.
  assert_eq(
    gen_err(
      board("state Board { anything: Any }", "<div @show=\".anything\">x</div>"),
      "Board",
    ),
    "",
  )
}

///|
test "a constant id inside a loop is not an id" {
  // The loop emits its body once per item, so `id="row"` is stamped on every
  // one of them. Only the compiled tree knows the element repeats — this is
  // not visible to an HTML linter reading the source.
  let msg = gen_err(
    board(
      "state Board { items: Array[Any] }", "<ul><li @each=\".items\" id=\"row\"><x text=\"@value\"></x></li></ul>",
    ),
    "Board",
  )
  assert_true(msg.contains("`id=\"row\"` sits inside an `@each`"))
  assert_true(msg.contains("use a class"))
  // Nested one level deeper is the same story.
  assert_true(
    gen_err(
      board(
        "state Board { items: Array[Any] }", "<ul><li @each=\".items\"><span id=\"cell\">x</span></li></ul>",
      ),
      "Board",
    ).contains("`id=\"cell\"`"),
  )
}

///|
test "an id outside the loop, and a per-item id, are both fine" {
  assert_eq(
    gen_err(
      board(
        "state Board { items: Array[Any] }",
        "<ul id=\"list\"><li @each=\".items\" :id=\"$'row-{@key}'\">" +
        "<x text=\"@value\"></x></li></ul>",
      ),
      "Board",
    ),
    "",
  )
  // `<x render-each>` drops the element it is written on, so there is no host
  // markup to repeat and nothing to report.
  assert_eq(
    gen_err(
      board(
        "state Board { items: Array[Any] }", "<div id=\"pane\"><x render-each=\".items\"></x></div>",
      ),
      "Board",
    ),
    "",
  )
}

///|
/// Generate, returning the ADVISORY findings (the `hints` channel) rather than
/// the fatal ones.
fn gen_hints(html : String, name : String) -> Array[String] {
  let hints : Array[String] = []
  try
    @viewgen.emit_module(name, "t.html", @viewgen.split_file(html), hints~)
    |> ignore
  catch {
    _ => ()
  }
  hints
}

///|
/// Two components in one file: a Page holding a list of Rows.
fn page_and_row(page_view : String, row_views : String) -> String {
  "<script type=\"tutuca/spec\">\n" +
  "state Page { rows: Array[Row], sel: Row }\n" +
  "state Row { title: String }\n" +
  "</script>\n" +
  "<template id=\"Page\">" +
  page_view +
  "</template>" +
  row_views
}

///|
test "a read inside a loop over CHILD components is checked against that child" {
  // `Array[Row]` names a sibling state, so the element type is the Row
  // component — a thing one StateDef could never answer.
  let msg = gen_err(
    page_and_row(
      "<ul><li @each=\".rows\"><x text=\".titel\"></x></li></ul>", "<template id=\"Row\"><span @text=\".title\"></span></template>",
    ),
    "Page",
  )
  assert_true(msg.contains("`.titel` is not a field of the Row state"))
  assert_true(msg.contains("did you mean `.title`?"))
  // `@value.member` names the same place and must agree.
  assert_true(
    gen_err(
      page_and_row(
        "<ul><li @each=\".rows\"><x text=\"@value.titel\"></x></li></ul>", "<template id=\"Row\"><span @text=\".title\"></span></template>",
      ),
      "Page",
    ).contains("not a field of the loop item (the Row component)"),
  )
  // The correct spellings both pass.
  assert_eq(
    gen_err(
      page_and_row(
        "<ul><li @each=\".rows\"><x text=\".title\"></x>" +
        "<x text=\"@value.title\"></x></li></ul>",
        "<template id=\"Row\"><span @text=\".title\"></span></template>",
      ),
      "Page",
    ),
    "",
  )
}

///|
test "an `as=` naming a view the child does not have is reported" {
  // At run time the miss falls back to the child's `main` view, so the site
  // renders the wrong one. Only a table spanning both components can see it.
  let hints = gen_hints(
    page_and_row(
      "<x render=\".sel\" as=\"edit\"></x>",
      "<template id=\"Row\"><span @text=\".title\"></span></template>" +
      "<template id=\"Row:edt\"><span></span></template>",
    ),
    "Page",
  )
  assert_eq(hints.length(), 1)
  assert_true(hints[0].contains("unknown-child-view (hint)"))
  assert_true(hints[0].contains("the Row component has no `edit` view"))
  assert_true(hints[0].contains("did you mean `edt`?"))
  // `render-each` reaches the same check through the loop's element type.
  let each_hints = gen_hints(
    page_and_row(
      "<x render-each=\".rows\" as=\"edit\"></x>", "<template id=\"Row\"><span @text=\".title\"></span></template>",
    ),
    "Page",
  )
  assert_eq(each_hints.length(), 1)
  assert_true(each_hints[0].contains("has no `edit` view (it has main)"))
}

///|
test "a view name that does resolve, or cannot be known, is reported by nothing" {
  // The name exists.
  assert_eq(
    gen_hints(
      page_and_row(
        "<x render=\".sel\" as=\"edit\"></x>",
        "<template id=\"Row\"><span @text=\".title\"></span></template>" +
        "<template id=\"Row:edit\"><input></template>",
      ),
      "Page",
    ).length(),
    0,
  )
  // The name is chosen at run time, so there is nothing to check.
  assert_eq(
    gen_hints(
      page_and_row(
        "<x render=\".sel\" as=\".pick\"></x>", "<template id=\"Row\"><span @text=\".title\"></span></template>",
      ),
      "Page",
    ).length(),
    0,
  )
  // An untyped `component` slot names no component: unknown is not wrong, in
  // the hints channel as much as in the fatal one.
  assert_eq(
    gen_hints(
      "<script type=\"tutuca/spec\">\nstate Page { sel: Component }\n</script>" +
      "<template id=\"Page\"><x render=\".sel\" as=\"edit\"></x></template>",
      "Page",
    ).length(),
    0,
  )
}
