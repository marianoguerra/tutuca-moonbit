// `tutuca storybook` — serve (or copy) the pre-built storybook gallery.
//
// The MoonBit port compiles AOT and the native binary cannot load user code,
// so there is no runtime *.dev.js discovery: the gallery is the compiled
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
  let mut dir = ""
  let mut port = 4321
  let mut out : String? = None
  let mut i = 0
  fn bad_port(v : String) -> Outcome {
    Done(
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

  while i < args.length() {
    let a = args[i]
    match a {
      "-h" | "--help" =>
        return Done({ out: storybook_help, err: "", exit_code: 0 })
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
            None => return bad_port(args[i])
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
            None => return bad_port(val)
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
