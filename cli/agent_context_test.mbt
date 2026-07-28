// agent-context: structural asserts on the parsed schema. The contract is
// that everything it lists is invocable and nothing invocable is missing — so
// the command list is pinned by name, and the absence of the module surface
// (which an ahead-of-time port answers at compile time) is asserted directly.

///|
fn schema() -> Json raise {
  @json.parse(@cli.agent_context_text())
}

///|
fn names_of(top : Map[String, Json]) -> Array[String] {
  guard top.get("commands") is Some(Array(cmds))
  let out : Array[String] = []
  for c in cmds {
    guard c is Object(o)
    guard o.get("name") is Some(String(n))
    out.push(n)
  }
  out
}

///|
test "schema top-level shape" {
  guard schema() is Object(top)
  @debug.assert_eq(top.keys().to_array(), [
    "schemaVersion", "cli", "version", "invocation", "globalFlags", "exitCodes",
    "errorCodes", "commands",
  ])
  guard top.get("schemaVersion") is Some(Number(v, ..))
  assert_eq(v, 6)
  @debug.assert_eq(top.get("cli"), Some(Json::string("tutuca")))
  @debug.assert_eq(top.get("version"), Some(Json::string(@cli.VERSION)))
  guard top.get("errorCodes") is Some(Array(codes))
  assert_eq(codes.length(), 9)
  guard top.get("globalFlags") is Some(Array(flags))
  assert_eq(flags.length(), 2)
  guard top.get("exitCodes") is Some(Array(exits))
  assert_eq(exits.length(), 2)
}

///|
test "the command list is exactly the commands that exist" {
  guard schema() is Object(top)
  @debug.assert_eq(names_of(top), [
    "help", "feedback", "install-skill", "storybook", "gen-views", "gen-tailwind-css",
    "gen-margaui-css", "watch", "agent-context",
  ])
}

///|
test "nothing in the schema describes a module surface" {
  // The whole point of the AOT model: no module path, no module flag, no
  // command that inspects components at run time, and no lint-code table for
  // a linter that doesn't exist.
  let text = @cli.agent_context_text()
  for
    word in [
      "module-path", "moduleFlag", "moduleFirst", "needsModule", "lintCodes", "defaultFormat",
    ] {
    assert_false(text.contains(word))
  }
  guard schema() is Object(top)
  guard top.get("commands") is Some(Array(cmds))
  for c in cmds {
    guard c is Object(o)
    guard o.get("name") is Some(String(n))
    for gone in ["get", "list", "examples", "show", "lint", "render"] {
      assert_not_eq(n, gone)
    }
  }
  // and the note says where those checks went instead
  guard top.get("invocation") is Some(Object(inv))
  guard inv.get("note") is Some(String(note))
  assert_true(note.contains("gen-views"))
  assert_true(note.contains("moon test"))
}

///|
test "global flags are just --json and --help" {
  guard schema() is Object(top)
  guard top.get("globalFlags") is Some(Array(flags))
  let names : Array[String] = []
  for f in flags {
    guard f is Object(o)
    guard o.get("name") is Some(String(n))
    names.push(n)
  }
  @debug.assert_eq(names, ["json", "help"])
}
