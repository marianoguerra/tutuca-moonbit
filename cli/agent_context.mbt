// `tutuca agent-context`: the machine-readable schema of the CLI surface.
//
// Everything it lists is invocable. There is no second command set, no mode
// and no module: an agent that reads this sees exactly what the binary does.
// What it does NOT list is as informative — nothing here inspects, documents,
// lints or renders components, because in an ahead-of-time port those are
// answered by `gen` (typed views, so a bad reference is a build error)
// and by `moon test`. `note` says so, so an agent doesn't go looking.

///|
/// 8: `new-guest` leaves the command set with the component-model format it
/// scaffolded. An agent that cached version 7 would offer a command that no
/// longer exists, which is exactly what a version is for.
///
/// 7: `new-guest` joined the command set, with three error codes of its own.
///
/// 6: `gen` takes `[path...]` rather than one `file`, matching the CSS
/// commands and `watch`. The batch is what the cross-component checks can see,
/// so the positional's arity is part of the contract, not a convenience —
/// hence a version bump rather than a silent widening.
///
/// 5: one command set. The `mode` field of 4 is gone with the embedded-module
/// story, along with `lintCodes` (there is no runtime linter), `formats`, and
/// the per-command `needsModule` / `needsEnv` / `defaultFormat`.
const SCHEMA_VERSION : Int = 8

///|
fn global_flags_schema() -> Array[FlagSpec] {
  [
    flag(
      "json",
      type_="boolean",
      description="Emit errors as a single-line JSON envelope on stderr.",
    ),
    flag("help", short="h", type_="boolean", description="Show help."),
  ]
}

///|
/// Exit codes this CLI can produce. Lint failures are compile errors and
/// nothing renders at run time, so there is no lint-findings or render-crash
/// exit code: only 0 and 1 exist.
fn exit_codes_schema() -> Array[(Int, String)] {
  [(0, "success"), (1, "usage error, or a command failed")]
}

///|
/// Serialize a flag omitting absent optional keys.
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
  Json::object({
    "name": cmd.name.to_json(),
    "describe": cmd.describe.to_json(),
    "flags": Json::array(cmd.flags.map(flag_to_json)),
    "positionals": Json::array(cmd.positionals.map(positional_to_json)),
  })
}

///|
pub fn agent_context_text() -> String {
  let schema : Json = {
    "schemaVersion": SCHEMA_VERSION.to_json(),
    "cli": "tutuca",
    "version": VERSION.to_json(),
    "invocation": {
      "synopsis": "tutuca <command> [flags]",
      "note": "tutuca-mb compiles ahead of time, so this CLI does not inspect, document, lint or render components. `gen` compiles a view file into typed MoonBit, which makes a bad field reference or an unhandled @on handler a BUILD error; component behaviour is checked by `moon test` over the marianoguerra/tutuca/testing/harness package. There is no module path and no module concept.",
    },
    "globalFlags": Json::array(global_flags_schema().map(flag_to_json)),
    "exitCodes": Json::array(
      exit_codes_schema().map(pair => {
        let j : Json = { "code": pair.0.to_json(), "meaning": pair.1.to_json() }
        j
      }),
    ),
    "errorCodes": error_codes.to_json(),
    "commands": Json::array(commands.map(command_to_json)),
  }
  schema.stringify(indent=2, escape_slash=false) + "\n"
}
