// Spec for the CLI core. READONLY by convention: concrete public data types
// plus `declare` stubs; implementations live in separate files.
//
// What this CLI is, and is not. tutuca-mb compiles ahead of time, so anything
// that can be known about a component is known to the COMPILER: `gen-views`
// turns a view file into typed MoonBit — a misspelled field or an unhandled
// `@on` handler is a build error — and component behaviour is checked by
// `moon test` over the `testing/harness` package. The CLI therefore does not
// inspect, document, lint or render components at run time. It has no notion
// of "a module" at all. What is left are the jobs that genuinely happen
// outside the compiler: generating view modules, watching them, serving a
// pre-built gallery, installing the skill, and describing itself.
//
// The core is deliberately I/O-free: `plan(argv)` returns an `Outcome` and
// the native shell (cmd/main) writes stdout/stderr, reads stdin, touches the
// filesystem and exits. This keeps the core testable on any target.

///|
/// Global flags extracted before command dispatch. `json` switches the error
/// envelope to a machine-readable one; there is nothing else to format, since
/// no command emits a structured result.
pub(all) struct GlobalOpts {
  json : Bool
  help : Bool
} derive(Debug, Eq)

///|
/// A coded CLI error. Rendering is plain text, or a single-line JSON
/// envelope under --json.
pub(all) struct ErrShape {
  code : String
  message : String
  suggestion : @lint.Suggestion?
  hint : String?
  where_ : String?
  exit_code : Int
} derive(Debug, Eq)

///|
/// Flag metadata for help + the agent-context schema.
pub(all) struct FlagSpec {
  name : String
  short : String?
  type_ : String // "string" | "boolean"
  enum_ : Array[String]?
  description : String?
} derive(Debug, Eq)

///|
pub(all) struct PositionalSpec {
  name : String
  required : Bool
  description : String?
  note : String?
} derive(Debug, Eq)

///|
/// One command. Every registered command is runnable — there is no
/// "implemented?" flag and no second command set.
pub(all) struct CommandSpec {
  name : String
  describe : String
  flags : Array[FlagSpec]
  positionals : Array[PositionalSpec]
} derive(Debug, Eq)

///|
/// What the shell should do: write `out` to stdout, `err` to stderr, exit
/// with `exit_code`.
pub(all) struct Emit {
  out : String
  err : String
  exit_code : Int
} derive(Debug, Eq)

///|
/// Result of pure dispatch. `Feedback` defers to the shell for the stdin
/// fallback and the ~/.tutuca/feedback.jsonl append; `InstallSkill` defers
/// the filesystem writes of the embedded skill assets (install_skill.mbt);
/// everything else is fully decided by the core.
pub(all) enum Outcome {
  Done(Emit)
  Feedback(GlobalOpts, message~ : String?)
  InstallSkill(GlobalOpts, plan~ : SkillInstallPlan)
  /// Serve the pre-built storybook gallery bundle (storybook.mbt). The core
  /// decides the flags; the shell (cmd/main) resolves the bundle directory,
  /// starts the static HTTP server, or copies the bundle for `--out`.
  ServeStorybook(GlobalOpts, dir~ : String, port~ : Int, out~ : String?)
  /// Compile the views in `input` into the MoonBit module `target`. The core
  /// decides the paths and the component name; the shell reads the input file,
  /// calls `gen_views`, and writes (or prints, under `dry_run`) the plan.
  GenViews(
    GlobalOpts,
    input~ : String,
    target~ : String,
    name~ : String,
    dry_run~ : Bool,
    ir~ : Bool
  )
  /// Regenerate view modules as their .html files change. The core decides
  /// what to watch; the shell owns the watcher and the filesystem.
  Watch(GlobalOpts, plan~ : WatchPlan)
  /// Compile the classes a project's views use into CSS (gen_css.mbt). The core
  /// decides the roots and the flags; the shell walks the tree, reads the view
  /// files, calls `collect_view_classes` and then the compiler, and writes the
  /// result.
  GenCss(GlobalOpts, plan~ : CssPlan)
} derive(Debug, Eq)

///|
/// What `gen-tailwind-css` / `gen-margaui-css` asked for. `margaui` is the only
/// difference between the two commands: which stylesheet set the collected
/// classes are compiled against.
pub(all) struct CssPlan {
  /// View files or directories to search. Never empty — the parser defaults it
  /// to ["."], the same root `watch` takes.
  paths : Array[String]
  /// Where to write the CSS; None means stdout.
  out : String?
  /// A CSS entry on disk to compile instead of the embedded one, with its
  /// `@import`s resolved from the filesystem.
  entry : String?
  /// A file of extra candidate class names, one per line — the escape hatch for
  /// names the collector cannot see because the view assembles them at run time.
  extra_classes : String?
  /// Print the collected class names instead of compiling them.
  print_classes : Bool
  /// The compiler's polyfill level, 0..3 (`@tw.POLYFILL_*`).
  polyfills : Int
  /// Compile against Tailwind + margaui rather than Tailwind alone.
  margaui : Bool
} derive(Debug, Eq)

///|
/// Top-level dispatcher: the pure port of main() in tools/tutuca.js.
declare pub fn plan(argv : Array[String]) -> Outcome

///|
/// Parse `gen-views` arguments: finishes purely on help and usage errors,
/// otherwise returns a GenViews outcome for the shell to carry out.
declare fn run_gen_views(args : Array[String], opts : GlobalOpts) -> Outcome

