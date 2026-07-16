///|
test "list-iteration: one <li> per item, with @key and @value" {
  let h = @harness.mount(list_iteration_module(), "ListIteration", args={
    "items": List([Str("one"), Str("two"), Str("three")]),
  })
  debug_inspect(
    h.texts("li"),
    content=(
      #|["0: one", "1: two", "2: three"]
    ),
  )
}

///|
test "list-iteration: an empty list renders no rows" {
  let h = @harness.mount(list_iteration_module(), "ListIteration", args={
    "items": List([]),
  })
  inspect(h.find_all("li").length(), content="0")
}

///|
test "list-iteration: the shared sample list" {
  let h = @harness.mount(list_iteration_module(), "ListIteration", args={
    "items": List(items()),
  })
  inspect(h.find_all("li").length(), content="14")
  inspect(h.text("li"), content="0: those belonging to the Emperor")
}

///|
test "render-child: the child renders from its own field, via the parent" {
  let h = @harness.mount(render_child_module(), "Page")
  inspect(h.text("h2"), content="Page header")
  inspect(h.text("strong"), content="tutorial reader")
}

///|
test "entry: the edit view two-way-binds the same fields as main" {
  let h = @harness.mount(entry_module(), "Entry")
  inspect(h.text(".card-title"), content="Entry Title")
}

///|
test "multiple-views: one instance rendered through two views stays in sync" {
  let h = @harness.mount(multiple_views_module(), "MultipleViews")
  // main view shows the read-only card, edit view binds :value
  inspect(h.text(".card-title"), content="Entry Title")
  inspect(h.value_of(".title"), content="Entry Title")
  // typing in the edit view's input updates the value BOTH views render
  h.type_into(".title", "Hello")
  inspect(h.text(".card-title"), content="Hello")
  inspect(h.value_of(".title"), content="Hello")
}
