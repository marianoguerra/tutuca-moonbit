///|
test "attribute-binding: :value / :checked bind state into the inputs" {
  let h = @harness.mount(attribute_binding_module(), "AttributeBinding")
  inspect(h.value_of(".s"), content="hello")
  inspect(h.value_of(".n"), content="42")
  inspect(h.checked_of(".b"), content="true")
  // $'Content is {.str}' — a string template in an attribute
  debug_inspect(
    h.attr(".s", "title"),
    content=(
      #|Some("Content is hello")
    ),
  )
}

///|
test "attribute-binding: typing updates the field, the template, and the echo" {
  let h = @harness.mount(attribute_binding_module(), "AttributeBinding")
  h.type_into(".s", "tutuca")
  inspect(h.text(".o-str"), content="tutuca")
  debug_inspect(
    h.attr(".s", "title"),
    content=(
      #|Some("Content is tutuca")
    ),
  )
}

///|
test "attribute-binding: setRawNumber validates — a bad number is ignored" {
  let h = @harness.mount(attribute_binding_module(), "AttributeBinding")
  h.type_into(".n", "100")
  inspect(h.text(".o-num"), content="100")
  h.type_into(".n", "not a number")
  inspect(h.text(".o-num"), content="100") // unchanged
}

///|
test "attribute-binding: a checkbox input carries `checked` as its value" {
  let h = @harness.mount(attribute_binding_module(), "AttributeBinding")
  h.check(".b", false)
  inspect(h.text(".o-bool"), content="false")
  inspect(h.checked_of(".b"), content="false")
}

///|
test "conditional-attributes: @if/@then/@else pick class AND title" {
  let h = @harness.mount(
    conditional_attributes_module(),
    "ConditionalAttributes",
  )
  debug_inspect(
    h.attr("button", "class"),
    content=(
      #|Some("btn btn-success")
    ),
  )
  debug_inspect(
    h.attr("button", "title"),
    content=(
      #|Some("Click to disable")
    ),
  )
  inspect(h.text(".on"), content="Enabled")
  inspect(h.find_all(".off").length(), content="0") // @hide drops the node
  h.click("button") // $toggleIsActive — a generated mutator
  debug_inspect(
    h.attr("button", "class"),
    content=(
      #|Some("btn btn-ghost")
    ),
  )
  debug_inspect(
    h.attr("button", "title"),
    content=(
      #|Some("Click to enable")
    ),
  )
  inspect(h.text(".off"), content="Disabled")
  inspect(h.find_all(".on").length(), content="0")
}

///|
test "event-modifiers: +send fires only on Enter, +cancel only on Escape" {
  let h = @harness.mount(event_modifiers_module(), "EventModifiers")
  h.type_into("input", "borges")
  inspect(h.value_of("input"), content="borges")
  // @show="truthy? .lastSentSearch" — nothing sent yet, so the <p> is absent
  inspect(h.find_all(".sent").length(), content="0")

  // a non-Enter key does NOT fire the +send handler
  h.key_down("input", "a", value=Str("borges"))
  inspect(h.find_all(".sent").length(), content="0")

  // Enter does
  h.key_down("input", "Enter", value=Str("borges"))
  inspect(h.text(".sent-q"), content="borges")

  // Escape runs $resetQuery (generated), clearing the query back to its default
  h.key_down("input", "Escape", value=Str("borges"))
  inspect(h.value_of("input"), content="")
}

///|
test "show-hide: @show / @hide add and remove the node" {
  let h = @harness.mount(show_hide_module(), "ShowHide")
  inspect(h.text(".toggle"), content="Show details")
  inspect(h.find_all(".details").length(), content="0")
  inspect(h.text(".hint"), content="(details are hidden)")
  // <x text=".count" @show=".isOpen"> — the @show on a render op emits no DOM
  inspect(
    h.text(".peek"),
    content=(
      #|Count, only when open:
    ),
  )
  h.click(".toggle")
  inspect(h.text(".toggle"), content="Hide details")
  inspect(h.find_all(".details").length(), content="1")
  inspect(h.find_all(".hint").length(), content="0")
  inspect(h.text(".peek"), content="Count, only when open: 0")
}

///|
test "show-hide: the revealed panel's button is live" {
  let h = @harness.mount(show_hide_module(), "ShowHide", args={
    "isOpen": Bool(true),
  })
  h.click(".bump")
  h.click(".bump")
  inspect(h.text(".peek"), content="Count, only when open: 2")
}
