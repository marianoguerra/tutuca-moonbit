// `tutuca storybook` — serve (or copy) the pre-built storybook gallery.
//
// The MoonBit port compiles AOT and the native binary cannot load user code,
// so there is no runtime example discovery: the gallery is the compiled
// example registry baked into a wasm host at build time by
// `cmd/dev -- dist`. What is left for the CLI is a static file server, so
// that is all this command is — serve a directory, or copy it with --out.
// It knows nothing about the story registry, which is why `cli` does not
// depend on the `storybook` packages at all.

///|
let storybook_help : String =
  #|tutuca storybook [dir] [--port <n>] [--out <dir>]
  #|
  #|  Serve the pre-built storybook gallery bundle over HTTP.
  #|
  #|  dir         the bundle directory to serve (default: the bundle shipped
  #|              next to the binary, i.e. dist/storybook).
  #|  --port <n>  preferred port (default 4321; falls back to a free port).
  #|  --out <dir> copy the static bundle to <dir> instead of serving.
  #|
  #|  Build the bundle with `moon run --target native cmd/dev -- dist`.
  #|

///|
/// Parse storybook's args and either finish purely (help, usage errors) or
/// hand the shell a serve/copy request.
fn run_storybook(args : Array[String], opts : GlobalOpts) -> Outcome {
  let parsed = match parse_flags(args, command_spec("storybook")) {
    Ok(p) => p
    Err(e) => return Done(error_emit(opts, e))
  }
  if parsed.bool("help") || opts.help {
    return Done({ out: storybook_help, err: "", exit_code: 0 })
  }
  let dir = parsed.positionals.get(0).unwrap_or("")
  let out = parsed.str("out")
  // The registry says `--port` takes a string; that it must be a positive
  // integer is this command's rule, not the flag grammar's.
  let port = match parsed.str("port") {
    Some(v) =>
      match parse_port(v) {
        Some(p) => p
        None =>
          return Done(
            error_emit(
              opts,
              err(
                CODE_USAGE_BAD_FLAG_VALUE,
                "invalid --port value '\{v}'",
                hint="pass a positive integer, e.g. --port 4321",
              ),
            ),
          )
      }
    None => 4321
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
