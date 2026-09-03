// `tutuca migrate` — rewrite files from one spelling of the language to the
// next.
//
// Pure like the rest of cli/: this half takes SOURCE TEXT and answers what the
// shell should write and what it should print. The shell reads and writes the
// files, the same split `gen` uses.
//
// The default is to say what WOULD change and write nothing. A tool that
// rewrites a tree by default is one people run once, by accident, on a repo
// with uncommitted work — and the whole point of a migration is that the
// author reads it.

///|
/// One file's migration, resolved: what it was, what it becomes, and the
/// per-edit lines a reader gets.
pub(all) struct MigrateFile {
  path : String
  /// The rewritten source, or None when the file was refused. A refused file
  /// is reported and skipped rather than stopping the run: a tree usually has
  /// one file that does not split, and the other ninety should still migrate.
  out : String?
  lines : Array[String]
  /// The refusal, when there is one, already worded.
  problem : String?
} derive(Debug, Eq)

///|
/// What the shell should do, over every file it was given.
pub(all) struct MigratePlan {
  files : Array[MigrateFile]
  /// Files that would change, whether or not `--write` was passed.
  changed : Int
  /// Files refused. The exit code turns on this and nothing else: a run that
  /// changed nothing succeeded, and a run that could not read a file did not.
  refused : Int
} derive(Debug, Eq)

///|
/// One file in, its migration out.
pub fn migrate_one(path : String, source : String) -> MigrateFile {
  // The same fallback name `gen` derives, and for the same reason: a
  // file whose `state {}` block is unnamed answers for the component the file
  // is named after, and the splitter needs to be told which that is.
  let (_, name) = gen_views_target(path)
  let m = @migrate.migrate_file(source, name~) catch {
    e =>
      return {
        path,
        out: None,
        lines: [],
        problem: Some("\{path}: \{migrate_problem(e)}"),
      }
  }
  {
    path,
    out: Some(m.out),
    lines: @migrate.diff_lines(path, m),
    problem: None,
  }
}

///|
/// Every file, as one plan.
pub fn migrate_all(
  inputs : Array[(String, String)],
  explicit? : Map[String, Bool] = Map([]),
) -> MigratePlan {
  let files : Array[MigrateFile] = []
  let mut changed = 0
  let mut refused = 0
  for pair in inputs {
    let f = migrate_one(pair.0, pair.1)
    if f.problem is Some(_) {
      // A file the caller NAMED and that does not split is reported: they said
      // it was a view file and it is not. One found by walking a directory is
      // skipped in silence — nobody claimed it was one, and a tree of pages
      // beside a tree of views is the ordinary shape of a project.
      if !explicit.contains(f.path) {
        continue
      }
      refused = refused + 1
    } else if !f.lines.is_empty() {
      changed = changed + 1
    }
    files.push(f)
  }
  { files, changed, refused, }
}

///|
/// A refusal in the words an author can act on.
///
/// The two rule bugs are worded as bugs, because they are: an author cannot
/// fix an overlap or a mismatch by editing their file, and telling them to try
/// would waste their afternoon.
fn migrate_problem(e : @migrate.MigrateError) -> String {
  match e {
    Unsplittable(why) =>
      "\{why} — the file has to split into blocks before it can be rewritten"
    Overlap(first~, second~, at~) =>
      "two rules claim the same text at offset \{at} (`\{first}` and `\{second}`) — a bug in tutuca; the file is untouched"
    Mismatch(rule~, at~, want~, got~) =>
      "rule `\{rule}` expected `\{want}` at offset \{at} and found `\{got}` — a bug in tutuca; the file is untouched"
  }
}

///|
/// The plan as terminal output.
///
/// Every changed file's edits, then a count. A file with nothing to change
/// says nothing at all: a migration over a hundred files should print the
/// three that moved, not a hundred lines of "ok".
pub fn migrate_emit(
  opts : GlobalOpts,
  plan : MigratePlan,
  wrote : Bool,
) -> Emit {
  let sb = StringBuilder()
  let errs = StringBuilder()
  for f in plan.files {
    match f.problem {
      Some(p) => errs.write_string(p + "\n")
      None =>
        for line in f.lines {
          sb.write_string(line + "\n")
        }
    }
  }
  if plan.changed == 0 {
    sb.write_string("nothing to migrate\n")
  } else {
    let verb = if wrote { "rewrote" } else { "would rewrite" }
    sb.write_string("\{verb} \{plan.changed} file(s)\n")
    if !wrote {
      sb.write_string("run again with --write to apply\n")
    }
  }
  ignore(opts)
  {
    out: sb.to_string(),
    err: errs.to_string(),
    // A run that changed nothing succeeded. Only a file that could not be
    // migrated is a failure, because that is the only outcome where the
    // author's tree is not in the state the command claims.
    exit_code: if plan.refused > 0 {
      1
    } else {
      0
    },
  }
}

///|
let migrate_help : String =
  #|tutuca migrate [path...] [--write]
  #|
  #|  Rewrites files from a retired spelling of the language to the current
  #|  one. A rename lands with the old spelling still parsing for one release;
  #|  this is what carries a tree across in between.
  #|
  #|  Paths are .html files or directories, following gen' rule: a
  #|  directory contributes the .html files that already have a generated
  #|  sibling, so pointing this at a project root does not rewrite index.html.
  #|
  #|  Says what would change and writes nothing, unless --write. Each line is
  #|
  #|    path:offset  rule  old -> new
  #|
  #|  where `rule` names the retirement, so a file with nine edits from one
  #|  rename reads differently from one with nine renames touching it once.
  #|
  #|  Every edit replaces a span of the ORIGINAL text. Comments, blank lines
  #|  and alignment come back exactly as they were: nothing here re-serialises
  #|  a declaration, which is the shape that would reformat a file it only
  #|  meant to rename a word in.
  #|
  #|  Running it twice is running it once. A file already in the current
  #|  spelling is not rewritten, and one that cannot be split into blocks is
  #|  reported and skipped rather than half-rewritten.
  #|
  #|  --write  apply the edits. Without it nothing on disk is touched.
  #|
  #|  Exit code 0 when every file was readable, whether or not anything
  #|  changed; non-zero when a file was refused.

///|
fn run_migrate(args : Array[String], opts : GlobalOpts) -> Outcome {
  let parsed = match parse_flags(args, command_spec("migrate")) {
    Ok(p) => p
    Err(e) => return Done(error_emit(opts, e))
  }
  if parsed.bool("help") || opts.help {
    return Done({ out: migrate_help, err: "", exit_code: 0, })
  }
  let roots = parsed.positionals
  if roots.is_empty() {
    return Done(
      error_emit(
        opts,
        err(
          CODE_USAGE_MISSING_ARGUMENT,
          "migrate requires an input .html file or a directory",
          hint="`tutuca migrate src/` says what would change; add --write to apply it",
        ),
      ),
    )
  }
  Migrate(opts, roots~, write=parsed.bool("write"))
}
