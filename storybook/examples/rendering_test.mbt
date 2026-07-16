///|
test "push-view: one field flips EVERY nested Entry to its edit view" {
  let h = @harness.mount_example(push_view_module(), "Read Only")
  // main view: read-only cards, and no Entry edit inputs anywhere
  inspect(h.text(".toggle-btn"), content="Set Edit Mode")
  inspect(h.find_all(".card-title").length(), content="14")
  inspect(h.find_all("input.title").length(), content="0")
  h.click(".toggle-btn")
  // edit view: every Entry now renders its `edit` view — two inputs each
  inspect(h.text(".toggle-btn"), content="Set Read Only")
  inspect(h.find_all(".card-title").length(), content="0")
  inspect(h.find_all("input.title").length(), content="14")
}

///|
test "push-view: @when filters render-each by calling a method ON THE ITEM" {
  let h = @harness.mount_example(push_view_module(), "Read Only")
  h.type_into("input", "Emperor")
  inspect(h.find_all(".card-title").length(), content="1")
  inspect(h.text(".card-title"), content="those belonging to the Emperor")
}

///|
test "push-view: the example that starts in edit mode" {
  let h = @harness.mount_example(push_view_module(), "Edit Mode")
  inspect(h.find_all("input.title").length(), content="14")
  // each rendered Entry is a live component: editing one updates only that one
  h.type_into("input.title", "renamed", nth=2)
  inspect(h.value_of("input.title", nth=2), content="renamed")
  inspect(h.value_of("input.title", nth=1), content="embalmed ones")
}

///|
test "seq-item-access: .byIndex[.currentIndex] and .byKey[.currentKey]" {
  let h = @harness.mount_example(seq_item_access_module(), "Default")
  // two components render: byIndex[0] and byKey["key-0"]
  debug_inspect(
    h.texts(".card-title"),
    content=(
      #|["those belonging to the Emperor", "those belonging to the Emperor"]
    ),
  )
  // @each over a Map: one <option> per key; @value.title is a bind-member read
  inspect(h.find_all("option").length(), content="14")
  inspect(h.text("option"), content="those belonging to the Emperor")
  inspect(h.value_of("option"), content="key-0")
}

///|
test "seq-item-access: moving the range re-renders the item at that index" {
  let h = @harness.mount_example(seq_item_access_module(), "Default")
  // @on.input="$setCurrentIndex valueAsInt" — the event's value, coerced to Int
  h.fire("input", @render.DomEvent::new(name="input", value=Str("3")))
  debug_inspect(
    h.texts(".card-title"),
    content=(
      #|["suckling pigs", "those belonging to the Emperor"]
    ),
  )
}

///|
test "seq-item-access: picking a key re-renders the keyed item" {
  let h = @harness.mount_example(seq_item_access_module(), "Default")
  h.fire("select", @render.DomEvent::new(name="input", value=Str("key-4")))
  debug_inspect(
    h.texts(".card-title"),
    content=(
      #|["those belonging to the Emperor", "mermaids (or sirens)"]
    ),
  )
}

///|
test "pagination: @loop-with slices the page, keeping ORIGINAL keys" {
  let h = @harness.mount_example(pagination_module(), "First Page")
  inspect(h.text(".label"), content="Page 1 of 3")
  inspect(h.find_all("li").length(), content="5")
  debug_inspect(
    h.texts(".badge"),
    content=(
      #|["0", "1", "2", "3", "4"]
    ),
  )
  h.click(".next")
  inspect(h.text(".label"), content="Page 2 of 3")
  // page 2's badges are the items' ORIGINAL indices, not 0..4 again
  debug_inspect(
    h.texts(".badge"),
    content=(
      #|["5", "6", "7", "8", "9"]
    ),
  )
  inspect(h.text("li"), content="5 fabled ones")
}

///|
test "pagination: the last page is short, and the buttons clamp" {
  let h = @harness.mount_example(pagination_module(), "Second Page")
  h.click(".next")
  inspect(h.text(".label"), content="Page 3 of 3")
  inspect(h.find_all("li").length(), content="4") // 14 items = 5 + 5 + 4
  debug_inspect(
    h.texts(".badge"),
    content=(
      #|["10", "11", "12", "13"]
    ),
  )
  h.click(".next") // clamped: already on the last page
  inspect(h.text(".label"), content="Page 3 of 3")
  h.click(".prev")
  h.click(".prev")
  h.click(".prev") // clamped at 0
  inspect(h.text(".label"), content="Page 1 of 3")
}

///|
test "todo: add and remove child components" {
  let h = @harness.mount(todo_module(), "Items")
  inspect(h.find_all(".row").length(), content="0")
  h.click(".add") // the handler CAPTURES the Item component and makes one
  h.click(".add")
  inspect(h.find_all(".row").length(), content="2")
  inspect(h.value_of("input.input"), content="do the thing")
  // each row is its own component instance with its own two-way-bound fields
  h.type_into("input.input", "buy milk", nth=1)
  inspect(h.value_of("input.input", nth=1), content="buy milk")
  inspect(h.value_of("input.input", nth=0), content="do the thing")
  // $removeInItemsAt @key — a generated mutator, given the loop's key
  h.click(".rm", nth=0)
  inspect(h.find_all(".row").length(), content="1")
  inspect(h.value_of("input.input"), content="buy milk")
}

///|
test "todo: the seeded example renders one row per item" {
  let h = @harness.mount_example(todo_module(), "Some Items")
  inspect(h.find_all(".row").length(), content="3")
  inspect(h.checked_of("input.checkbox", nth=0), content="false")
  inspect(h.checked_of("input.checkbox", nth=1), content="true")
}

///|
test "todo: :disabled tracks the checkbox on the SAME child" {
  let h = @harness.mount(todo_module(), "Items")
  h.click(".add")
  inspect(
    h.prop("input.input", "disabled") is Some(Bool(true)),
    content="false",
  )
  h.check("input.checkbox", true)
  inspect(h.checked_of("input.checkbox"), content="true")
  inspect(h.prop("input.input", "disabled") is Some(Bool(true)), content="true")
}
