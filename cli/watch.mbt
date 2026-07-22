// `tutuca watch` — regenerate view modules as the .html files change.
//
// Authoring a view is an edit/compile loop, and `gen-views` makes it a
// three-step one: edit the view, remember to regenerate, then build. Watch
// removes the middle step, so the generated modules are simply always current
// and the MoonBit compiler is the thing that tells you what broke.
//
// Pure like the rest of cli/: this half only decides WHAT to watch and what
// each changed file should generate. The shell (cmd/main) owns the watcher,
// the filesystem and the printing, because a watch loop is nothing but I/O.

///|
/// What the shell should watch and how to regenerate a hit.
///
/// `paths` are as the user gave them — files or directories; resolving a
/// directory to the view files under it needs the filesystem, so the shell
/// does it with `watch_manages`.
pub(all) struct WatchPlan {
  paths : Array[String]
  name : String?
  out : String?
  ir : Bool
} derive(Debug, Eq)

///|
let watch_help : String =
  #|tutuca watch [path...] [--out <dir>] [--name <Name>] [--no-ir]
  #|
  #|  Watches view files and regenerates their MoonBit modules on every save,
  #|  so the generated types are always current and the compiler is what tells
  #|  you a view and a component have drifted apart.
  #|
  #|  Each path is either an .html view file, or a directory to scan. A
  #|  directory contributes the .html files that ALREADY have a generated
  #|  sibling (<stem>_view_gen.mbt) — that is what distinguishes a view file
  #|  from a page like index.html, so watching a whole project is safe.
  #|  Defaults to the current directory.
  #|
  #|  Every file is generated once at startup, then again on each change.
  #|  --name applies only when watching a single file; a file that names its
  #|  own components with `id="Comp:view"` never needs it.
  #|
  #|  --out, --name and --no-ir mean what they do for `gen-views`.
  #|  Ctrl-C to stop.
  #|

///|
/// Parse `watch`'s own args. Finishes purely on help and usage errors,
/// otherwise hands the shell the plan.
pub fn run_watch(args : Array[String], opts : GlobalOpts) -> Outcome {
  let paths : Array[String] = []
  let mut name : String? = None
  let mut out : String? = None
  let mut ir = true
  let mut i = 0
  while i < args.length() {
    let a = args[i]
    let value_of = (flag : String) => {
      if a.has_prefix(flag + "=") {
        Some(a[flag.length() + 1:].to_owned())
      } else if a == flag && i + 1 < args.length() {
        i = i + 1
        Some(args[i])
      } else {
        None
      }
    }
    match a {
      "-h" | "--help" => return Done({ out: watch_help, err: "", exit_code: 0 })
      "--no-ir" => ir = false
      _ =>
        if a.has_prefix("--name") {
          match value_of("--name") {
            Some(v) => name = Some(v)
            None => return Done(missing_value(opts, "--name"))
          }
        } else if a.has_prefix("--out") {
          match value_of("--out") {
            Some(v) => out = Some(v)
            None => return Done(missing_value(opts, "--out"))
          }
        } else if a.has_prefix("-") {
          return Done(
            error_emit(
              opts,
              err(
                CODE_USAGE_UNKNOWN_FLAG,
                "unknown flag '\{a}' for watch",
                hint="see `tutuca watch -h` for the accepted flags",
              ),
            ),
          )
        } else {
          paths.push(a)
        }
    }
    i = i + 1
  }
  if opts.help {
    return Done({ out: watch_help, err: "", exit_code: 0 })
  }
  if name is Some(_) && paths.length() > 1 {
    return Done(
      error_emit(
        opts,
        err(
          CODE_USAGE_MUTUALLY_EXCLUSIVE,
          "--name applies to a single view file, but \{paths.length()} paths were given",
          hint="name the components inside the file with `id=\"Comp:view\"` instead",
        ),
      ),
    )
  }
  Watch(opts, plan={
    paths: if paths.is_empty() {
      ["."]
    } else {
      paths
    },
    name,
    out,
    ir,
  })
}

///|
/// True for a path the watcher should react to at all. Everything else in a
/// watched tree — .mbt, .json, the generated modules themselves — is noise,
/// and reacting to the modules we just wrote would loop.
pub fn is_view_path(path : String) -> Bool {
  path.has_suffix(".html")
}

///|
/// The generated module a view file produces, given `--out`. Shared with
/// `gen-views` so watch and one-shot generation cannot disagree about where
/// a file lands.
pub fn watch_target(path : String, out : String?) -> String {
  let (dir, stem) = split_path(path)
  match out {
    Some(o) =>
      if o.has_suffix(".mbt") {
        o
      } else {
        join_path(o, "\{stem}_view_gen.mbt")
      }
    None => join_path(dir, "\{stem}_view_gen.mbt")
  }
}

///|
/// The component name for a watched file: `--name`, else the basename
/// capitalized, matching `gen-views`.
pub fn watch_name(path : String, name : String?) -> String {
  match name {
    Some(n) => n
    None => {
      let (_, stem) = split_path(path)
      default_name(stem)
    }
  }
}

///|
/// Does this .html file look like one gen-views manages? The rule is the
/// presence of its generated sibling, which is what a directory scan uses to
/// tell a view file from a page.
pub fn watch_sibling(path : String) -> String {
  watch_target(path, None)
}

///|
/// The line printed for a regenerated file.
pub fn watch_generated_line(target : String) -> String {
  "  → \{target}\n"
}

///|
/// The line printed when a view fails. Watch does NOT exit on one: the next
/// save is expected to fix it, and dropping out of the loop mid-edit is the
/// opposite of useful.
///
/// `message` is expected to name the file already — `gen_views` errors do —
/// so nothing is prefixed here and the path is not printed twice.
pub fn watch_error_line(message : String) -> String {
  "  ✗ \{message}\n"
}

///|
/// The banner printed once the watcher is up.
pub fn watch_banner(files : Array[String], roots : Array[String]) -> String {
  if files.is_empty() {
    return "watching \{roots.join(", ")} — no view files yet (a .html with a generated sibling)\n"
  }
  "watching \{files.length()} view file(s) under \{roots.join(", ")}\n"
}
