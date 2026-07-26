// Teaches: the state schema's NAMED and STRUCTURAL types — `record`, `enum`,
// `variant`, `option` and `tuple` — not just the scalars and lists the rest of
// the corpus uses.
//
// Every one of them becomes a real MoonBit type in nested_state_view_gen.mbt
// (`NestedStateLabel`, `NestedStatePriority`, `NestedStateDue`, `String?`,
// `(Int, Int)`), so `update` pattern-matches them directly and a missing case
// is a compile error rather than a null at render time.
//
// It also pins the generated codec. `nested_state_encode`/`_decode` convert
// each of these shapes to and from `@tutuca.Value` field by field, and the
// tests below check the round trip against the `derive(ToJson)` bridge the
// runtime used to fall back to — the two must agree exactly, because that
// agreement is what lets the bridge be deleted.

///|
/// Flip a label's `done` by index, leaving the rest alone.
fn ns_toggle_label(
  labels : Array[NestedStateLabel],
  key : @tutuca.Value,
) -> Array[NestedStateLabel] {
  guard key is Num(n) else { return labels }
  let i = n.to_int()
  guard i >= 0 && i < labels.length() else { return labels }
  let out = labels.copy()
  out[i] = NestedStateLabel::{ text: out[i].text, done: !out[i].done }
  out
}

///|
fn nested_state_comp() -> @component.Component {
  nested_state_component(
    init={
      ..NestedStateState::zero(),
      title: "Write the codec",
      labels: [{ text: "schema", done: true }, { text: "codec", done: false }],
      due: OnDay(3),
      size: (2, 5),
    },
    update=(s, msg, _ctx) => {
      match NestedStateMsg::from_dispatch(msg) {
        // The enum is exhaustive, so adding a `priority` case to the schema
        // breaks this match until it is answered.
        Some(BumpPriority) =>
          Some({
            ..s,
            priority: match s.priority {
              Low => High
              High => Low
            },
          })
        Some(ToggleLabel(key)) =>
          Some({ ..s, labels: ns_toggle_label(s.labels, key) })
        Some(Unknown(_, _)) | None => None
      }
    },
  )
}

///|
pub fn nested_state_module() -> @component.ModuleDef {
  @component.ModuleDef::new(
    name="nested-state",
    components=[nested_state_comp()],
    examples=[
      {
        component: "NestedState",
        title: "Nested state types",
        args: Map([]),
        view: None,
      },
    ],
  )
}
