// Addresses: the four questions a recording asks of one.

///|
fn p(src : String) -> @trace.Place {
  @trace.parse_place(src) catch {
    e => {
      println(e.message())
      @trace.Place([])
    }
  }
}

///|
test "a dotted place reads the spelling a scene already uses" {
  assert_eq(p(".rows[0].label").label(), "rows[0].label")
  assert_eq(p("rows[0].label").label(), "rows[0].label")
  assert_eq(p(".byId['a'].n").label(), "byId[a].n")
  assert_eq(p(".count").label(), "count")
  assert_eq(p("").depth(), 0)
  assert_eq(p(".").depth(), 0)
}

///|
/// Quoting decides, not the digits. A map really can be keyed by "1", and
/// guessing from the content would make that address unwritable.
test "a quoted key is a name even when it looks like a number" {
  assert_true(p(".m['1']") is Place([{ field: "m", key: Some(KStr("1")), }]))
  assert_true(p(".m[1]") is Place([{ field: "m", key: Some(KInt(1)), }]))
}

///|
fn why(src : String) -> String {
  try {
    @trace.parse_place(src) |> ignore
    "no error"
  } catch {
    e => e.message()
  }
}

///|
test "a place that does not read as one says why" {
  inspect(why(".rows[0"), content="bad place: unclosed `[` in `.rows[0`")
  inspect(why(".rows."), content="bad place: trailing `.` in `.rows.`")
  inspect(
    why(".rows[a]"),
    content="bad place: `a` in `.rows[a]` is neither a number nor a quoted key",
  )
}

///|
/// Step by step and not a text comparison on the labels, which would be the
/// obvious shortcut and is wrong: `rows` is a prefix of `rowsExtra` as text and
/// of nothing as an address.
test "a prefix is a prefix of steps, not of text" {
  assert_true(p(".rows[1].label").starts_with(p(".rows[1]")))
  assert_true(p(".rows[1]").starts_with(p("")))
  assert_false(p(".rowsExtra[1]").starts_with(p(".rows")))
  assert_false(p(".rows[1]").starts_with(p(".rows[2]")))
  // Equal counts as at-or-below: relocating onto a place keeps the events
  // addressed exactly at it.
  assert_true(p(".rows[1]").starts_with(p(".rows[1]")))
}

///|
test "stripping a prefix is the address seen from there" {
  assert_eq(
    p(".rows[1].label").strip_prefix(p(".rows[1]")).map(x => x.label()),
    Some("label"),
  )
  assert_eq(
    p(".rows[1]").strip_prefix(p(".rows[1]")).map(x => x.label()),
    Some(""),
  )
  assert_eq(p(".other").strip_prefix(p(".rows[1]")), None)
}

///|
/// A round trip through the address encoding `core` owns, which a refusal and
/// an observer record write too.
test "a place round-trips through JSON" {
  for src in [".rows[0].label", ".byId['a'].n", ".count", ""] {
    let place = p(src)
    assert_eq(@trace.Place::from_json(place.to_json()), Some(place))
  }
  inspect(
    p(".rows[0].label").to_json().stringify(),
    content=(
      #|[{"f":"rows","k":0},{"f":"label"}]
    ),
  )
}

///|
/// The two directions are not symmetric and cannot be: `to_keys` flattens seven
/// step variants onto two, and what comes back is the pair that ADDRESSES
/// something. That is enough to dispatch at, which is all a recording needs.
test "a place becomes steps a dispatch can be aimed at" {
  let steps = p(".rows[1].label").to_steps()
  assert_true(steps is [SeqStep(field="rows", key=KInt(1)), FieldStep("label")])
  assert_eq(
    @trace.Place::of_path(p(".rows[1].label").to_path()).label(),
    "rows[1].label",
  )
}
