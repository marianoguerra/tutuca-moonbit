// The generated DOM property table, and the two questions it answers.
//
// What is asserted here is deliberately narrow: the table is GENERATED, so a
// test that restated it would be the hand transcription the generator exists to
// avoid. What can be asserted without restating it is that the LOOKUP works —
// that inheritance is walked, that the three scalar kinds come out as
// themselves, and that an interface the table does not carry says so.

///|
test "value on an input types as text, as it does today" {
  // The one property the whole `e.value` surface turns on. `HTMLInputElement`
  // spells it `[LegacyNullToEmptyString] DOMString`, which says what happens
  // when JavaScript ASSIGNS null to it — an `e.` path only ever reads, so the
  // extended attribute is stripped and the type is text.
  assert_eq(@eventpath.dom_prop_ty("HTMLInputElement", "value"), Some(PText))
  assert_eq(@eventpath.dom_prop_ty("HTMLInputElement", "checked"), Some(PBool))
  assert_eq(@eventpath.dom_prop_ty("HTMLInputElement", "type"), Some(PText))
  // A number, and a different interface's `value` that is one.
  assert_eq(@eventpath.dom_prop_ty("HTMLProgressElement", "value"), Some(PNum))
}

///|
test "a property declared on an ancestor is found by walking inherits" {
  // The table stores what each interface DECLARES. `id` is `Element`'s, and a
  // lookup on `HTMLInputElement` has to climb four interfaces to find it.
  assert_eq(@eventpath.dom_prop_ty("HTMLInputElement", "id"), Some(PText))
  assert_eq(@eventpath.dom_prop_ty("Element", "id"), Some(PText))
  // ...and an event's own chain climbs too: `detail` is `UIEvent`'s.
  assert_eq(@eventpath.dom_prop_ty("MouseEvent", "detail"), Some(PNum))
  assert_eq(@eventpath.dom_prop_ty("KeyboardEvent", "detail"), Some(PNum))
  // `type` is `Event`'s, three interfaces above a pointer event.
  assert_eq(@eventpath.dom_prop_ty("PointerEvent", "type"), Some(PText))
}

///|
test "the scalar kinds an event carries come out as themselves" {
  assert_eq(@eventpath.dom_prop_ty("KeyboardEvent", "key"), Some(PText))
  assert_eq(@eventpath.dom_prop_ty("KeyboardEvent", "ctrlKey"), Some(PBool))
  assert_eq(@eventpath.dom_prop_ty("MouseEvent", "clientX"), Some(PNum))
  assert_eq(@eventpath.dom_prop_ty("WheelEvent", "deltaY"), Some(PNum))
  assert_eq(@eventpath.dom_prop_ty("PointerEvent", "pointerId"), Some(PNum))
}

///|
test "an object-valued property carries the name of what it is" {
  // The name is what lets layer 2 ask whether the STEP may be traversed — the
  // design's rule that every step is allowlisted, not just the root.
  assert_eq(
    @eventpath.dom_prop_ty("Event", "target"),
    Some(PObj("EventTarget")),
  )
  assert_eq(
    @eventpath.dom_prop_ty("DragEvent", "dataTransfer"),
    Some(PObj("DataTransfer")),
  )
  assert_eq(
    @eventpath.dom_prop_ty("HTMLElement", "dataset"),
    Some(PObj("DOMStringMap")),
  )
}

///|
test "a property no interface in the chain declares is not there" {
  assert_eq(@eventpath.dom_prop_ty("HTMLInputElement", "valeu"), None)
  assert_eq(@eventpath.dom_prop_ty("Event", "value"), None)
  // THE one that matters: a DOM `Event` has no `value` property at all, which
  // is why layer 1's computed accessors have to shadow layer 2 rather than
  // fall through to it (`totuka-v2.md` section 7).
  assert_eq(@eventpath.dom_prop_ty("MouseEvent", "value"), None)
}

///|
test "Window and Document are not in the table, and that is the scope" {
  // Not an omission. No allowlisted object step lands on either, so a path
  // through one has no typed continuation — the second reason
  // `e.target.ownerDocument.defaultView.localStorage.length` is refused, after
  // the allowlist's first.
  assert_false(@eventpath.dom_interface_known("Window"))
  assert_false(@eventpath.dom_interface_known("Document"))
  assert_true(@eventpath.dom_interface_known("Event"))
  assert_true(@eventpath.dom_interface_known("HTMLInputElement"))
  assert_true(@eventpath.dom_interface_known("DataTransfer"))
  // ...and a lookup through a name it does not carry answers None rather than
  // guessing.
  assert_eq(@eventpath.dom_prop_ty("Window", "localStorage"), None)
}

///|
test "the property list of an interface is its own plus its ancestors'" {
  let props = @eventpath.dom_props_of("KeyboardEvent")
  // Its own...
  assert_true(props.contains("key"))
  assert_true(props.contains("altKey"))
  // ...UIEvent's...
  assert_true(props.contains("detail"))
  // ...and Event's.
  assert_true(props.contains("type"))
  assert_true(props.contains("bubbles"))
  // Sorted, so a "did you mean" search reads the same way twice.
  let sorted = props.copy()
  sorted.sort()
  assert_eq(props, sorted)
  assert_eq(@eventpath.dom_props_of("NoSuchInterface").length(), 0)
}
