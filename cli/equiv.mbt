// `tutuca equiv` — does this `.tutu` file mean what the `.html` file meant?
//
// The acceptance check for converting a view file, and the reason a conversion
// can be trusted. It compares what the PIPELINE reads out of each file — the
// schema, the handlers, the trees, the fixtures and the scenes — rather than
// the text, because the two notations spell the same thing differently on
// purpose and text would report every file as different.
//
// Pure like the rest of cli/: two sources in, a report out. The shell reads the
// two files.

///|
/// What `equiv` asked for.
pub(all) struct EquivPlan {
  /// The `.html` file being replaced.
  html : String
  /// The `.tutu` file replacing it.
  tutu : String
  /// The component name a nameless `.html` file would have been given.
  ///
  /// A `.html` file that declares one unnamed component takes its name from
  /// `--name` at generation time, and a `.tutu` file always names its
  /// components — so the comparison has to be told which name the nameless side
  /// was going to get, exactly as `gen` does.
  name : String
  /// Print each difference in full, both sides, instead of one line each.
  verbose : Bool
} derive(Debug, Eq)

///|
/// Parse `equiv` arguments.
fn run_equiv(args : Array[String], opts : GlobalOpts) -> Outcome {
  let parsed = match parse_flags(args, command_spec("equiv")) {
    Ok(p) => p
    Err(e) => return Done(error_emit(opts, e))
  }
  if parsed.bool("help") || opts.help {
    return Done({ out: equiv_help, err: "", exit_code: 0, })
  }
  guard parsed.positionals is [html, tutu, ..] else {
    return Done(
      error_emit(
        opts,
        err(
          CODE_USAGE_MISSING_ARGUMENT,
          "equiv requires the .html file and the .tutu file that replaces it",
          hint="`tutuca equiv Guarded.tutu Guarded.tutu` compares the two",
        ),
      ),
    )
  }
  Equiv(opts, plan={
    html,
    tutu,
    name: parsed.str("name").unwrap_or(""),
    verbose: parsed.bool("verbose"),
  })
}

///|
let equiv_help : String =
  #|tutuca equiv <file.html> <file.tutu>
  #|
  #|  Check that a `.tutu` file means what the `.html` file it replaces meant.
  #|
  #|  What is compared is what the pipeline reads out of each file — the schema,
  #|  the handlers, the view trees, the fixtures and the scenes — and not the
  #|  text. Positions, node ids and whitespace are ignored, because those differ
  #|  between two files without either meaning anything different; everything
  #|  else is compared, and any difference exits 1.
  #|
  #|  The view half reads the `.tutu` side with the direct reader
  #|  (`tutufile/toanode`) and the `.html` side with the HTML parser, so a clean
  #|  run says the conversion is sound AND that the two readers agree.
  #|
  #|  Options:
  #|    --name <Name>  The component name a nameless .html file would be given,
  #|                   the same one `gen --name` supplies.
  #|    --verbose      Print both sides of every difference, not one line each.
  #|    -h, --help     Show this.
  #|
  #|  Examples:
  #|    tutuca equiv tutucard/examples/Guarded.tutu tutucard/examples/Guarded.tutu
  #|    tutuca equiv counter.tutu counter.tutu --name Counter --verbose

///|
/// Compare the two sources and report.
pub fn equiv_apply(
  plan : EquivPlan,
  html_source : String,
  tutu_source : String,
) -> Emit {
  let diffs = @equiv.compare(html_source, tutu_source, name=plan.name)
  if diffs.is_empty() {
    return {
      out: "\{plan.tutu} is equivalent to \{plan.html}\n",
      err: "",
      exit_code: 0,
    }
  }
  let err = StringBuilder()
  err.write_string(
    "\{plan.tutu} differs from \{plan.html} in \{diffs.length()} place\{if diffs.length() == 1 { "" } else { "s" }}:\n",
  )
  for d in diffs {
    err.write_string("  \{d.line()}\n")
    if plan.verbose {
      err.write_string("    \{plan.html}: \{d.html}\n")
      err.write_string("    \{plan.tutu}: \{d.tutu}\n")
    }
  }
  if !plan.verbose {
    err.write_string("\nRun again with --verbose to see both sides.\n")
  }
  { out: "", err: err.to_string(), exit_code: 1, }
}
