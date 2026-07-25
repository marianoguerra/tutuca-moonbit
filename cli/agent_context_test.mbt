// agent-context: structural asserts on the parsed schema, per MODE. The point
// of the mode split is that an agent reading this schema can invoke everything
// it lists — so the stock schema must not mention module commands, a module
// path, or exit codes only the module commands produce.

///|
fn schema(mode : @cli.CliMode) -> Json raise {
  @json.parse(@cli.agent_context_text(mode))
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
  for mode in [@cli.CliMode::Stock, Embedded] {
    guard schema(mode) is Object(top)
    @debug.assert_eq(top.keys().to_array(), [
      "schemaVersion", "cli", "version", "mode", "invocation", "globalFlags", "formats",
      "exitCodes", "errorCodes", "lintCodes", "commands",
    ])
    guard top.get("schemaVersion") is Some(Number(v, ..))
    assert_eq(v, 4)
    @debug.assert_eq(top.get("cli"), Some(Json::string("tutuca")))
    @debug.assert_eq(top.get("version"), Some(Json::string(@cli.VERSION)))
    // 14 error codes / 43 lint rules / 5 global flags are mode-independent
    guard top.get("errorCodes") is Some(Array(codes))
    assert_eq(codes.length(), 14)
    guard top.get("lintCodes") is Some(Array(rules))
    assert_eq(rules.length(), 43)
    guard top.get("globalFlags") is Some(Array(flags))
    assert_eq(flags.length(), 5)
    guard top.get("formats") is Some(Array(formats))
    assert_eq(formats.length(), 4)
  }
}

///|
test "no global --module flag in either mode" {
  for mode in [@cli.CliMode::Stock, Embedded] {
    guard schema(mode) is Object(top)
    guard top.get("globalFlags") is Some(Array(flags))
    for f in flags {
      guard f is Object(o)
      assert_not_eq(o.get("name"), Some(Json::string("module")))
    }
  }
}

///|
test "stock mode: 7 commands, none of them module commands" {
  guard schema(Stock) is Object(top)
  @debug.assert_eq(top.get("mode"), Some(Json::string("stock")))
  @debug.assert_eq(names_of(top), [
    "help", "feedback", "install-skill", "storybook", "gen-views", "watch", "agent-context",
  ])
  guard top.get("commands") is Some(Array(cmds))
  for c in cmds {
    guard c is Object(o)
    @debug.assert_eq(o.get("needsModule"), Some(Json::boolean(false)))
    // no-module entries carry neither needsEnv nor defaultFormat
    @debug.assert_eq(o.get("needsEnv"), None)
    @debug.assert_eq(o.get("defaultFormat"), None)
  }
  // and only the exit codes a stock binary can produce
  guard top.get("exitCodes") is Some(Array(exits))
  assert_eq(exits.length(), 2)
}

///|
test "stock invocation shape carries no module positional" {
  guard schema(Stock) is Object(top)
  guard top.get("invocation") is Some(Object(inv))
  @debug.assert_eq(
    inv.get("synopsis"),
    Some(Json::string("tutuca <command> [flags]")),
  )
  // the JS-compatible module-path keys are gone
  @debug.assert_eq(inv.get("moduleFirst"), None)
  @debug.assert_eq(inv.get("moduleFlag"), None)
  guard inv.get("note") is Some(String(note))
  assert_true(note.contains("plan_with_module"))
}

///|
test "embedded mode: 13 commands, module commands first and pathless" {
  guard schema(Embedded) is Object(top)
  @debug.assert_eq(top.get("mode"), Some(Json::string("embedded")))
  @debug.assert_eq(names_of(top), [
    "get", "list", "examples", "show", "lint", "render", "help", "feedback", "install-skill",
    "storybook", "gen-views", "watch", "agent-context",
  ])
  guard top.get("commands") is Some(Array(cmds))
  guard cmds[0] is Object(get_cmd)
  @debug.assert_eq(get_cmd.get("needsModule"), Some(Json::boolean(true)))
  @debug.assert_eq(get_cmd.get("needsEnv"), Some(Json::boolean(false)))
  @debug.assert_eq(get_cmd.get("defaultFormat"), Some(Json::string("cli")))
  guard cmds[4] is Object(lint_cmd)
  @debug.assert_eq(lint_cmd.get("name"), Some(Json::string("lint")))
  @debug.assert_eq(lint_cmd.get("needsEnv"), Some(Json::boolean(true)))
  // every module command's ONLY positional is the component-name filter
  for i in 0..<6 {
    guard cmds[i] is Object(o)
    guard o.get("positionals") is Some(Array(ps))
    assert_eq(ps.length(), 1)
    guard ps[0] is Object(p)
    @debug.assert_eq(p.get("name"), Some(Json::string("name")))
    @debug.assert_eq(p.get("required"), Some(Json::boolean(false)))
  }
  // lint/render exit codes are reachable here
  guard top.get("exitCodes") is Some(Array(exits))
  assert_eq(exits.length(), 4)
}

///|
test "no schema in either mode mentions a module-path positional" {
  for mode in [@cli.CliMode::Stock, Embedded] {
    assert_false(@cli.agent_context_text(mode).contains("module-path"))
  }
}
