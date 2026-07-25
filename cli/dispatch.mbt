// Top-level dispatch. Global flags come out first, the first remaining
// positional picks the command, and the mode decides which commands exist:
// `plan` is the stock binary, `plan_with_module` a project binary with its
// own ModuleDef compiled in (module_commands.mbt runs those).
//
// There is no module path to resolve. A stock binary asked for a module
// command says so — the command is real, this binary just has nothing to run
// it against — rather than claiming the name is unknown.

///|
pub fn plan(argv : Array[String]) -> Outcome {
  plan_stock(argv, Stock)
}

///|
/// The stock half of dispatch, shared by both modes. `mode` only changes what
/// `help` / `agent-context` describe and how an unresolved name is reported;
/// every command reached here needs no module.
fn plan_stock(argv : Array[String], mode : CliMode) -> Outcome {
  let (opts, rest) = match extract_globals(argv) {
    Ok(pair) => pair
    Err((opts, shape)) => return Done(error_emit(opts, shape))
  }
  if rest.length() == 0 {
    return Done(run_help(mode, None, opts))
  }
  let command = rest[0]
  let command_args = rest.iter().drop(1).to_array()
  // A global -h is forwarded as --help so each command's own parser handles it.
  if opts.help {
    command_args.push("--help")
  }
  match command {
    "help" => return Done(run_help(mode, command_args.get(0), opts))
    "feedback" => return run_feedback(command_args, opts)
    // agent-context ignores its args entirely (even --help).
    "agent-context" =>
      return Done({ out: agent_context_text(mode), err: "", exit_code: 0 })
    "install-skill" => return run_install_skill(command_args, opts)
    "storybook" => return run_storybook(command_args, opts)
    "gen-views" => return run_gen_views(command_args, opts)
    "watch" => return run_watch(command_args, opts)
    _ => ()
  }
  if opts.help && find_command(mode, command) is Some(_) {
    return Done(run_help(mode, Some(command), opts))
  }
  // Nothing stock matched. In Embedded mode the module commands were already
  // handled upstream, so anything left is genuinely unresolved.
  Done(unresolved_command(command, opts))
}

///|
/// Report a command name this binary cannot run. A module command in a stock
/// binary gets the honest explanation (and the way to get one that can);
/// everything else is an unknown command with a did-you-mean over every name
/// the CLI knows, in either mode.
fn unresolved_command(command : String, opts : GlobalOpts) -> Emit {
  if is_module_command(command) {
    return needs_embedded_module(command, opts)
  }
  error_emit(
    opts,
    err(
      CODE_USAGE_UNKNOWN_COMMAND,
      "Unknown command '\{command}'",
      suggestion?=did_you_mean(command, all_command_names()),
      hint="Run `tutuca help` for the full reference.",
    ),
  )
}

///|
fn needs_embedded_module(name : String, opts : GlobalOpts) -> Emit {
  error_emit(
    opts,
    err(
      CODE_USAGE_MISSING_MODULE,
      "'\{name}' needs a module, and this binary has none compiled in",
      hint="`\{name}` runs against a @component.ModuleDef value. A native binary cannot load user code, so build a project binary whose main calls @cli.plan_with_module(argv, your_module) — see demo/counter_cli.",
    ),
  )
}