///|
/// Compile view source into the generated MoonBit module (viewgen/), the
/// pure half of `gen-views`. Also runs the view-only lint rules, whose
/// findings come back in `GenPlan.diagnostics`.
declare pub fn gen_views(
  source : String,
  name~ : String,
  input~ : String,
  target~ : String,
  ir~ : Bool,
) -> Result[GenPlan, ErrShape]

///|
/// Parse `watch` arguments: finishes purely on help and usage errors,
/// otherwise returns a Watch outcome for the shell to carry out.
declare fn run_watch(args : Array[String], opts : GlobalOpts) -> Outcome

///|
/// Parse the shared arguments of `gen-tailwind-css` / `gen-margaui-css`:
/// finishes purely on help and usage errors, otherwise returns a GenCss
/// outcome for the shell to carry out.
declare fn run_gen_css(
  args : Array[String],
  opts : GlobalOpts,
  margaui~ : Bool,
) -> Outcome

///|
/// Every literal class name the given (path, source) view files use, sorted
/// and deduped — the file-level twin of `@component.Components::collect_classes`.
/// The pure half of both CSS commands.
declare pub fn collect_view_classes(
  sources : Array[(String, String)],
) -> Result[Array[String], ErrShape]

///|
/// The line the shell prints after writing the CSS.
declare pub fn gen_css_success(
  target : String,
  files~ : Int,
  classes~ : Int,
) -> String

///|
/// `--print-classes` output: one class name per line.
declare pub fn class_list_text(classes : Array[String]) -> String

///|
/// Byte-lexicographic string order — NOT `String`'s own `Compare`, which sorts
/// by length first. Shared with the shell so the class list it merges
/// `--classes` into keeps the same order this produced.
declare pub fn lex_compare(a : String, b : String) -> Int

///|
/// True for a path the watcher should react to; everything else in a watched
/// tree is noise, and reacting to the generated modules would loop.
declare pub fn is_view_path(path : String) -> Bool

///|
/// Where a watched view file's generated module lands, and under what
/// component name — shared with `gen-views` so the two cannot disagree.
declare pub fn watch_target(path : String, out : String?) -> String

///|
declare pub fn watch_name(path : String, name : String?) -> String

///|
/// The generated sibling whose presence marks an .html as gen-views-managed.
declare pub fn watch_sibling(path : String) -> String

///|
/// Split argv into the global flags and the remaining positionals.
declare pub fn extract_globals(
  argv : Array[String],
) -> (GlobalOpts, Array[String])

///|
/// Render an ErrShape to stderr text: plain text, or a one-line JSON
/// envelope under --json.
declare fn render_error(opts : GlobalOpts, shape : ErrShape) -> String

///|
/// ErrShape constructor: exit code 1, everything else absent.
declare pub fn err(
  code : String,
  message : String,
  suggestion? : @lint.Suggestion,
  hint? : String,
  where_? : String,
  exit_code? : Int = 1,
) -> ErrShape

///|
/// Emit for an error: stderr text + the shape's exit code.
declare pub fn error_emit(opts : GlobalOpts, shape : ErrShape) -> Emit

///|
/// Registry lookup by command name.
declare pub fn find_command(name : String) -> CommandSpec?

///|
/// Every command name, in registry (= agent-context) order. Also the
/// did-you-mean candidate list.
declare pub fn command_names() -> Array[String]

///|
/// "Did you mean" suggestion against valid names, using the lint package's
/// Damerau-Levenshtein closest_name.
declare fn did_you_mean(
  name : String,
  candidates : Array[String],
) -> @lint.Suggestion?

///|
/// Human tail line for a suggestion.
declare fn suggestion_to_message(suggestion : @lint.Suggestion?) -> String?

///|
/// Full CLI reference (`tutuca help` with no argument), trailing newline
/// included.
declare pub fn overview() -> String

///|
/// `tutuca help [command]`.
declare fn run_help(target : String?, opts : GlobalOpts) -> Emit

///|
/// The machine-readable schema printed by `tutuca agent-context`
/// (schemaVersion 5), trailing newline included.
declare pub fn agent_context_text() -> String

///|
/// Parse `tutuca feedback`'s own args: -h/--help prints the command help,
/// other flags are rejected, positionals join into the message.
declare fn run_feedback(args : Array[String], opts : GlobalOpts) -> Outcome

///|
/// One feedback.jsonl record line: {"ts":...,"version":...,"message":...}
/// plus trailing newline (tools/cli/commands/feedback.js).
declare pub fn feedback_record_line(
  ts_iso : String,
  version : String,
  message : String,
) -> String

///|
/// (dir, file) under the given home directory: ~/.tutuca and
/// ~/.tutuca/feedback.jsonl.
declare pub fn feedback_paths(home : String) -> (String, String)

///|
/// The ERR_USAGE_MISSING_ARGUMENT error for `tutuca feedback` with no
/// message, pre-rendered for the shell.
declare pub fn feedback_missing_message(opts : GlobalOpts) -> Emit

///|
declare pub fn feedback_success_line(file : String) -> String

///|
/// Epoch milliseconds -> "YYYY-MM-DDTHH:MM:SS.mmmZ", matching JS
/// Date.toISOString().
declare pub fn iso8601_utc(ms : UInt64) -> String
