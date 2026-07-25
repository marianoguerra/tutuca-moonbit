// Spec for the CLI core: pure port of the tutuca CLI's dispatch layer
// (tools/tutuca.js) plus the three commands that need no value/component
// layer (help, agent-context, feedback). Everything module-shaped is a stub
// (see registry.mbt for the per-command blockers). READONLY by convention:
// concrete public data types plus `declare` stubs; implementations live in
// separate files.
//
// The core is deliberately I/O-free: `plan(argv)` returns an `Outcome` and
// the native shell (cmd/main) writes stdout/stderr, reads stdin, touches the
// filesystem and exits. This keeps the core testable on any target.

///|
/// Which command set the running binary has. The stock `tutuca` binary is
/// `Stock`; a project binary that compiles its `ModuleDef` in and calls
/// `plan_with_module` is `Embedded` and additionally has the module commands.
/// Everything user-visible that differs between the two — `help`,
/// `agent-context`, the unknown-command error — takes this rather than
/// guessing.
pub(all) enum CliMode {
  Stock
  Embedded
} derive(Debug, Eq)

///|
/// Global flags extracted before command dispatch (tools/tutuca.js
/// extractGlobals, minus `--module`: nothing here loads a module from a path).
pub(all) struct GlobalOpts {
  format : String?
  output : String?
  pretty : Bool
  help : Bool
} derive(Debug, Eq)

///|
/// A coded CLI error (tools/cli/errors.js emitError shape). Rendering is
/// format-aware: plain text, or a single-line JSON envelope under --json.
pub(all) struct ErrShape {
  code : String
  message : String
  suggestion : @lint.Suggestion?
  hint : String?
  where_ : String?
  exit_code : Int
} derive(Debug, Eq)

///|
/// Flag metadata for help + the agent-context schema (mirrors the flag
/// objects in tools/cli/commands/_no-module.js and agent-context.js).
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
/// Every registered command is runnable in the mode that registers it, so
/// there is no "implemented?" flag: `needs_module` says which set it belongs
/// to and that is the whole story.
pub(all) struct CommandSpec {
  name : String
  describe : String
  needs_module : Bool
  needs_env : Bool
  default_format : String?
  flags : Array[FlagSpec]
  positionals : Array[PositionalSpec]
} derive(Debug, Eq)

///|
/// One row of the component-linter rule table (tools/core/lint-rules.js),
/// emitted as JSON by `agent-context` and as a grouped text table by
/// `tutuca help lint`.
pub(all) struct LintRule {
  code : String
  level : String
  group : String
  summary : String
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
/// Port of extractGlobals (tools/tutuca.js). Returns the parsed globals and
/// remaining positionals; on an unknown --format value returns the opts too
/// so the error can be rendered format-aware.
declare pub fn extract_globals(
  argv : Array[String],
) -> Result[(GlobalOpts, Array[String]), (GlobalOpts, ErrShape)]

///|
/// Render an ErrShape to stderr text (tools/cli/errors.js emitError, minus
/// the exit): plain text, or a one-line JSON envelope when format is json.
declare fn render_error(opts : GlobalOpts, shape : ErrShape) -> String

///|
/// ErrShape constructor with emitError's defaults (exit code 1, everything
/// else absent).
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
/// The commands a binary in `mode` has, in agent-context order.
declare fn commands_for(mode : CliMode) -> Array[CommandSpec]

///|
/// Registry lookup by command name, within a mode's command set.
declare pub fn find_command(mode : CliMode, name : String) -> CommandSpec?

///|
/// A mode's command names in registry (= agent-context) order.
declare pub fn command_names(mode : CliMode) -> Array[String]

///|
/// True for a command only a module-embedding binary has.
declare fn is_module_command(name : String) -> Bool

///|
/// Every name the CLI knows in either mode — the did-you-mean candidates.
declare fn all_command_names() -> Array[String]

///|
/// "Did you mean" suggestion against valid names, using the lint package's
/// Damerau-Levenshtein closest_name.
declare fn did_you_mean(
  name : String,
  candidates : Array[String],
) -> @lint.Suggestion?

///|
/// Port of suggestionToMessage (tools/format/lint.js): human tail line for a
/// suggestion.
declare fn suggestion_to_message(suggestion : @lint.Suggestion?) -> String?

///|
/// Full CLI reference for `mode` (`tutuca help` with no argument), including
/// trailing newline.
declare pub fn overview(mode : CliMode) -> String

///|
/// `tutuca help [command]` for `mode`.
declare fn run_help(mode : CliMode, target : String?, opts : GlobalOpts) -> Emit

///|
/// The machine-readable schema printed by `tutuca agent-context`
/// (schemaVersion 4), including trailing newline. It describes the command
/// set the RUNNING binary has, so an agent reading it never sees a command it
/// cannot invoke.
declare pub fn agent_context_text(mode : CliMode) -> String

///|
/// The error a stock binary gives for a module command: the command is real,
/// this binary just has no module to run it against.
declare fn needs_embedded_module(name : String, opts : GlobalOpts) -> Emit

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

///|
/// The dispatcher for a binary that COMPILED A MODULE IN — the MoonBit
/// module-input answer: a native binary cannot load user code, so a user
/// project embeds the CLI by building a main that calls this with its own
/// `ModuleDef` (demo/counter_cli is the worked example). It runs the whole
/// `Embedded` command set: the module commands against `module_`, everything
/// stock exactly as `plan` does. With None this is exactly `plan`.
declare pub fn plan_with_module(
  argv : Array[String],
  module_ : @component.ModuleDef?,
) -> Outcome
