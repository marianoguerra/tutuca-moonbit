// Interaction tests for the last batch of ported examples:
// custom-collection, dynamic-selected-edit, file-picker,
// web-component-custom-event and composability (lint-errors has its own
// fixture test in lint_errors_test.mbt).

///|
test "custom-collection: @each iterates the keyed list in insertion order" {
  let h = @harness.mount_example(custom_collection_module(), "Playlist")
  debug_inspect(
    h.texts(".song"),
    content=(
      #|["Intro", "Middle Eight", "Outro"]
    ),
  )
}

///|
test "custom-collection: remove resolves @key through the walker" {
  let h = @harness.mount_example(custom_collection_module(), "Playlist")
  // the middle button's @key is "middle" — removal is by key, not index
  h.click(".rm", nth=1)
  debug_inspect(
    h.texts(".song"),
    content=(
      #|["Intro", "Outro"]
    ),
  )
  h.click(".rm", nth=1)
  debug_inspect(
    h.texts(".song"),
    content=(
      #|["Intro"]
    ),
  )
}

///|
test "dynamic-selected-edit: both dynamics resolve and lists mirror" {
  let h = @harness.mount_example(
    dynamic_selected_edit_module(),
    "First selected",
  )
  inspect(h.text(".selected-key"), content="a")
  // owner iterates *items (its own provide) and the child Editor iterates
  // the same sequence through its lookup: 3 entries each, document order
  debug_inspect(
    h.texts(".entry"),
    content=(
      #|["alpha", "beta", "gamma", "alpha", "beta", "gamma"]
    ),
  )
  // the edit view shows the *selected seq-access target
  inspect(h.value_of(".edit-name"), content="alpha")
}

///|
test "dynamic-selected-edit: select changes the edit target" {
  let h = @harness.mount_example(
    dynamic_selected_edit_module(),
    "First selected",
  )
  h.click(".select", nth=2)
  inspect(h.text(".selected-key"), content="c")
  inspect(h.value_of(".edit-name"), content="gamma")
}

///|
test "dynamic-selected-edit: edits in the child teleport to the owner" {
  let h = @harness.mount_example(
    dynamic_selected_edit_module(),
    "Second selected",
  )
  inspect(h.value_of(".edit-name"), content="beta")
  // the edited Entry physically lives in Root.items — the owner's list AND
  // the child's list update in lock-step
  h.type_into(".edit-name", "BETA!")
  debug_inspect(
    h.texts(".entry"),
    content=(
      #|["alpha", "BETA!", "gamma", "alpha", "BETA!", "gamma"]
    ),
  )
}

///|
test "file-picker: empty state, then metadata summary" {
  let h = @harness.mount_example(file_picker_module(), "Empty")
  inspect(h.find_all(".empty").length(), content="1")
  // picking a file delivers its metadata Map as `value`
  h.fire(
    "input",
    @render.DomEvent::new(
      name="change",
      value=Map({
        "name": Str("photo.png"),
        "size": Num(2048),
        "type": Str("image/png"),
        "lastModified": Num(1700000000000),
      }),
    ),
  )
  inspect(h.text(".fname"), content="photo.png")
  inspect(h.text(".fsize"), content="2 KB")
  inspect(h.text(".ftype"), content="image/png")
  inspect(h.text(".fmodified"), content="2023-11-14 22:13 UTC")
  // a null value (no file) clears the selection
  h.fire("input", @render.DomEvent::new(name="change", value=Null))
  inspect(h.find_all(".empty").length(), content="1")
}

///|
test "file-picker: the pre-populated example formats its labels" {
  let h = @harness.mount_example(file_picker_module(), "With a file")
  inspect(h.text(".fname"), content="report.pdf")
  inspect(h.text(".fsize"), content="239.92 KB")
  inspect(h.text(".ftype"), content="application/pdf")
}

///|
test "web-component: the custom event's detail selects the emoji" {
  let h = @harness.mount_example(web_component_module(), "Default")
  inspect(h.find_all(".hint").length(), content="1")
  // emoji-picker-element dispatches CustomEvent("emoji-click", {detail});
  // the glue maps detail -> value as a Map
  h.fire(
    "section",
    @render.DomEvent::new(
      name="emoji-click",
      value=Map({ "unicode": Str("😀") }),
    ),
  )
  inspect(h.text(".current"), content="😀")
  inspect(h.find_all(".hint").length(), content="0")
}

///|
test "web-component: toggle shows and hides the picker element" {
  let h = @harness.mount_example(web_component_module(), "Default")
  inspect(h.find_all("emoji-picker").length(), content="0")
  h.click(".toggle")
  inspect(h.find_all("emoji-picker").length(), content="1")
  h.click(".toggle")
  inspect(h.find_all("emoji-picker").length(), content="0")
}

///|
test "composability: tabs switch which sub-app is visible" {
  let h = @harness.mount_example(composability_module(), "Default (To-Do tab)")
  // all sub-apps are mounted; only the active pane is shown
  inspect(h.find_all(".pane-todo").length(), content="1")
  inspect(h.find_all(".pane-json").length(), content="0")
  h.click("#tab-json")
  inspect(h.find_all(".pane-todo").length(), content="0")
  inspect(h.find_all(".pane-json").length(), content="1")
  h.click("#tab-tree")
  inspect(h.find_all(".pane-tree").length(), content="1")
}

///|
test "composability: the JSON-tab preset starts on the JSON editor" {
  let h = @harness.mount_example(composability_module(), "JSON Editor Selected")
  inspect(h.find_all(".pane-json").length(), content="1")
  inspect(h.find_all(".pane-todo").length(), content="0")
}

///|
test "composability: init forwards to the personal-site sub-app" {
  let h = @harness.mount_example(composability_module(), "Default (To-Do tab)")
  h.send_at_root("init")
  h.click("#tab-personal-site")
  // the personal-site app loaded its data through its request handler
  inspect(h.find_all(".pane-personal-site").length(), content="1")
}
