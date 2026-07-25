// Global-flag extraction.
//
// Two flags, because there are only two things that are global. No command
// emits a structured RESULT — the CLI generates files, watches them, serves a
// directory or describes itself — so there is nothing to choose an output
// format for; `--json` exists to make the ERROR envelope machine-readable.

///|
/// Flag names listed as valid in unknown-flag hints.
pub let global_flag_names : Array[String] = ["json", "help"]

///|
pub fn extract_globals(argv : Array[String]) -> (GlobalOpts, Array[String]) {
  let rest : Array[String] = []
  let mut json = false
  let mut help = false
  for a in argv {
    if a == "--json" {
      json = true
    } else if a == "-h" || a == "--help" {
      help = true
    } else {
      rest.push(a)
    }
  }
  ({ json, help }, rest)
}
