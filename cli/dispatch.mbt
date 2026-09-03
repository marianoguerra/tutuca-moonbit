// Top-level dispatch. Global flags come out first, the first remaining
// positional picks the command, and the command's own parser takes the rest.
//
// There is one command set and no module concept: a command either exists or
// it doesn't. Anything a user might have expected here that inspects their
// components — get/list/show/lint/render — is the compiler's job in an
// ahead-of-time port, not a CLI's.

///|
pub fn plan(argv : Array[String]) -> Outcome {
  let (opts, rest) = extract_globals(argv)
  if rest.length() == 0 {
    return Done(run_help(None, opts))
  }
  let command = rest[0]
  let command_args = rest.iter().drop(1).to_array()
  // A global -h is forwarded as --help so each command's own parser handles it.
  if opts.help {
    command_args.push("--help")
  }
  match command {
    "help" => return Done(run_help(command_args.get(0), opts))
    "feedback" => return run_feedback(command_args, opts)
    // agent-context ignores its args entirely (even --help).
    "agent-context" =>
      return Done({ out: agent_context_text(), err: "", exit_code: 0, })
    "install-skill" => return run_install_skill(command_args, opts)
    "new-guest" => return run_new_guest(command_args, opts)
    "new-storybook" => return run_new_storybook(command_args, opts)
    "storybook" => return run_storybook(command_args, opts)
    "gen-views" => return run_gen_views(command_args, opts)
    "migrate" => return run_migrate(command_args, opts)
    "gen-tailwind-css" => return run_gen_css(command_args, opts, margaui=false)
    "gen-margaui-css" => return run_gen_css(command_args, opts, margaui=true)
    "watch" => return run_watch(command_args, opts)
    "trace" => return run_trace(command_args, opts)
    _ => ()
  }
  Done(unknown_command(command, opts))
}

///|
fn unknown_command(command : String, opts : GlobalOpts) -> Emit {
  error_emit(
    opts,
    err(
      CODE_USAGE_UNKNOWN_COMMAND,
      "Unknown command '\{command}'",
      suggestion?=did_you_mean(command, command_names()),
      hint="Run `tutuca help` for the full reference.",
    ),
  )
}
