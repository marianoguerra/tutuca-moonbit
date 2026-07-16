///|
test "todo-macros: the checkbox/input macros expand with two-way bindings" {
  let h = @harness.mount_example(todo_macros_module(), "Default Item")
  // <x:hbox> wraps <x:checkbox> + <x:input>
  inspect(h.find_all(".hbox").length(), content="1")
  inspect(h.value_of("input.input"), content="do the thing")
  inspect(h.checked_of("input.checkbox"), content="false")
  // :handler="$setText" threaded through ^handler -> @on.input="$setText value"
  h.type_into("input.input", "buy milk")
  inspect(h.value_of("input.input"), content="buy milk")
  h.check("input.checkbox", true)
  inspect(h.checked_of("input.checkbox"), content="true")
}

///|
test "todo-macros: the completed item disables its text input via ^disabled" {
  let h = @harness.mount_example(todo_macros_module(), "Completed Item")
  inspect(h.checked_of("input.checkbox"), content="true")
  inspect(h.prop("input.input", "disabled") is Some(Bool(true)), content="true")
}

///|
test "todo-macros: btn-action's ^handler adds an item, btn-rm's removes one" {
  let h = @harness.mount_example(todo_macros_module(), "Empty List")
  inspect(h.find_all(".entry").length(), content="0")
  // <x:btn-action :handler="onAddItem"> -> @on.click="onAddItem ..."
  h.click(".add")
  h.click(".add")
  inspect(h.find_all(".entry").length(), content="2")
  // <x:btn-rm :handler="$removeInItemsAt" :arg="@key"> -> the loop key threads in
  h.click(".rm", nth=0)
  inspect(h.find_all(".entry").length(), content="1")
}

///|
test "todo-macros: the seeded list renders one row per item" {
  let h = @harness.mount_example(todo_macros_module(), "Some Items")
  inspect(h.find_all(".entry").length(), content="3")
  inspect(h.checked_of("input.checkbox", nth=0), content="false")
  inspect(h.checked_of("input.checkbox", nth=1), content="true")
  inspect(h.checked_of("input.checkbox", nth=2), content="true")
}
