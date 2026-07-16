///|
test "dynamic-bindings: the consumer reads the producer's list as *entries" {
  let h = @harness.mount_example(dynamic_bindings_module(), "With Entries")
  // Selector has NO items of its own; every <option> comes from the producer's
  // .items through the `entries` dynamic
  inspect(h.find_all("option").length(), content="2")
  debug_inspect(
    h.texts("option"),
    content=(
      #|["Alpha", "Beta"]
    ),
  )
  inspect(h.value_of("option"), content="a")
}

///|
test "dynamic-bindings: adding an item updates the distant consumer" {
  let h = @harness.mount_example(dynamic_bindings_module(), "Default")
  // no items yet: the producer provides an empty list
  inspect(h.find_all("option").length(), content="0")
  h.click(".add")
  h.click(".add")
  debug_inspect(
    h.texts("option"),
    content=(
      #|["Entry #1", "Entry #2"]
    ),
  )
  // editing an entry's label re-renders the option that reads it
  h.type_into("input.lbl", "Renamed", nth=0)
  debug_inspect(
    h.texts("option"),
    content=(
      #|["Renamed", "Entry #2"]
    ),
  )
  // and removing one drops its option
  h.click(".rm", nth=0)
  debug_inspect(
    h.texts("option"),
    content=(
      #|["Entry #2"]
    ),
  )
}

///|
test "dynamic-path: a dynamic var as a RENDER TARGET, across a deep tree" {
  let h = @harness.mount_example(dynamic_path_module(), "Default")
  // Workspace -> Panel -> Toolbar, and the Toolbar renders <x render="*active">
  inspect(h.find_all(".panel").length(), content="1")
  inspect(h.find_all(".toolbar").length(), content="1")
  inspect(h.find_all(".sheet").length(), content="1")
  inspect(h.text(".echo"), content="untitled")
  inspect(h.value_of("input.title"), content="untitled")
}

///|
test "dynamic-path: editing the teleported Sheet mutates Workspace.sheet" {
  let h = @harness.mount_example(dynamic_path_module(), "Default")
  // The Sheet is rendered inside Toolbar but LIVES at Workspace.sheet. The
  // transaction skips the intermediate components and lands on the real owner —
  // the echo at the Workspace level is the proof.
  h.type_into("input.title", "quarterly report")
  inspect(h.value_of("input.title"), content="quarterly report")
  inspect(h.text(".echo"), content="quarterly report")
}
