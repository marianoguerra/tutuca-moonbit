///|
fn bind_file(field : String, view : String) -> String {
  "spec:\n  Form:\n    field " +
  field +
  "\n\nview:\n  Form:\n    " +
  view +
  "\n"
}

///|
fn bind_error(field : String, view : String) -> String {
  try {
    @viewgen.emit_module(
      "Form",
      "form.tutu",
      @viewgen.read_file(bind_file(field, view), name="Form"),
    )
    |> ignore
    ""
  } catch {
    e => e.message()
  }
}

///|
test "@bind accepts the scalar field/tag matrix" {
  for
    case in [
      ("name :: String", "@input(~bind: it.name)"),
      ("notes :: String", "@textarea(~bind: it.notes)"),
      ("choice :: String", "@select(~bind: it.choice){@option{a}}"),
      ("done :: Bool", "@input(~type: \"checkbox\", ~bind: it.done)"),
      ("count :: Int", "@input(~type: \"number\", ~bind: it.count)"),
      ("small :: UInt8", "@input(~type: \"range\", ~bind: it.small)"),
      (
        "ratio :: Double", "@input(~type: \"number\", ~step: \"any\", ~bind: it.ratio)",
      ),
    ] {
    assert_eq(bind_error(case.0, case.1), "")
  }
}

///|
test "@bind emits its exact coercion in the compiled event table" {
  let file = @viewgen.read_file(
    bind_file("count :: Int", "@input(~type: \"number\", ~bind: it.count)"),
  )
  let ir = @viewgen.emit_ir_module("Form", "form.tutu", file)
  assert_true(
    ir.contains(
      "action=@anode.set_property_action(\"count\", @tutuca.Expr::event_path([\"value\"]))",
    ),
  )
  assert_true(ir.contains("binding=@anode.BindInt(width=32, signed=true)"))
}

///|
test "@bind rejects unsupported or ambiguous combinations" {
  let cases = [
    ("name :: String", "@div(~bind: it.name)", "cannot bind String"),
    ("done :: Bool", "@input(~bind: it.done)", "Bool only"),
    (
      "count :: Int", "@input(~type: \"text\", ~bind: it.count)", "integer fields only",
    ),
    (
      "ratio :: Double", "@input(~type: it.kind, ~bind: it.ratio)", "dynamic `~type`",
    ),
    (
      "names :: List.of(String)", "@input(~bind: it.names)", "does not support Array[String]",
    ),
    (
      "name :: String", "@select(~multiple, ~bind: it.name)", "multiple `<select>`",
    ),
    (
      "name :: String", "@input(~value: it.name, ~bind: it.name)", "conflicts with an explicit `~value` option",
    ),
    (
      "name :: String", "@input(~bind: it.name, ~on_input: changed)", "conflicts with an explicit `~on_input`",
    ),
  ]
  for case in cases {
    assert_true(bind_error(case.0, case.1).contains(case.2))
  }
}

///|
test "@bind requires a direct root field and a schema" {
  assert_true(
    bind_error("name :: String", "@input(~bind: name())").contains(
      "direct state field",
    ),
  )
  assert_true(
    bind_error(
      "names :: List.of(String)", "@each(value, key in it.names){@input(~bind: it.name)}",
    ).contains("outside `@each`"),
  )
  let no_schema = try {
    @viewgen.emit_module(
      "Form",
      "form.tutu",
      @viewgen.read_file(
        "view:\n  Form:\n    @input(~bind: it.name)\n",
        name="Form",
      ),
    )
    |> ignore
    ""
  } catch {
    e => e.message()
  }
  assert_true(no_schema.contains("needs a `spec:` section"))
}

///|
test "property actions are checked against member access and collection kind" {
  assert_eq(
    bind_error(
      "items :: List.of(String)", "@button(~on_click: it.items.delete_at(0)){x}",
    ),
    "",
  )
  assert_true(
    bind_error("name :: String", "@button(~on_click: it.name.push(\"x\")){x}").contains(
      "does not apply to String",
    ),
  )
  assert_true(
    bind_error(
      "name :: String\n    property label :: String:\n      get: it.name", "@button(~on_click: it.label := \"x\"){x}",
    ).contains("read-only property `.label`"),
  )
  assert_true(
    bind_error("name :: String", "@button(~on_click: it.missing := \"x\"){x}").contains(
      "unknown member `.missing`",
    ),
  )
}

///|
test "a property action does not become a generated input message" {
  let file = @viewgen.read_file(
    bind_file("name :: String", "@input(~on_input: it.name := e.value)"),
  )
  let ir = @viewgen.emit_ir_module("Form", "form.tutu", file)
  assert_true(
    ir.contains(
      "action=@anode.set_property_action(\"name\", @tutuca.Expr::event_path([\"value\"]))",
    ),
  )
  assert_false(ir.contains("Expr::handler_name(\"setName\""))
}
