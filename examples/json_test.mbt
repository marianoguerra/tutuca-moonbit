///|
test "json: the selector's buttons swap it for the chosen value type" {
  let h = @harness.mount_example(json_module(), "Type Selector")
  inspect(h.find_all(".json-selector").length(), content="1")
  // clicking "0" replaces the selector with a JsonNumber
  h.click(".to-number")
  inspect(h.find_all(".json-selector").length(), content="0")
  inspect(h.find_all(".json-number").length(), content="1")
}

///|
test "json: self-replacement works for every type" {
  let cases = [
    (".to-null", ".json-null"),
    (".to-bool", "[data-bool]"),
    (".to-string", ".json-string"),
    (".to-array", ".json-array"),
    (".to-object", ".json-object"),
  ]
  for c in cases {
    let h = @harness.mount_example(json_module(), "Type Selector")
    h.click(c.0)
    inspect(h.find_all(".json-selector").length(), content="0")
    inspect(h.find_all(c.1).length(), content="1")
  }
}

///|
test "json: array grows via the selector, and a picked type edits in place" {
  let h = @harness.mount_example(json_module(), "Empty Array With Selector")
  // starts with one selector inside the array
  inspect(h.find_all(".entry").length(), content="1")
  inspect(h.find_all(".json-selector").length(), content="1")
  // add a second element (another selector)
  h.click(".add")
  inspect(h.find_all(".entry").length(), content="2")
  inspect(h.find_all(".json-selector").length(), content="2")
  // turn the first selector into a string, then edit it
  h.click(".to-string", nth=0)
  inspect(h.find_all(".json-string").length(), content="1")
  h.type_into(".json-string", "hello world")
  inspect(h.value_of(".json-string"), content="hello world")
  // the second is still a selector
  inspect(h.find_all(".json-selector").length(), content="1")
}

///|
test "json: bool ctrl-click starts false, plain click starts true" {
  let plain = @harness.mount_example(json_module(), "Type Selector")
  plain.click(".to-bool")
  inspect(plain.text("[data-bool]"), content="true")
  let ctrl = @harness.mount_example(json_module(), "Type Selector")
  // isCtrl reaches the method as an argument; ctrl -> !true -> false
  ctrl.fire(".to-bool", @render.DomEvent::new(name="click", ctrl_or_cmd=true))
  inspect(ctrl.text("[data-bool]"), content="false")
}

///|
test "json: a bool toggles, a number keeps its raw string" {
  let h = @harness.mount_example(json_module(), "Boolean True")
  inspect(h.text("[data-bool]"), content="true")
  h.click("[data-bool]")
  inspect(h.text("[data-bool]"), content="false")

  let n = @harness.mount_example(json_module(), "Number")
  inspect(n.value_of(".json-number"), content="42")
  // a partial/invalid entry keeps the raw string but not a bad numeric value
  n.type_into(".json-number", "3.")
  inspect(n.value_of(".json-number"), content="3.")
}

///|
test "json: removing an array element drops it" {
  let h = @harness.mount_example(json_module(), "Empty Array With Selector")
  h.click(".add")
  h.click(".add")
  inspect(h.find_all(".entry").length(), content="3")
  h.click(".rm", nth=0)
  inspect(h.find_all(".entry").length(), content="2")
}

///|
test "json: an object builds key/value rows whose value is a selector" {
  let h = @harness.mount_example(json_module(), "Object")
  inspect(h.find_all(".json-kv").length(), content="0")
  h.click(".add")
  inspect(h.find_all(".json-kv").length(), content="1")
  // the value slot is a fresh selector; the key is editable
  inspect(h.find_all(".json-selector").length(), content="1")
  h.type_into(".json-key", "name")
  inspect(h.value_of(".json-key"), content="name")
  // turn the value into a string via the nested selector
  h.click(".to-string")
  inspect(h.find_all(".json-string").length(), content="1")
}

///|
test "json: nested composition — an array inside an array" {
  let h = @harness.mount_example(json_module(), "Empty Array With Selector")
  h.click(".to-array", nth=0) // the seed selector becomes an inner array
  inspect(h.find_all(".json-array").length(), content="2") // outer + inner
  // the inner array has its own + button; adding puts a selector inside it
  h.click(".add", nth=1)
  inspect(h.find_all(".json-selector").length(), content="1")
}
