///|
fn ns_toggle_label(
  labels : Array[NestedStateLabel],
  key : @tutuca.Value,
) -> Array[NestedStateLabel] {
  guard key is Num(n) else { return labels }
  let i = n.to_int()
  guard i >= 0 && i < labels.length() else { return labels }
  let out = labels.copy()
  out[i] = { text: out[i].text, done: !out[i].done, }
  out
}

///|
fn nested_state_comp() -> @component.Component {
  nested_state_component(
    initial={
      ..NestedStateState::zero(),
      title: "Write the codec",
      labels: [{ text: "schema", done: true, }, { text: "codec", done: false, }],
      due: OnDay(3),
      size: (2, 5),
    },
    update=(s, msg, _ctx) => {
      match NestedStateMsg::from_dispatch(msg) {
        // The enum is exhaustive, so adding a `priority` case to the schema
        // breaks this match until it is answered.
        Some(BumpPriority) =>
          Next({
            ..s,
            priority: match s.priority {
              Low => High
              High => Low
            },
          })
        Some(ToggleLabel(key)) =>
          Next({ ..s, labels: ns_toggle_label(s.labels, key), })
        Some(Unknown(_, _)) | None => Unhandled
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
