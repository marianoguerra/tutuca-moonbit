// `tutuca outline` — what a `.tutu` file declares, and what is wrong with it.
//
// It reads the FILE, not the languages inside it: which sections are there,
// in what order, and what each one declares. That is the whole of what
// `tutufile` knows, and a command that claimed more would be claiming the
// section readers exist.
//
// Pure like the rest of cli/: source text in, output text out. The shell
// (cmd/tutuca) reads the file and prints the answer.

///|
/// What `outline` asked for.
pub(all) struct OutlinePlan {
  path : String
  /// Print the reports as JSON instead of as annotated source.
  json : Bool
} derive(Debug, Eq)

///|
/// Parse `outline` arguments.
fn run_outline(args : Array[String], opts : GlobalOpts) -> Outcome {
  let parsed = match parse_flags(args, command_spec("outline")) {
    Ok(p) => p
    Err(e) => return Done(error_emit(opts, e))
  }
  if parsed.bool("help") || opts.help {
    return Done({ out: outline_help, err: "", exit_code: 0, })
  }
  guard parsed.positionals is [path, ..] else {
    return Done(
      error_emit(
        opts,
        err(
          CODE_USAGE_MISSING_ARGUMENT,
          "outline requires a .tutu file",
          hint="`tutuca outline card.tutu` says what one declares",
        ),
      ),
    )
  }
  Outline(opts, plan={ path, json: parsed.bool("json"), })
}

///|
let outline_help : String =
  #|tutuca outline <file.tutu>
  #|
  #|  Say what a `.tutu` file declares: its sections, in file order, and the
  #|  declarations in each. Anything wrong with the file's shape is reported
  #|  against the source and the command exits 1.
  #|
  #|  Options:
  #|    --json         Report the diagnostics as JSON, one per line.
  #|    -h, --help     Show this.
  #|
  #|  Examples:
  #|    tutuca outline todos.tutu
  #|    tutuca outline todos.tutu --json

///|
/// The outline of one file, plus its diagnostics rendered for a terminal.
///
/// Exit code 1 when anything was reported at `Error`, so a script can gate on
/// it; warnings come back beside the outline and leave the code at 0.
pub fn outline_apply(plan : OutlinePlan, source : String) -> Emit {
  let sources = @report.Sources::new()
  let id = sources.add(plan.path, source)
  let file = @tutufile.read(source, id)
  let out = StringBuilder()
  out.write_string(outline_text(plan.path, file))
  let err = StringBuilder()
  if plan.json {
    for r in file.reports {
      err.write_string(@report_render.report_json(r, sources).stringify())
      err.write_string("\n")
    }
  } else {
    let config = { ..@report_render.default_config, color: Auto, }
    for r in file.reports {
      err.write_string(@report_render.render_string(r, sources, config))
    }
  }
  {
    out: out.to_string(),
    err: err.to_string(),
    exit_code: if file.ok() {
      0
    } else {
      1
    },
  }
}

///|
/// The outline itself: one line per section, in file order.
fn outline_text(path : String, file : @tutufile.TutuFile) -> String {
  let out = StringBuilder()
  out.write_string("\{path}\n")
  if file.sections.is_empty() {
    out.write_string("  (no sections)\n")
    return out.to_string()
  }
  for section in file.sections {
    let entries = []
    for d in section.decls {
      entries.push(outline_entry(d))
    }
    let body = if entries.is_empty() { "(empty)" } else { entries.join(", ") }
    out.write_string("  \{pad(section.section.name(), 10)}\{body}\n")
  }
  out.to_string()
}

///|
/// One declaration, written the way the file writes it.
fn outline_entry(d : @tutufile.Decl) -> String {
  let name = match d.kind {
    Fixture | Scene => "\"\{d.name}\""
    Style => "style"
    _ => d.name
  }
  let head = match d.kind.keyword() {
    "" => name
    "style" => name
    word => "\{word} \{name}"
  }
  let opts = []
  for o in d.options {
    opts.push("~\{o}")
  }
  if opts.is_empty() {
    head
  } else {
    head + " " + opts.join(" ")
  }
}

///|
/// Left-align a column so the section names line up.
fn pad(text : String, width : Int) -> String {
  let out = StringBuilder()
  out.write_string(text)
  for _ in text.length()..<width {
    out.write_string(" ")
  }
  out.to_string()
}
