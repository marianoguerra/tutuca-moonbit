// `tutuca help [command]`. The overview text lives in help_overview.mbt.

///|
fn run_help(target : String?, opts : GlobalOpts) -> Emit {
  match target {
    None => { out: overview(), err: "", exit_code: 0 }
    Some("help") =>
      {
        out: "help: Show usage. `help <command>` for per-command detail.\n",
        err: "",
        exit_code: 0,
      }
    Some(name) =>
      match find_command(name) {
        None => unknown_command(name, opts)
        Some(cmd) =>
          {
            out: "\{cmd.name}: \{cmd.describe}\n" +
            "Run `tutuca help` for the full reference including signatures and flags.\n",
            err: "",
            exit_code: 0,
          }
      }
  }
}
