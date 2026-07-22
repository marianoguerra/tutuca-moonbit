// Top-level dispatcher: pure port of main() in tools/tutuca.js. Global flags
// come out first, the first remaining positional picks the command, module
// commands resolve their module path (second positional unless --module) —
// and only then hit their stub, so every usage error behaves exactly like
// the JS CLI today.

///|
pub fn plan(argv : Array[String]) -> Outcome {
  let (opts, rest) = match extract_globals(argv) {
    Ok(pair) => pair
    Err((opts, shape)) => return Done(error_emit(opts, shape))
  }
  if rest.length() == 0 {
    return Done(run_help(None, opts))
  }
  let command = rest[0]
  let command_args = rest.iter().drop(1).to_array()
  // JS appends --help to a no-module command's args when the global -h flag
  // was set, so each command's own parser handles it.
  if opts.help {
    command_args.push("--help")
  }
  match command {
    "help" => return Done(run_help(command_args.get(0), opts))
    "feedback" => return run_feedback(command_args, opts)
    // JS agent-context ignores its args entirely (even --help).
    "agent-context" =>
      return Done({ out: agent_context_text(), err: "", exit_code: 0 })
    "install-skill" => return run_install_skill(command_args, opts)
    "storybook" => return run_storybook(command_args, opts)
    "gen-views" => return run_gen_views(command_args, opts)
    "watch" => return run_watch(command_args, opts)
    _ => ()
  }
  if opts.help {
    return Done(run_help(Some(command), opts))
  }
  match find_command(command) {
    None =>
      Done(
        error_emit(
          opts,
          err(
            CODE_USAGE_UNKNOWN_COMMAND,
            "Unknown command '\{command}'",
            suggestion?=did_you_mean(command, command_names()),
            hint="Run `tutuca help` for the full reference.",
          ),
        ),
      )
    Some(cmd) => {
      // Module path: second positional unless --module overrides. The module
      // must come immediately after the command, before per-command flags.
      if opts.module_path is None &&
        (rest.length() < 2 || rest[1].has_prefix("-")) {
        return Done(
          error_emit(
            opts,
            err(
              CODE_USAGE_MISSING_MODULE,
              "'\{command}' requires a module path",
              hint="Pass it as the second positional: `tutuca \{command} <module-path>`, or use --module=<path>.",
            ),
          ),
        )
      }
      match cmd.impl_ {
        Stub(missing) => Done(stub(command, missing))
        // No wired module commands yet; unreachable until layers land.
        Wired =>
          Done(
            stub(command, ["internal: command marked Wired but has no runner"]),
          )
      }
    }
  }
}
