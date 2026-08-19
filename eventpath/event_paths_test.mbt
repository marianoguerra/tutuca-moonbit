// The object-step allowlist.
//
// Two kinds of test, and the plan asks for both by name. One asserts the EXACT
// list, so growing it is a deliberate edit to an assertion rather than a line
// nobody reviews. The other walks known escape paths and asserts each is
// refused — because the first test would still pass if the walk had a bug, and
// a list nothing consults is a list that does nothing.

///|
test "the allowlist is exactly these six steps" {
  // Sorted, and asserted whole. A seventh entry fails this test, in a diff
  // that says which one — which is the only protection a list that cannot be
  // generated can have.
  assert_eq(@eventpath.event_object_steps, [
    "currentTarget", "dataTransfer", "dataset", "detail", "relatedTarget", "target",
  ])
  // And the two below which traversal stops being checked. Both are AUTHOR
  // data — an object the application built, and a map of attributes the author
  // wrote — so there is nothing left to escalate into.
  assert_eq(@eventpath.event_data_terminals, ["dataset", "detail"])
}

///|
test "a scalar on the event traverses nothing" {
  assert_eq(@eventpath.check_event_path(["deltaY"]), PathOk)
  assert_eq(@eventpath.check_event_path(["pointerId"]), PathOk)
  assert_eq(@eventpath.check_event_path(["clientX"]), PathOk)
  // `e.target` alone is allowed HERE and still produces `Null`: an `Element` is
  // not representable, which is rule 1's answer rather than this list's. The
  // two rules are separate on purpose.
  assert_eq(@eventpath.check_event_path(["target"]), PathOk)
}

///|
test "the paths a view legitimately writes are allowed" {
  assert_eq(@eventpath.check_event_path(["target", "value"]), PathOk)
  assert_eq(@eventpath.check_event_path(["target", "checked"]), PathOk)
  assert_eq(@eventpath.check_event_path(["target", "id"]), PathOk)
  assert_eq(@eventpath.check_event_path(["currentTarget", "value"]), PathOk)
  assert_eq(@eventpath.check_event_path(["relatedTarget", "id"]), PathOk)
  assert_eq(@eventpath.check_event_path(["dataTransfer", "types"]), PathOk)
}

///|
test "depth past author data is free" {
  // `dataset` and `detail` are where the boundary stops being a boundary,
  // which is what keeps the language open: these work with no release.
  assert_eq(@eventpath.check_event_path(["target", "dataset", "rowId"]), PathOk)
  assert_eq(@eventpath.check_event_path(["detail", "unicode"]), PathOk)
  assert_eq(@eventpath.check_event_path(["detail", "a", "b", "c"]), PathOk)
  assert_eq(
    @eventpath.check_event_path(["target", "dataset", "a", "b", "c"]),
    PathOk,
  )
}

// ---------------------------------------------------------------------------
// The escape paths. Each of these is a real way out of the event, and each is
// refused at the FIRST step that leaves — which is the whole reason the check
// is per-step rather than per-root.

///|
test "a permitted root is not a permitted path" {
  // THE case the design is written around. `target` is permitted, every step
  // after it is an ordinary property read, and `length` is a number — so it
  // converts cleanly, and a view template has just read the window. Rule 1
  // does not stop it, because the leaf IS representable.
  assert_eq(
    @eventpath.check_event_path([
      "target", "ownerDocument", "defaultView", "localStorage", "length",
    ]),
    BadStep(step="ownerDocument", index=1),
  )
}

///|
test "walking out of the event into the page is refused" {
  // Up the tree.
  assert_eq(
    @eventpath.check_event_path(["target", "parentElement", "id"]),
    BadStep(step="parentElement", index=1),
  )
  assert_eq(
    @eventpath.check_event_path(["target", "parentNode", "nodeName"]),
    BadStep(step="parentNode", index=1),
  )
  // Down it.
  assert_eq(
    @eventpath.check_event_path(["target", "children", "length"]),
    BadStep(step="children", index=1),
  )
  // Sideways, through the form the element belongs to. `e.target.form.action`
  // is as much a read of the host as the `localStorage` line above.
  assert_eq(
    @eventpath.check_event_path(["target", "form", "action"]),
    BadStep(step="form", index=1),
  )
  // Straight at the window, from the root.
  assert_eq(
    @eventpath.check_event_path(["view", "location", "href"]),
    BadStep(step="view", index=0),
  )
  assert_eq(
    @eventpath.check_event_path(["srcElement", "value"]),
    BadStep(step="srcElement", index=0),
  )
}

///|
test "an author-data terminal does not retroactively free the steps above it" {
  // The free-depth rule applies AFTER a terminal is reached, and a path that
  // never reaches one legitimately gets no benefit from naming one later.
  assert_eq(
    @eventpath.check_event_path([
      "target", "ownerDocument", "body", "dataset", "x",
    ]),
    BadStep(step="ownerDocument", index=1),
  )
}

///|
test "the empty path traverses nothing" {
  assert_eq(@eventpath.check_event_path([]), PathOk)
}
