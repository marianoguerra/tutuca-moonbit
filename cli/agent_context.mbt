// `tutuca agent-context`: the machine-readable schema of the CLI surface.
//
// It describes the command set the RUNNING binary has, not a superset: a
// stock binary reports only the commands that need no user module, and an
// embedded one additionally reports the module commands — without a
// module-path positional, because there is no such thing here. An agent that
// reads this can invoke everything it sees.

///|
/// 4: mode-aware. The set of commands, the invocation shape and the exit
/// codes now depend on `mode`, and the module-path positional / `--module`
/// flag of the JS-compatible schema are gone.
const SCHEMA_VERSION : Int = 4

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
    flag("help", short="h", type_="boolean", description="Show help."),
  ]
}

///|
/// Exit codes a binary in `mode` can actually produce. 2 and 3 belong to
/// `lint` and `render`, so a stock binary never reports them.
fn exit_codes_schema(mode : CliMode) -> Array[(Int, String)] {
  let codes : Array[(Int, String)] = [
    (0, "success"),
    (1, "usage error (bad args, missing module, bad module shape)"),
  ]
  if mode is Embedded {
    codes.push((2, "lint findings at error level (lint command)"))
    codes.push((3, "render crash (render command)"))
  }
  codes
}

///|
fn mode_name(mode : CliMode) -> String {
  match mode {
    Stock => "stock"
    Embedded => "embedded"
  }
}

///|
/// How to invoke this binary, and what its mode means.
fn invocation_schema(mode : CliMode) -> Json {
  match mode {
    Stock =>
      {
        "synopsis": "tutuca <command> [flags]",
        "note": "This is the stock tutuca binary: it ships only the commands that need no user module. The module commands (get, list, examples, show, lint, render) run against a @component.ModuleDef value and exist only in a project binary that compiles its module in and calls @cli.plan_with_module(argv, your_module) — see demo/counter_cli. There is no module path and no --module flag: a native binary cannot load user code.",
      }
    Embedded =>
      {
        "synopsis": "tutuca <command> [name] [flags]",
        "note": "This binary has a module compiled in, so the module commands run against it. Their first positional is an OPTIONAL component-name filter, not a module path — the module is the one compiled in.",
      }
  }
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
pub fn agent_context_text(mode : CliMode) -> String {
  let schema : Json = {
    "schemaVersion": SCHEMA_VERSION.to_json(),
    "cli": "tutuca",
    "version": VERSION.to_json(),
    "mode": mode_name(mode).to_json(),
    "invocation": invocation_schema(mode),
    "globalFlags": Json::array(global_flags_schema().map(flag_to_json)),
    "formats": format_names.to_json(),
    "exitCodes": Json::array(
      exit_codes_schema(mode).map(pair => {
        let j : Json = { "code": pair.0.to_json(), "meaning": pair.1.to_json() }
        j
      }),
    ),
    "errorCodes": error_codes.to_json(),
    "lintCodes": Json::array(lint_rules.map(lint_rule_to_json)),
    "commands": Json::array(commands_for(mode).map(command_to_json)),
  }
  schema.stringify(indent=2, escape_slash=false) + "\n"
}
