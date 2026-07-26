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
/// A state block wrapping the given interface body for the `board` component.
fn board(state : String, view : String) -> String {
  "<script type=\"tutuca/state\">\ninterface board {\n" +
  state +
  "\n}\n</script>\n<template>" +
  view +
  "</template>"
}

///|
test "a misspelt root field fails generation and suggests the right name" {
  let msg = gen_err(
    board(
      "record state { label: string, count: s32 }", "<p><x text=\".labelx\"></x></p>",
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
      "record state { label: string }", "<p><x text=\".somethingElse\"></x></p>",
    ),
    "Board",
  )
  assert_true(msg.contains("not a field of the Board state"))
  assert_true(msg.contains("tutuca/state"))
}

///|
test "reads inside an @each are checked against the ELEMENT type" {
  // The hole this whole stage exists to close: view_surface stops collecting
  // field reads under @each, so before now this was not merely unchecked —
  // it was not even looked at.
  let msg = gen_err(
    board(
      "record card { title: string, done: bool }\nrecord state { cards: list<card> }",
      "<ul><li @each=\".cards\"><x text=\".titel\"></x></li></ul>",
    ),
    "Board",
  )
  assert_true(msg.contains("`.titel` is not a field of card"))
  assert_true(msg.contains("did you mean `.title`?"))
}

///|
test "@value.member inside a loop is checked too" {
  let msg = gen_err(
    board(
      "record card { title: string }\nrecord state { cards: list<card> }", "<ul><li @each=\".cards\"><x text=\"@value.titel\"></x></li></ul>",
    ),
    "Board",
  )
  assert_true(msg.contains("not a field of the loop item (card)"))
  assert_true(msg.contains("did you mean `.title`?"))
}

///|
test "a correct loop body generates cleanly" {
  assert_eq(
    gen_err(
      board(
        "record card { title: string, done: bool }\nrecord state { cards: list<card> }",
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
    board("record state { count: s32 }", "<ul><li @each=\".count\">x</li></ul>"),
    "Board",
  )
  assert_true(msg.contains("`@each` needs a collection"))
  assert_true(msg.contains("`.count` is s32"))
}

///|
test "@each over a set, a list or an ordered map is fine" {
  for
    expr in [
      ("record state { tags: text-set }", ".tags"),
      ("record state { xs: list<s32> }", ".xs"),
      ("record state { m: value-omap }", ".m"),
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
      "record state { label: string }", "<div><x render=\".label\"></x></div>",
    ),
    "Board",
  )
  assert_true(msg.contains("`<x render>` needs a component"))
  assert_true(msg.contains("`.label` is string"))
}

///|
test "<x render> on a declared child slot is fine" {
  let html = "<script type=\"tutuca/state\">\n" +
    "interface card { record state { title: string } }\n" +
    "interface board { record state { lead: card } }\n" +
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
        "record state { detail: any, slot: component, rows: values }",
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
  let html = "<script type=\"tutuca/state\">\n" +
    "interface counter { record state { label: string, count: s32, history: list<s32> } }\n" +
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
      "record inner { deep: string }\n" +
      "record outer { inner: inner }\n" +
      "record state { o: outer }",
      "<p><x text=\".o\"></x><span @each=\".o\">x</span></p>",
    ),
    "Board",
  )
  // `.o` is a record, which is not iterable.
  assert_true(msg.contains("`@each` needs a collection"))
  assert_true(msg.contains("outer"))
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
        "record state { items: values, view: string, q: string }",
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
      "record state { items: values, view: string, q: string }", "<div @push-view=\".view\"><p><x text=\".qq\"></x></p></div>",
    ),
    "Board",
  )
  assert_true(msg.contains("`.qq` is not a field of the Board state"))
}
