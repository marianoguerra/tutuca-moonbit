// What makes the patch benches valid: every round trip has to put the DOM back
// the way it found it. If one did not, reusing a mounted app across bench
// iterations would drift — the tenth iteration would be measuring a different
// tree than the first, and the number would mean nothing.
//
// The one deliberate exception is add+remove, which appends a row and drops the
// FIRST one: the list keeps its length and rotates by one. That is checked here
// too, because "rotates by one" is a much stronger property than "changed".

///|
/// A round trip that must be an exact identity on the DOM.
fn assert_round_trip(
  h : @harness.Harness,
  run : (@harness.Harness) -> Int,
) -> Unit raise {
  let before = h.html()
  let renders = h.render_count()
  let after_count = run(h)
  assert_true(after_count > renders) // it re-rendered at all
  assert_eq(h.html(), before)
  // …and again, since the benches run it thousands of times over.
  let _ = run(h)
  assert_eq(h.html(), before)
}

///|
test "noop round trip leaves the DOM identical" {
  assert_round_trip(@benchmarks.mount_todo(10), @benchmarks.patch_noop)
}

///|
test "counter round trip leaves the DOM identical" {
  assert_round_trip(@benchmarks.mount_counter(), @benchmarks.patch_counter)
}

///|
test "toggle round trip leaves the DOM identical" {
  assert_round_trip(@benchmarks.mount_todo(10), @benchmarks.patch_toggle)
}

///|
test "page round trip leaves the DOM identical" {
  assert_round_trip(@benchmarks.mount_people(100), @benchmarks.patch_page)
}

///|
test "move round trip leaves the DOM identical" {
  assert_round_trip(@benchmarks.mount_json(4, 3), @benchmarks.patch_move)
}

///|
test "refilter round trip leaves the DOM identical" {
  assert_round_trip(@benchmarks.mount_people(100), @benchmarks.patch_refilter)
}

///|
test "switch-view round trip leaves the DOM identical" {
  assert_round_trip(@benchmarks.mount_tabs(), @benchmarks.patch_switch_view)
}

///|
test "add+remove keeps the row count and rotates by one" {
  let h = @benchmarks.mount_todo(5)
  let rows = h.find_all(".row").length()
  assert_eq(rows, 5)
  assert_eq(h.value_of(".input", nth=0), "task 0")
  let _ = @benchmarks.patch_add_remove(h)
  // Same length: one appended, the first one dropped. Row 0 is what row 1 was,
  // and the last row is `Item`'s default — the freshly added one.
  assert_eq(h.find_all(".row").length(), rows)
  assert_eq(h.value_of(".input", nth=0), "task 1")
  assert_eq(h.value_of(".input", nth=rows - 1), "do the thing")
}
