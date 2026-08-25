// `tutuca watch` — regenerate view modules as the .html files change.
//
// Authoring a view is an edit/compile loop, and `gen-views` makes it a
// three-step one: edit the view, remember to regenerate, then build. Watch
// removes the middle step, so the generated modules are simply always current
// and the MoonBit compiler is the thing that tells you what broke.
//
// Pure like the rest of cli/: this half only decides WHAT to watch and what
// each changed file should generate. The shell (cmd/tutuca) owns the watcher,
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
  /// Refresh a stylesheet after every settled batch, or None to watch views
  /// only. It is a whole `CssPlan` rather than a couple of loose fields so the
  /// shell can run the SAME collect/compile/write path `gen-margaui-css` runs —
  /// a stylesheet that differs between watch and a one-shot build would be
  /// worse than no stylesheet at all.
  css : CssPlan?
} derive(Debug, Eq)

///|
let watch_help : String =
  #|tutuca watch [path...] [--out <dir>] [--name <Name>] [--no-ir]
  #|             [--tailwind-css <file> | --margaui-css <file>]
  #|             [--css-entry <file>] [--css-classes <file>]
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
  #|
  #|  --tailwind-css / --margaui-css also rewrite that stylesheet after every
  #|  settled batch, so a new class in a view is styled by the time you reload.
  #|  The two are alternatives — they are the same choice `gen-tailwind-css` and
  #|  `gen-margaui-css` make. The stylesheet is a whole-project artifact, so it
  #|  is rebuilt once per batch over EVERY watched view, not per changed file.
  #|  --css-entry and --css-classes are the CSS commands' --entry / --classes;
  #|  pass them here if your build passes them, or watch will write a stylesheet
  #|  that differs from the one you ship. Polyfills are always the default (3).
  #|  Ctrl-C to stop.
  #|

///|
/// Parse `watch`'s own args. Finishes purely on help and usage errors,
/// otherwise hands the shell the plan.
fn run_watch(args : Array[String], opts : GlobalOpts) -> Outcome {
  let parsed = match parse_flags(args, command_spec("watch")) {
    Ok(p) => p
    Err(e) => return Done(error_emit(opts, e))
  }
  if parsed.bool("help") || opts.help {
    return Done({ out: watch_help, err: "", exit_code: 0 })
  }
  let paths = parsed.positionals
  let name = parsed.str("name")
  let out = parsed.str("out")
  let ir = !parsed.bool("no-ir")
  let tailwind_css = parsed.str("tailwind-css")
  let margaui_css = parsed.str("margaui-css")
  let css_entry = parsed.str("css-entry")
  let css_classes = parsed.str("css-classes")
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
  if tailwind_css is Some(_) && margaui_css is Some(_) {
    return Done(
      error_emit(
        opts,
        err(
          CODE_USAGE_MUTUALLY_EXCLUSIVE,
          "--tailwind-css and --margaui-css write the same file from different stylesheets",
          hint="pick one: --margaui-css if your views use margaui components, --tailwind-css otherwise",
        ),
      ),
    )
  }
  let css_target = match (tailwind_css, margaui_css) {
    (Some(t), _) => Some((t, false))
    (_, Some(t)) => Some((t, true))
    _ => None
  }
  // Silently ignoring these would leave watch writing a stylesheet that differs
  // from the built one for a reason nothing on screen explains.
  if css_target is None && (css_entry is Some(_) || css_classes is Some(_)) {
    return Done(
      error_emit(
        opts,
        err(
          CODE_USAGE_MISSING_ARGUMENT,
          "--css-entry/--css-classes need --tailwind-css or --margaui-css",
          hint="they configure the stylesheet watch writes; without one of those, watch writes no stylesheet",
        ),
      ),
    )
  }
  let watched = if paths.is_empty() { ["."] } else { paths }
  Watch(opts, plan={
    paths: watched,
    name,
    out,
    ir,
    css: match css_target {
      None => None
      Some((target, margaui)) =>
        Some({
          // The same roots watch resolves its view files from, so the class set
          // is the whole watched project rather than whatever last changed.
          paths: watched,
          out: Some(target),
          entry: css_entry,
          extra_classes: css_classes,
          print_classes: false,
          polyfills: 3,
          margaui,
        })
    },
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
/// The line printed after watch rewrites the stylesheet.
pub fn watch_css_line(target : String, classes~ : Int) -> String {
  "  → \{target} (\{classes} classes)\n"
}

///|
/// The banner printed once the watcher is up.
pub fn watch_banner(files : Array[String], roots : Array[String]) -> String {
  if files.is_empty() {
    return "watching \{roots.join(", ")} — no view files yet (a .html with a generated sibling)\n"
  }
  "watching \{files.length()} view file(s) under \{roots.join(", ")}\n"
}
