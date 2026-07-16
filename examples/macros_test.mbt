///|
test "macro-static: the macro expands in place, once per call site" {
  let h = @harness.mount(macro_static_module(), "StaticMacro")
  inspect(h.find_all(".badge").length(), content="2")
  inspect(h.text(".badge"), content="New")
  debug_inspect(
    h.attr(".badge", "class"),
    content=(
      #|Some("badge badge-info")
    ),
  )
}

///|
test "macro-params: defaults, static params, and dynamic params" {
  let h = @harness.mount(macro_params_module(), "MacroParams")
  // in order: the default; label="Sale" (static); :label="'Sale'" (literal
  // expression); kind+label static; :label=".status" (a FIELD reference)
  debug_inspect(
    h.texts(".badge"),
    content=(
      #|["New", "Sale", "Sale", "OK", "active"]
    ),
  )
  // :class="$'badge badge-{^kind}'" — the ^kind param inside a string template
  debug_inspect(
    h.attr(".badge", "class", nth=0),
    content=(
      #|Some("badge badge-info")
    ),
  )
  debug_inspect(
    h.attr(".badge", "class", nth=3),
    content=(
      #|Some("badge badge-success")
    ),
  )
  debug_inspect(
    h.attr(".badge", "class", nth=4),
    content=(
      #|Some("badge badge-warning")
    ),
  )
}

///|
test "macro-params: a dynamic param tracks the field it reads" {
  let h = @harness.mount(macro_params_module(), "MacroParams", args={
    "status": Str("archived"),
  })
  debug_inspect(
    h.texts(".badge"),
    content=(
      #|["New", "Sale", "Sale", "OK", "archived"]
    ),
  )
}

///|
test "macro-slots: slot content lands inside the macro, and stays live" {
  let h = @harness.mount(macro_slots_module(), "MacroSlots")
  debug_inspect(
    h.texts(".card-title"),
    content=(
      #|["Static Content", "Interactive"]
    ),
  )
  inspect(h.text(".count"), content="0")
  // @on.click="$inc" inside the macro's slot calls inc on the HOST component
  h.click(".bump")
  h.click(".bump")
  inspect(h.text(".count"), content="2")
}

///|
test "macro-named-slots: each child lands in its named slot" {
  let h = @harness.mount(macro_named_slots_module(), "MacroNamedSlots")
  inspect(h.text(".card-title"), content="Dashboard")
  inspect(
    h.text(".foot"),
    content=(
      #|Footer content here
    ),
  )
  inspect(
    h.text(".actions"),
    content=(
      #|+
    ),
  )
  // the unslotted children went to the default slot
  inspect(h.text(".body").contains("default slot content"), content="true")
  inspect(h.text(".body").contains("Count:"), content="true")
  // the button in the "actions" slot still drives the host component
  h.click(".bump")
  inspect(h.text(".count"), content="1")
}
