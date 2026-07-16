///|
test "render-with-scope: @enrich-with publishes derived @-bindings to a subtree" {
  let h = @harness.mount(render_with_scope_module(), "RenderWithScope")
  inspect(h.text(".v-text"), content="Hello")
  inspect(h.text(".v-len"), content="5")
  inspect(h.text(".v-upper"), content="HELLO")
  // the derived values are recomputed on every render — they are not state
  h.type_into("input", "Tutuca")
  inspect(h.text(".v-len"), content="6")
  inspect(h.text(".v-upper"), content="TUTUCA")
}

///|
test "list-filter-enrich: @enrich-with adds a per-item binding" {
  let h = @harness.mount(list_filter_enrich_module(), "ListFilterEnrich", args={
    "items": List([Str("one"), Str("three")]),
  })
  debug_inspect(
    h.texts("li"),
    content=(
      #|["0: one (3 characters)", "1: three (5 characters)"]
    ),
  )
}

///|
test "list-filter-enrich: filter and enrich compose" {
  let h = @harness.mount(list_filter_enrich_module(), "ListFilterEnrich", args={
    "items": List(items()),
  })
  h.type_into("input", "emperor")
  debug_inspect(
    h.texts("li"),
    content=(
      #|["0: those belonging to the Emperor (30 characters)"]
    ),
  )
}

///|
test "list-filter-enrich-with: @loop-with data reaches @when AND @enrich-with" {
  let h = @harness.mount(
    list_filter_enrich_with_module(),
    "ListFilterEnrichWith",
    args={ "items": List([Str("one"), Str("three")]) },
  )
  // total = 3 + 5 = 8, computed once over the WHOLE sequence
  debug_inspect(
    h.texts("li"),
    content=(
      #|["0: one (3 / 8)", "1: three (5 / 8)"]
    ),
  )
}

///|
test "list-filter-enrich-with: totals are computed BEFORE filtering" {
  let h = @harness.mount(
    list_filter_enrich_with_module(),
    "ListFilterEnrichWith",
    args={ "items": List([Str("one"), Str("three")]) },
  )
  h.type_into("input", "three")
  // only one row survives the filter, but the total still counts both items
  debug_inspect(
    h.texts("li"),
    content=(
      #|["1: three (5 / 8)"]
    ),
  )
}
