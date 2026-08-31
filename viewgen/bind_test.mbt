///|
fn bind_file(state : String, view : String) -> String {
  "<script type=\"tutuca/spec\">\nstate Form { " +
  state +
  " }\n</script>\n<template>" +
  view +
  "</template>"
}

///|
fn bind_error(state : String, view : String) -> String {
  try {
    @viewgen.generate(
      bind_file(state, view),
      name="Form",
      source_file="form.html",
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
      ("name: String", "<input @bind=\".name\">"),
      ("notes: String", "<textarea @bind=\".notes\"></textarea>"),
      (
        "choice: String", "<select @bind=\".choice\"><option>a</option></select>",
      ),
      ("done: Bool", "<input type=\"checkbox\" @bind=\".done\">"),
      ("count: Int", "<input type=\"number\" @bind=\".count\">"),
      ("small: UInt8", "<input type=\"range\" @bind=\".small\">"),
      ("ratio: Double", "<input type=\"number\" step=\"any\" @bind=\".ratio\">"),
    ] {
    assert_eq(bind_error(case.0, case.1), "")
  }
}

///|
test "@bind emits its exact coercion in the compiled event table" {
  let file = @viewgen.split_file(
    bind_file("count: Int", "<input type=\"number\" @bind=\".count\">"),
  )
  let ir = @viewgen.emit_ir_module("Form", "form.html", file)
  assert_true(
    ir.contains(
      "action=@anode.set_property_action(\"count\", EventPath([\"value\"]))",
    ),
  )
  assert_true(ir.contains("binding=@anode.BindInt(width=32, signed=true)"))
}

///|
test "@bind rejects unsupported or ambiguous combinations" {
  let cases = [
    ("name: String", "<div @bind=\".name\"></div>", "cannot bind String"),
    ("done: Bool", "<input @bind=\".done\">", "Bool only"),
    (
      "count: Int", "<input type=\"text\" @bind=\".count\">", "integer fields only",
    ),
    (
      "ratio: Double", "<input :type=\".kind\" @bind=\".ratio\">", "dynamic `:type`",
    ),
    (
      "names: Array[String]", "<input @bind=\".names\">", "does not support Array[String]",
    ),
    (
      "name: String", "<select multiple @bind=\".name\"></select>", "multiple `<select>`",
    ),
    (
      "name: String", "<input :value=\".name\" @bind=\".name\">", "conflicts with an explicit `:value`",
    ),
    (
      "name: String", "<input @bind=\".name\" @on.input=\"changed\">", "conflicts with an explicit `@on.input`",
    ),
  ]
  for case in cases {
    assert_true(bind_error(case.0, case.1).contains(case.2))
  }
}

///|
test "@bind requires a direct root field and a schema" {
  assert_true(
    bind_error("name: String", "<input @bind=\"$name\">").contains(
      "direct state field",
    ),
  )
  assert_true(
    bind_error(
      "names: Array[String]", "<div @each=\".names\"><input @bind=\".name\"></div>",
    ).contains("outside `@each`"),
  )
  let no_schema = try {
    @viewgen.generate(
      "<template><input @bind=\".name\"></template>",
      name="Form",
      source_file="form.html",
    )
    |> ignore
    ""
  } catch {
    e => e.message()
  }
  assert_true(
    no_schema.contains("needs a `<script type=\"tutuca/spec\">` schema"),
  )
}

///|
test "property actions are checked against member access and collection kind" {
  assert_eq(
    bind_error(
      "items: Array[String]", "<button @on.click=\".items.removeAt 0\">x</button>",
    ),
    "",
  )
  assert_true(
    bind_error(
      "name: String", "<button @on.click=\".name.push 'x'\">x</button>",
    ).contains("does not apply to String"),
  )
  assert_true(
    bind_error(
      "name: String property { label: String { get .name } }", "<button @on.click=\".label = 'x'\">x</button>",
    ).contains("read-only property `.label`"),
  )
  assert_true(
    bind_error(
      "name: String", "<button @on.click=\".missing = 'x'\">x</button>",
    ).contains("unknown member `.missing`"),
  )
}

///|
test "a property action does not become a generated input message" {
  let file = @viewgen.split_file(
    bind_file("name: String", "<input @on.input=\".name = e.value\">"),
  )
  let ir = @viewgen.emit_ir_module("Form", "form.html", file)
  assert_true(
    ir.contains(
      "action=@anode.set_property_action(\"name\", EventPath([\"value\"]))",
    ),
  )
  assert_false(ir.contains("HandlerName(name=\"setName\""))
}
