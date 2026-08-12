// `tutuca help [command]`. The overview text lives in help_overview.mbt.

///|
fn run_help(target : String?, opts : GlobalOpts) -> Emit {
  match target {
    None => { out: overview(), err: "", exit_code: 0 }
    Some(name) =>
      match find_command(name) {
        None => unknown_command(name, opts)
        Some(cmd) => {
          // `help help` does not point at `tutuca help`: the reader is already
          // there. Every description, this one included, comes from the
          // registry — it used to be spelled out a second time here.
          let more = if name == "help" {
            ""
          } else {
            "Run `tutuca help` for the full reference including signatures and flags.\n"
          }
          {
            out: "\{cmd.name}: \{cmd.describe}\n" + more,
            err: "",
            exit_code: 0,
          }
        }
      }
  }
}
