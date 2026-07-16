// `tutuca storybook` — serve the pre-built storybook gallery.
//
// Divergence from the JS CLI (documented in help_overview.mbt): the MoonBit
// port compiles AOT and the native binary cannot load user code, so there is
// no runtime *.dev.js discovery. The gallery is the compiled example registry
// (storybook/), baked into a wasm host at build time. This command therefore
// SERVES that pre-built bundle (or copies it with --out, or lists it with
// --dry-run) rather than scanning a directory. `dir` optionally points at a
// bundle directory to serve instead of the one shipped next to the binary.

///|
let storybook_help : String =
  #|tutuca storybook [dir] [--port <n>] [--out <dir>] [--dry-run [--json]]
  #|
  #|  Serve the pre-built storybook gallery: the compiled example registry,
  #|  grouped into sections, rendered as one interactive WebAssembly app.
  #|
  #|  dir         a pre-built bundle directory to serve (default: the bundle
  #|              shipped next to the binary, i.e. dist/storybook).
  #|  --port <n>  preferred port (default 4321; falls back to a free port).
  #|  --out <dir> copy the static bundle to <dir> instead of serving.
  #|  --dry-run   print the compiled story registry instead of serving
  #|              (add --json for structured output).
  #|
  #|  Unlike the JS CLI this does not scan for *.dev.js: the port compiles
  #|  ahead of time, so stories are the compiled examples baked into the host.
  #|

///|
/// Parse storybook's args and either finish purely (help, dry-run, usage
/// errors) or hand the shell a serve/copy request.
pub fn run_storybook(args : Array[String], opts : GlobalOpts) -> Outcome {
  let mut dir = ""
  let mut port = 4321
  let mut out : String? = None
  let mut dry_run = false
  let mut json = false
  let mut i = 0
  while i < args.length() {
    let a = args[i]
    match a {
      "-h" | "--help" =>
        return Done({ out: storybook_help, err: "", exit_code: 0 })
      "--dry-run" => dry_run = true
      "--json" => json = true
      // accepted for CLI-surface parity; these are build-time concerns for the
      // compiled host and have no effect on serving.
      "--no-margaui" | "--no-check" | "--no-tests" => ()
      "--port" | "--out" => {
        i = i + 1
        if i >= args.length() {
          return Done(
            error_emit(
              opts,
              err(
                CODE_USAGE_UNKNOWN_FLAG,
                "flag '\{a}' expects a value",
                hint="see `tutuca storybook -h` for the accepted flags",
              ),
            ),
          )
        }
        if a == "--port" {
          match parse_port(args[i]) {
            Some(p) => port = p
            None =>
              return Done(
                error_emit(
                  opts,
                  err(
                    CODE_USAGE_UNKNOWN_FLAG,
                    "invalid --port value '\{args[i]}'",
                    hint="pass a positive integer, e.g. --port 4321",
                  ),
                ),
              )
          }
        } else {
          out = Some(args[i])
        }
      }
      other =>
        if other.has_prefix("--port=") {
          let val = other[7:].to_owned()
          match parse_port(val) {
            Some(p) => port = p
            None =>
              return Done(
                error_emit(
                  opts,
                  err(
                    CODE_USAGE_UNKNOWN_FLAG,
                    "invalid --port value '\{val}'",
                    hint="pass a positive integer, e.g. --port 4321",
                  ),
                ),
              )
          }
        } else if other.has_prefix("--out=") {
          out = Some(other[6:].to_owned())
        } else if other.has_prefix("-") {
          return Done(
            error_emit(
              opts,
              err(
                CODE_USAGE_UNKNOWN_FLAG,
                "unknown flag '\{other}' for storybook",
                hint="see `tutuca storybook -h` for the accepted flags",
              ),
            ),
          )
        } else {
          dir = other
        }
    }
    i = i + 1
  }
  if opts.help {
    return Done({ out: storybook_help, err: "", exit_code: 0 })
  }
  if dry_run {
    let sections = @sb.sections_of(@sb.stories())
    let want_json = json || opts.format is Some("json")
    let out_text = if want_json {
      @sb.dry_run_json(sections).stringify(indent=2, escape_slash=false) + "\n"
    } else {
      @sb.dry_run_text(sections)
    }
    return Done({ out: out_text, err: "", exit_code: 0 })
  }
  ServeStorybook(opts, dir~, port~, out~)
}

///|
/// A positive integer port, or None.
fn parse_port(s : String) -> Int? {
  let n = @string.parse_int(s) catch { _ => return None }
  if n > 0 {
    Some(n)
  } else {
    None
  }
}
