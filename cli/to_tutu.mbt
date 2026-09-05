// `tutuca to-tutu` — an `.html` view file, written out as the `.tutu` file that
// replaces it.
//
// It converts and then CHECKS, in one command, because the two are not separate
// steps: a conversion nobody compared against the file it replaces is a guess.
// `tutufile/equiv` is what compares them, and anything it reports stops the
// write — so nothing this command produces can reach a file without having been
// held against the original.
//
// Pure like the rest of cli/: source in, text out. The shell reads the `.html`
// and writes the `.tutu`.

///|
/// What `to-tutu` asked for.
pub(all) struct ToTutuPlan {
  /// The `.html` file to convert.
  path : String
  /// Where to write the `.tutu`; None means beside it, with the extension
  /// changed.
  out : String?
  /// The component name a nameless `.html` file would be given.
  name : String
  /// Print the converted file instead of writing it.
  dry_run : Bool
} derive(Debug, Eq)

///|
/// Parse `to-tutu` arguments.
fn run_to_tutu(args : Array[String], opts : GlobalOpts) -> Outcome {
  let parsed = match parse_flags(args, command_spec("to-tutu")) {
    Ok(p) => p
    Err(e) => return Done(error_emit(opts, e))
  }
  if parsed.bool("help") || opts.help {
    return Done({ out: to_tutu_help, err: "", exit_code: 0, })
  }
  guard parsed.positionals is [path, ..] else {
    return Done(
      error_emit(
        opts,
        err(
          CODE_USAGE_MISSING_ARGUMENT,
          "to-tutu requires an .html view file",
          hint="`tutuca to-tutu Counter.html` writes Counter.tutu beside it",
        ),
      ),
    )
  }
  ToTutu(opts, plan={
    path,
    out: parsed.str("out"),
    name: parsed.str("name").unwrap_or(""),
    dry_run: parsed.bool("dry-run"),
  })
}

///|
let to_tutu_help : String =
  #|tutuca to-tutu <file.html> [--name <Name>] [-o <file.tutu>] [--dry-run]
  #|
  #|  Convert an `.html` view file into the `.tutu` file that replaces it.
  #|
  #|  It converts from what the pipeline PARSED — the schema, the handlers, the
  #|  view trees, the fixtures and the scenes — rather than from the text, and
  #|  it renames what the new notation renames: a component's own fields,
  #|  handlers, computes, rules and message names become snake_case. A protocol
  #|  member does not, because a protocol id and its members are a wire
  #|  vocabulary that a second host dispatches by those exact strings.
  #|
  #|  **It refuses rather than guesses.** Any construct it cannot spell is
  #|  listed and nothing is written; so is any difference `tutuca equiv` finds
  #|  between what it wrote and the file it read. A conversion that silently
  #|  dropped a handler would compile, render, and do less than it did.
  #|
  #|  Options:
  #|    --name <Name>  The component name a nameless .html file would be given,
  #|                   the same one `gen --name` supplies.
  #|    -o, --out      Where to write it (default: the .html path, .tutu).
  #|    --dry-run      Print the converted file instead of writing it.
  #|    -h, --help     Show this.
  #|
  #|  Examples:
  #|    tutuca to-tutu tutucard/examples/Counter.html --name Counter
  #|    tutuca to-tutu counter.html --dry-run

///|
/// Convert the source, check what came out, and answer with it.
///
/// On success `out` is the whole `.tutu` file and the shell writes it. On any
/// refusal or any difference, `out` is empty and `err` says what stopped it —
/// which is the same shape every other failing command has, so a caller that
/// checks the exit code never has to know which half failed.
pub fn to_tutu_apply(plan : ToTutuPlan, source : String) -> Emit {
  // A component name is a TYPE name, and a `.tutu` file always writes one. A
  // file that declared its component anonymously takes this one, so a lowercase
  // `--name` would produce a file whose first line is not a declaration — and
  // the error that reaches the author would be about the notation rather than
  // about the flag they passed.
  if plan.name != "" && !@totutu.is_type_name(plan.name) {
    return {
      out: "",
      err: "`--name \{plan.name}` is not a component name: a component is a type, so its name is written `\{@totutu.pascal_of(plan.name)}`\n",
      exit_code: 1,
    }
  }
  // With no `--name`, the file's own basename supplies it — the same default
  // `gen` uses — put into the spelling a component name takes.
  let name = if plan.name == "" {
    @totutu.pascal_of(basename_of(plan.path))
  } else {
    plan.name
  }
  let got = @totutu.convert(source, name~)
  if !got.refusals.is_empty() {
    let err = StringBuilder()
    err.write_string(
      "\{plan.path} has \{got.refusals.length()} construct\{if got.refusals.length() == 1 { "" } else { "s" }} the converter will not guess at:\n",
    )
    for r in got.refusals {
      err.write_string("  \{r}\n")
    }
    return { out: "", err: err.to_string(), exit_code: 1, }
  }
  let diffs = @equiv.compare(source, got.text, name~)
  if !diffs.is_empty() {
    let err = StringBuilder()
    err.write_string(
      "what \{plan.path} converted to differs from it in \{diffs.length()} place\{if diffs.length() == 1 { "" } else { "s" }}:\n",
    )
    for d in diffs {
      err.write_string("  \{d.line()}\n")
      err.write_string("    \{plan.path}: \{d.html}\n")
      err.write_string("    converted:   \{d.tutu}\n")
    }
    err.write_string(
      "\nNothing was written. This is a converter bug, not a file to fix by hand.\n",
    )
    // What it wrote still goes to stdout: a difference is a bug in this
    // command, and the first thing anybody fixing one needs is the output that
    // caused it. The exit code is what stops the shell writing a file.
    return { out: got.text, err: err.to_string(), exit_code: 1, }
  }
  { out: got.text, err: "", exit_code: 0, }
}

///|
/// A path's filename, without its directory or its extension.
fn basename_of(path : String) -> String {
  let mut start = 0
  for i, c in path.iter2() {
    if c is ('/' | '\\') {
      start = i + 1
    }
  }
  let file = path[start:].to_owned()
  match file.rev_find(".") {
    Some(dot) => file[:dot].to_owned()
    None => file
  }
}

///|
/// Where the converted file goes: what `--out` said, or the source path with
/// its extension changed.
pub fn ToTutuPlan::target(self : ToTutuPlan) -> String {
  match self.out {
    Some(p) => p
    None =>
      if self.path.has_suffix(".html") {
        self.path[:self.path.length() - 5].to_owned() + ".tutu"
      } else {
        self.path + ".tutu"
      }
  }
}
