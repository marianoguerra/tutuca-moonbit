// The generated codec for the named and structural schema types, checked
// against the bridge it replaces.
//
// `nested_state_encode` is a second encoder for a shape `derive(ToJson)`
// already knows how to write, so the only thing that makes it safe is that the
// two agree. These tests are that agreement, written over a state that
// populates every shape the schema language has: a record, an enum, a variant
// with and without a payload, a set and an unset option, and a tuple.

///|
/// A state with every schema shape populated, and `note` set.
fn ns_full() -> NestedStateState {
  NestedStateState::{
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
  NestedStateState::{
    title: "",
    labels: [],
    priority: Low,
    due: Unscheduled,
    note: None,
    size: (0, 0),
  }
}

///|
/// The JSON bridge, spelled exactly as `component/instance.mbt`'s
/// `encode_state` spells it: `ToJson` per field, inside the value stash.
fn ns_bridge_encode(s : NestedStateState) -> Map[String, @tutuca.Value] {
  @tutuca.with_value_stash(() => {
    match ToJson::to_json(s) {
      Object(m) => {
        let out : Map[String, @tutuca.Value] = Map([])
        for k, jv in m {
          let v : @tutuca.Value = @json.from_json(jv) catch { _ => Null }
          out[k] = v
        }
        out
      }
      _ => Map([])
    }
  })
}

///|
test "nested state: the direct codec encodes what the JSON bridge encodes" {
  for s in [ns_full(), ns_empty()] {
    let direct : @tutuca.Value = Map(nested_state_encode(s))
    let bridged : @tutuca.Value = Map(ns_bridge_encode(s))
    @debug.assert_eq(direct, bridged)
  }
}

///|
/// The shapes themselves, pinned. The test above proves the two encoders
/// agree; this one says what they agree ON, so a change to either is legible
/// as a change in the data views read rather than as two numbers moving
/// together.
test "nested state: the encoded shapes" {
  let m = nested_state_encode(ns_full())
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
  let e = nested_state_encode(ns_empty())
  // The payload-free variant case is a bare name, not a one-element list.
  @debug.assert_eq(e.get("due"), Some(Str("Unscheduled")))
  // `option` NONE is the absence of the key — the one shape whose encoding is
  // not a value at all.
  assert_true(e.get("note") is None)
}

///|
test "nested state: decode is the inverse of encode" {
  for s in [ns_full(), ns_empty()] {
    guard nested_state_decode(nested_state_encode(s)) is Some(back) else {
      fail("decode rejected its own encoding")
    }
    // The state struct derives no Eq, so the round trip is compared through
    // the encoding — which is the representation that actually has to survive.
    @debug.assert_eq(
      (Map(nested_state_encode(back)) : @tutuca.Value),
      Map(nested_state_encode(s)),
    )
  }
}

///|
/// Decode all the way back to the TYPED values, not just to something that
/// re-encodes the same. A record whose fields swapped places, or a variant
/// that lost its payload, would survive the encode-comparison above and fail
/// here.
test "nested state: decode rebuilds the typed values" {
  guard nested_state_decode(nested_state_encode(ns_full())) is Some(s) else {
    fail("decode rejected its own encoding")
  }
  @debug.assert_eq(s.labels, [
    NestedStateLabel::{ text: "a", done: true },
    NestedStateLabel::{ text: "b", done: false },
  ])
  @debug.assert_eq(s.priority, NestedStatePriority::High)
  @debug.assert_eq(s.due, NestedStateDue::OnDay(3))
  @debug.assert_eq(s.note, Some("n"))
  @debug.assert_eq(s.size, (2, 5))
  guard nested_state_decode(nested_state_encode(ns_empty())) is Some(e) else {
    fail("decode rejected the zero-ish encoding")
  }
  @debug.assert_eq(e.due, NestedStateDue::Unscheduled)
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
    let fields = nested_state_encode(ns_full())
    fields[entry.0] = entry.1
    assert_true(nested_state_decode(fields) is None)
  }
}
