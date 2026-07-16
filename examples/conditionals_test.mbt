///|
test "traffic-light: the button cycles red -> orange -> green -> red" {
  let h = @harness.mount(traffic_light_module(), "TrafficLight")
  inspect(h.text("code"), content="red")
  // only the matching @show="equals? $light '…'" span survives
  inspect(h.text(".advice"), content="You must STOP")
  h.click("button")
  inspect(h.text("code"), content="orange")
  inspect(h.text(".advice"), content="You must SLOW DOWN")
  h.click("button")
  inspect(h.text("code"), content="green")
  h.click("button")
  inspect(h.text("code"), content="red") // wraps around
}

///|
test "tabbed-ui: one string field drives the active tab and the visible panel" {
  let h = @harness.mount(tabbed_ui_module(), "TabbedUI")
  debug_inspect(
    h.attr("#t-overview", "class"),
    content=(
      #|Some("tab tab-active")
    ),
  )
  debug_inspect(
    h.attr("#t-pricing", "class"),
    content=(
      #|Some("tab")
    ),
  )
  inspect(h.find_all(".panel").length(), content="1")
  inspect(h.text("h4"), content="Overview")
  h.click("#t-pricing") // $setTab 'pricing' — a generated setter, string literal arg
  debug_inspect(
    h.attr("#t-pricing", "class"),
    content=(
      #|Some("tab tab-active")
    ),
  )
  debug_inspect(
    h.attr("#t-overview", "class"),
    content=(
      #|Some("tab")
    ),
  )
  inspect(h.text("h4"), content="Pricing")
  inspect(h.find_all(".panel").length(), content="1")
}

///|
test "list-and-filter: @when narrows the list, keeping ORIGINAL keys" {
  let h = @harness.mount(list_and_filter_module(), "ListAndFilter", args={
    "items": List(items()),
  })
  inspect(h.find_all("li").length(), content="14")
  h.type_into("input", "those")
  // 6 entries contain "those" — and each keeps its ORIGINAL index as @key
  inspect(h.find_all("li").length(), content="6")
  debug_inspect(
    h.texts("li"),
    content=(
      #|[
      #|  "0: those belonging to the Emperor",
      #|  "7: those included in this classification",
      #|  "8: those that tremble as if they were mad",
      #|  "10: those drawn with a very fine camel hair brush",
      #|  "12: those that have just broken the vase",
      #|  "13: those that from afar look like flies",
      #|]
    ),
  )
}

///|
test "list-and-filter: the filter is case-insensitive, and Escape resets it" {
  let h = @harness.mount(list_and_filter_module(), "ListAndFilter", args={
    "items": List(items()),
  })
  h.type_into("input", "EMPEROR")
  inspect(h.find_all("li").length(), content="1")
  h.key_down("input", "Escape") // @on.keydown+cancel="$resetQuery"
  inspect(h.find_all("li").length(), content="14")
}
