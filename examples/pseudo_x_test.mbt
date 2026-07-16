///|
test "pseudo-x: <tr @x render-each> renders row components inside a real table" {
  let h = @harness.mount_example(pseudo_x_module(), "Table with row components")
  // the rows survived the parser and rendered as <tr> children of <tbody>
  inspect(h.find_all("tbody tr").length(), content="0") // no descendant combinator
  inspect(h.find_all("tr").length(), content="4") // 1 header + 3 data rows
  debug_inspect(
    h.texts(".name"),
    content=(
      #|["Apple", "Bread", "Cheese"]
    ),
  )
  debug_inspect(
    h.texts(".qty"),
    content=(
      #|["3", "1", "2"]
    ),
  )
  debug_inspect(
    h.texts(".price"),
    content=(
      #|["1.5", "2.25", "4"]
    ),
  )
}

///|
test "pseudo-x: <option @x render-each> renders option components inside a select" {
  let h = @harness.mount_example(
    pseudo_x_module(),
    "Select with option components",
  )
  inspect(h.find_all("option").length(), content="3")
  debug_inspect(
    h.texts("option"),
    content=(
      #|["Alpha", "Beta", "Gamma"]
    ),
  )
  inspect(h.value_of("option", nth=1), content="b")
  // the select's :value binds the current option
  inspect(h.value_of("select"), content="b")
}

///|
test "pseudo-x: both tables and selects compose under one parent" {
  let h = @harness.mount_example(pseudo_x_module(), "Default")
  inspect(h.find_all("tr").length(), content="4")
  inspect(h.find_all("option").length(), content="3")
  // picking a different option updates the select's bound value
  h.fire("select", @render.DomEvent::new(name="input", value=Str("c")))
  inspect(h.value_of("select"), content="c")
}
