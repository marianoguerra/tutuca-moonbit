// The nested-types example driven through the DOM. The codec that carries
// these shapes to and from the render layer is checked in
// nested_state_wbtest.mbt, which can see the private state type.

///|
test "nested state: the view renders the nested fields" {
  let h = @harness.mount(nested_state_module(), "NestedState")
  inspect(h.text(".card-title"), content="Write the codec")
  // the `list<label>` of records, iterated
  debug_inspect(
    h.texts(".btn-xs"),
    content=(
      #|["schema", "codec"]
    ),
  )
}

///|
/// Every write goes state -> fields -> state through the generated codec, so
/// an interaction that changes ONE field is also a round trip for the record
/// list, the enum, the variant, the option and the tuple beside it. If any of
/// those decoded wrong the write would be rejected as a shape mismatch and the
/// list would come back empty.
test "nested state: a write round-trips the whole nested state" {
  let h = @harness.mount(nested_state_module(), "NestedState")
  h.click(".btn-primary") // bumpPriority: Low -> High
  debug_inspect(
    h.texts(".btn-xs"),
    content=(
      #|["schema", "codec"]
    ),
  )
  h.click(".btn-xs") // toggleLabel 0
  debug_inspect(
    h.texts(".btn-xs"),
    content=(
      #|["schema", "codec"]
    ),
  )
}
