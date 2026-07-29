// The generated codec for the named and structural schema types.
//
// It used to be checked against the JSON bridge it replaced: the codec was a
// second encoder for a shape `derive(ToJson)` already knew how to write, and
// the two agreeing was what made replacing one with the other safe. The bridge
// is gone now and the state struct derives nothing, so there is no second
// encoder to agree with — the codec IS the definition of what a view reads.
//
// What is left is the part that still says something: the shapes it produces,
// pinned, over a state that populates every shape the schema language has — a
// record, an enum, a variant with and without a payload, a set and an unset
// option, and a tuple.

///|
/// A state with every schema shape populated, and `note` set.
fn ns_full() -> NestedStateState {
  {
    title: "t",
    labels: [{ text: "a", done: true }, { text: "b", done: false }],
    priority: High,
    due: OnDay(3),
    note: Some("n"),
    size: (2, 5),
  }
}

///|
/// The same, in its zero-ish shape: the payload-free variant case, and `note`
/// unset — the one field whose encoding is its ABSENCE.
fn ns_empty() -> NestedStateState {
  {
    title: "",
    labels: [],
    priority: Low,
    due: Unscheduled,
    note: None,
    size: (0, 0),
  }
}

///|
/// The shapes, pinned — so a change to the codec is legible as a change in the
/// data views read.
test "nested state: the encoded shapes" {
  let m = @component.Fields::encode(ns_full())
  @debug.assert_eq(m.get("priority"), Some(Str("High")))
  @debug.assert_eq(m.get("due"), Some(List([Str("OnDay"), Num(3)])))
  @debug.assert_eq(m.get("size"), Some(List([Num(2), Num(5)])))
  @debug.assert_eq(m.get("note"), Some(Str("n")))
  @debug.assert_eq(
    m.get("labels"),
    Some(
      List([
        Map({ "text": Str("a"), "done": Bool(true) }),
        Map({ "text": Str("b"), "done": Bool(false) }),
      ]),
    ),
  )
  let e = @component.Fields::encode(ns_empty())
  // The payload-free variant case is a bare name, not a one-element list.
  @debug.assert_eq(e.get("due"), Some(Str("Unscheduled")))
  // `option` NONE is the absence of the key — the one shape whose encoding is
  // not a value at all.
  assert_true(e.get("note") is None)
}

///|
test "nested state: decode is the inverse of encode" {
  for s in [ns_full(), ns_empty()] {
    let round : NestedStateState? = @component.Fields::decode(
      @component.Fields::encode(s),
    )
    guard round is Some(back) else { fail("decode rejected its own encoding") }
    // The state struct derives no Eq, so the round trip is compared through
    // the encoding — which is the representation that actually has to survive.
    @debug.assert_eq(
      (Map(@component.Fields::encode(back)) : @tutuca.Value),
      Map(@component.Fields::encode(s)),
    )
  }
}

///|
/// Decode all the way back to the TYPED values, not just to something that
/// re-encodes the same. A record whose fields swapped places, or a variant
/// that lost its payload, would survive the encode-comparison above and fail
/// here.
test "nested state: decode rebuilds the typed values" {
  let round : NestedStateState? = @component.Fields::decode(
    @component.Fields::encode(ns_full()),
  )
  guard round is Some(s) else { fail("decode rejected its own encoding") }
  @debug.assert_eq(s.labels, [
    { text: "a", done: true },
    { text: "b", done: false },
  ])
  @debug.assert_eq(s.priority, High)
  @debug.assert_eq(s.due, OnDay(3))
  @debug.assert_eq(s.note, Some("n"))
  @debug.assert_eq(s.size, (2, 5))
  let empty : NestedStateState? = @component.Fields::decode(
    @component.Fields::encode(ns_empty()),
  )
  guard empty is Some(e) else { fail("decode rejected the zero-ish encoding") }
  @debug.assert_eq(e.due, Unscheduled)
  @debug.assert_eq(e.note, None)
}

///|
test "nested state: decode rejects a value of the wrong shape" {
  // a bad enum case, a variant tag nothing declares, and a short tuple
  let bad : Array[(String, @tutuca.Value)] = [
    ("priority", Str("Sideways")),
    ("due", List([Str("OnDay")])),
    ("size", List([Num(1)])),
    ("labels", List([Str("not a record")])),
  ]
  for entry in bad {
    let fields = @component.Fields::encode(ns_full())
    fields[entry.0] = entry.1
    let bad : NestedStateState? = @component.Fields::decode(fields)
    assert_true(bad is None)
  }
}
