// agent-context: structural asserts on the parsed schema. Byte-level parity
// with the JS CLI is checked by diffing against `node tools/tutuca.js
// agent-context` (see cmd/main); these guard the shape from within.

///|
fn schema() -> Json raise {
  @json.parse(@cli.agent_context_text())
}

///|
test "schema top-level shape" {
  guard schema() is Object(top)
  @debug.assert_eq(top.keys().to_array(), [
    "schemaVersion", "cli", "version", "invocation", "globalFlags", "formats", "exitCodes",
    "errorCodes", "lintCodes", "commands",
  ])
  guard top.get("schemaVersion") is Some(Number(v, ..))
  assert_eq(v, 3)
  @debug.assert_eq(top.get("cli"), Some(Json::string("tutuca")))
  @debug.assert_eq(top.get("version"), Some(Json::string(@cli.VERSION)))
}

///|
test "schema counts: 13 commands, 14 error codes, 43 lint rules, 6 global flags" {
  guard schema() is Object(top)
  guard top.get("commands") is Some(Array(cmds))
  assert_eq(cmds.length(), 13)
  guard top.get("errorCodes") is Some(Array(codes))
  assert_eq(codes.length(), 14)
  guard top.get("lintCodes") is Some(Array(rules))
  assert_eq(rules.length(), 43)
  guard top.get("globalFlags") is Some(Array(flags))
  assert_eq(flags.length(), 6)
  guard top.get("formats") is Some(Array(formats))
  assert_eq(formats.length(), 4)
  guard top.get("exitCodes") is Some(Array(exits))
  assert_eq(exits.length(), 4)
}

///|
test "module vs no-module command schemas" {
  guard schema() is Object(top)
  guard top.get("commands") is Some(Array(cmds))
  guard cmds[0] is Object(get_cmd)
  @debug.assert_eq(get_cmd.get("name"), Some(Json::string("get")))
  @debug.assert_eq(get_cmd.get("needsModule"), Some(Json::boolean(true)))
  @debug.assert_eq(get_cmd.get("needsEnv"), Some(Json::boolean(false)))
  @debug.assert_eq(get_cmd.get("defaultFormat"), Some(Json::string("cli")))
  guard cmds[4] is Object(lint_cmd)
  @debug.assert_eq(lint_cmd.get("name"), Some(Json::string("lint")))
  @debug.assert_eq(lint_cmd.get("needsEnv"), Some(Json::boolean(true)))
  // no-module commands omit needsEnv/defaultFormat entirely
  guard cmds[6] is Object(help_cmd)
  @debug.assert_eq(help_cmd.get("name"), Some(Json::string("help")))
  @debug.assert_eq(help_cmd.get("needsModule"), Some(Json::boolean(false)))
  @debug.assert_eq(help_cmd.get("needsEnv"), None)
  @debug.assert_eq(help_cmd.get("defaultFormat"), None)
}
