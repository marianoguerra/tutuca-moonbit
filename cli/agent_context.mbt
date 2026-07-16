// `tutuca agent-context`: port of tools/cli/commands/agent-context.js.
// Emits the schemaVersion-3 JSON schema of the whole CLI surface. Key order
// mirrors the JS object literals (Json objects are insertion-ordered maps).

///|
const SCHEMA_VERSION : Int = 3

///|
fn global_flags_schema() -> Array[FlagSpec] {
  [
    flag(
      "json",
      type_="boolean",
      description="Shorthand for --format=json. Errors also emit JSON on stderr.",
    ),
    flag(
      "format",
      short="f",
      type_="string",
      enum_=format_names,
      description="Output format. Per-command default below; html is render-only; json works for every module command.",
    ),
    flag(
      "output",
      short="o",
      type_="string",
      description="Write to file instead of stdout.",
    ),
    flag(
      "pretty",
      type_="boolean",
      description="Pretty-print HTML/JSON output.",
    ),
    flag(
      "module",
      type_="string",
      description="Alternative to first-positional module path.",
    ),
    flag("help", short="h", type_="boolean", description="Show help."),
  ]
}

///|
fn exit_codes_schema() -> Array[(Int, String)] {
  [
    (0, "success"),
    (1, "usage error (bad args, missing module, bad module shape)"),
    (2, "lint findings at error level (lint command)"),
    (3, "render crash (render command)"),
  ]
}

///|
/// Serialize a flag omitting absent optional keys, in the JS literal key
/// order: name, short, type, enum, description.
fn flag_to_json(f : FlagSpec) -> Json {
  let m : Map[String, Json] = { "name": f.name.to_json() }
  match f.short {
    Some(s) => m["short"] = s.to_json()
    None => ()
  }
  m["type"] = f.type_.to_json()
  match f.enum_ {
    Some(e) => m["enum"] = e.to_json()
    None => ()
  }
  match f.description {
    Some(d) => m["description"] = d.to_json()
    None => ()
  }
  Json::object(m)
}

///|
fn positional_to_json(p : PositionalSpec) -> Json {
  let m : Map[String, Json] = {
    "name": p.name.to_json(),
    "required": p.required.to_json(),
  }
  match p.description {
    Some(d) => m["description"] = d.to_json()
    None => ()
  }
  match p.note {
    Some(n) => m["note"] = n.to_json()
    None => ()
  }
  Json::object(m)
}

///|
fn command_to_json(cmd : CommandSpec) -> Json {
  let m : Map[String, Json] = {
    "name": cmd.name.to_json(),
    "describe": cmd.describe.to_json(),
    "needsModule": cmd.needs_module.to_json(),
  }
  // Module commands carry needsEnv + defaultFormat (agent-context.js
  // moduleCommandSchema); no-module entries don't have the keys at all.
  if cmd.needs_module {
    m["needsEnv"] = cmd.needs_env.to_json()
    match cmd.default_format {
      Some(f) => m["defaultFormat"] = f.to_json()
      None => ()
    }
  }
  m["flags"] = Json::array(cmd.flags.map(flag_to_json))
  m["positionals"] = Json::array(cmd.positionals.map(positional_to_json))
  Json::object(m)
}

///|
fn lint_rule_to_json(r : LintRule) -> Json {
  {
    "code": r.code.to_json(),
    "level": r.level.to_json(),
    "group": r.group.to_json(),
    "summary": r.summary.to_json(),
  }
}

///|
pub fn agent_context_text() -> String {
  let schema : Json = {
    "schemaVersion": SCHEMA_VERSION.to_json(),
    "cli": "tutuca",
    "version": VERSION.to_json(),
    "invocation": {
      "synopsis": "tutuca <command> <module-path> [name] [flags]",
      "moduleFirst": false,
      "moduleFlag": "module",
      "note": "For module-required commands, the module path is the second positional. Use --module=<path> as an alternative.",
    },
    "globalFlags": Json::array(global_flags_schema().map(flag_to_json)),
    "formats": format_names.to_json(),
    "exitCodes": Json::array(
      exit_codes_schema().map(pair => {
        let j : Json = { "code": pair.0.to_json(), "meaning": pair.1.to_json() }
        j
      }),
    ),
    "errorCodes": error_codes.to_json(),
    "lintCodes": Json::array(lint_rules.map(lint_rule_to_json)),
    "commands": Json::array(commands.map(command_to_json)),
  }
  schema.stringify(indent=2, escape_slash=false) + "\n"
}
