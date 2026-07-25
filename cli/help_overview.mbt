// The `tutuca help` reference.
//
// Two texts, because there are two binaries (see registry.mbt). The stock
// overview documents what the shipped `tutuca` can do; the embedded one adds
// the module commands a project binary gets by calling `plan_with_module`.
// The shared tail (global flags, exit codes, error format) is written once.

///|
let stock_head : String =
  #|tutuca — the CLI for tutuca projects: compile views ahead of time, watch
  #|them, serve the storybook gallery, install the Claude Code skill.
  #|
  #|SYNOPSIS
  #|  tutuca <command> [flags]
  #|  tutuca help [command]
  #|  tutuca {-h | --help}
  #|
  #|COMMANDS
  #|  gen-views <file.html> [--name <Name>] [--out <dir|file>] [--dry-run] [--no-ir]
  #|      Compile an .html file of views into a companion MoonBit module of
  #|      typed view surfaces, plus a compiled-tree module beside it. The
  #|      generated files are checked in; regenerate, never edit them.
  #|        --name    component name heading the generated types
  #|                  (default: the file's basename)
  #|        --out     output directory, or an explicit .mbt path
  #|        --dry-run print the generated modules instead of writing them
  #|        --no-ir   skip the companion <stem>_view_ir_gen.mbt
  #|
  #|  watch [path...] [--name <Name>] [--out <dir>] [--no-ir]
  #|      Re-run gen-views on every save. Paths are .html files or directories;
  #|      a directory contributes the .html files that already have a generated
  #|      sibling, so pointing it at a project root does not try to compile
  #|      index.html. Defaults to the current directory.
  #|
  #|  storybook [dir] [--port <n>] [--out <dir>]
  #|      Serve the pre-built storybook gallery bundle over HTTP (default port
  #|      4321, falling back to a free one), or copy it with --out. The gallery
  #|      is a WebAssembly host built ahead of time by
  #|      `moon run --target native cmd/dev -- dist`; this command is a static
  #|      file server and nothing more. Unlike the JS CLI it does NOT scan for
  #|      *.dev.js — the port compiles ahead of time and a native binary cannot
  #|      load user code.
  #|
  #|  install-skill [--user | --project] [--dot-agents] [--dry-run] [--force]
  #|      Write the bundled tutuca Claude Code skill into .claude/skills/tutuca/.
  #|      The assets are compiled into the binary, so this works anywhere.
  #|        --project     install under the cwd (default)
  #|        --user        install under ~/.claude/skills/
  #|        --dot-agents  use .agents/skills/ instead of .claude/skills/
  #|        --dry-run     print the files that would be written
  #|        --force, -f   overwrite existing files
  #|
  #|  feedback [message]
  #|      Append a feedback record (one JSON object per line) to
  #|      ~/.tutuca/feedback.jsonl. Use it for bugs, confusing messages, or
  #|      suggestions about the CLI, the skill, the docs, or the library.
  #|      The message comes from the positional argument or piped stdin.
  #|
  #|  agent-context
  #|      Print a machine-readable schema of this binary's commands, flags,
  #|      exit codes, error codes and lint codes as JSON. Use it once to teach
  #|      an agent the shape of the CLI; the schema is versioned
  #|      (schemaVersion) and reports which command set this binary has (mode).
  #|
  #|  help [command]
  #|      Without [command]: this reference. With one: that command's
  #|      description (`help lint` also prints the lint-rule table).
  #|
  #|INSPECTING YOUR COMPONENTS
  #|  get / list / examples / show / lint / render operate on a module of
  #|  components, and this binary has none: a native binary cannot import user
  #|  code, so there is no module path to pass. Instead a project EMBEDS the
  #|  CLI — build a binary whose main hands its own ModuleDef to
  #|  @cli.plan_with_module:
  #|
  #|      fn main {
  #|        let argv = @env.args().iter().drop(1).to_array()
  #|        match @cli.plan_with_module(argv, Some(@mylib.module_def())) {
  #|          Done(emit) => …
  #|          …
  #|        }
  #|      }
  #|
  #|  demo/counter_cli is the worked example:
  #|      moon run --target native demo/counter_cli -- list
  #|      moon run --target native demo/counter_cli -- help
  #|

///|
let embedded_head : String =
  #|tutuca — inspect, document, lint and render the components compiled into
  #|this binary, and compile their views ahead of time.
  #|
  #|SYNOPSIS
  #|  tutuca <command> [name] [flags]
  #|  tutuca help [command]
  #|  tutuca {-h | --help}
  #|
  #|INVOCATION SHAPE
  #|  - <command> comes FIRST. There is no module path: the module is the
  #|    @component.ModuleDef this binary was built with.
  #|  - [name] is an OPTIONAL component-name filter. Omit it to operate on all
  #|    components; pass it to operate on exactly one (e.g. `show Button`).
  #|  - Per-command flags follow; global flags can appear anywhere. Unknown
  #|    flags are rejected by the subcommand's parser.
  #|
  #|COMMANDS (over the embedded module)
  #|  get
  #|      Summarize the module: its name, its components, and how many
  #|      components and examples it has. Good first step.
  #|
  #|  list [--limit <n>]
  #|      List the module's components. --limit caps how many are emitted
  #|      (0 = all); truncated output is marked with a "… truncated" line, or
  #|      `truncated: true` under --json.
  #|
  #|  examples [name] [--limit <n>]
  #|      List the module's examples as `<component> — <title>`, optionally
  #|      only those of one component. --limit caps the total (0 = all).
  #|
  #|  show [name]
  #|      Show API docs for every component, or for the one named: fields with
  #|      their kinds and defaults, views, provide/lookup wiring, and the
  #|      handler buckets it implements.
  #|
  #|  lint [name]
  #|      Run the component linter (view HTML plus provide/lookup shape) over
  #|      every component or one. Reports findings at error / warn / hint.
  #|      Exits 2 if ANY finding is at error level.
  #|
  #|  render [name] [--title <t>] [--view <v>]
  #|      Render the module's examples to HTML by mounting each one headlessly
  #|      on the in-memory DOM. Filters:
  #|        [name]       only examples of that component
  #|        --title <t>  only the example with that title
  #|        --view <v>   override the example's view name
  #|      Exit 3 is reserved for a render crash.
  #|
  #|  Component BEHAVIOUR is verified with `moon test`, not a CLI command:
  #|  write `test "..." { ... }` blocks against the
  #|  marianoguerra/tutuca/testing/harness package.
  #|
  #|COMMANDS (no module needed)
  #|  gen-views <file.html> [--name <Name>] [--out <dir|file>] [--dry-run] [--no-ir]
  #|      Compile an .html file of views into a companion MoonBit module of
  #|      typed view surfaces, plus a compiled-tree module beside it.
  #|
  #|  watch [path...] [--name <Name>] [--out <dir>] [--no-ir]
  #|      Re-run gen-views on every save.
  #|
  #|  storybook [dir] [--port <n>] [--out <dir>]
  #|      Serve (or copy with --out) the pre-built storybook gallery bundle.
  #|
  #|  install-skill [--user | --project] [--dot-agents] [--dry-run] [--force]
  #|      Write the bundled tutuca Claude Code skill into .claude/skills/.
  #|
  #|  feedback [message]
  #|      Append a feedback record to ~/.tutuca/feedback.jsonl (message from
  #|      the positional argument or piped stdin).
  #|
  #|  agent-context
  #|      Print this binary's command/flag/exit-code schema as JSON.
  #|
  #|  help [command]
  #|      Without [command]: this reference. With one: that command's
  #|      description (`help lint` also prints the lint-rule table).
  #|

///|
/// Global flags, exit codes and the error envelope — identical in both modes.
let shared_tail : String =
  #|GLOBAL FLAGS
  #|      --json                 Shorthand for `--format=json`. Recommended for
  #|                             agent/script consumers — error envelopes are
  #|                             also emitted as JSON on stderr.
  #|  -f, --format <cli|md|json|html>
  #|      Output format for the module commands. Defaults per command:
  #|        get, list, examples, lint -> cli
  #|        show, render              -> md
  #|      html is render-only; json works for every module command.
  #|
  #|  -o, --output <file>        Write to <file> instead of stdout.
  #|      --pretty               Pretty-print HTML/JSON output.
  #|  -h, --help                 Show help.
  #|
  #|EXIT CODES
  #|  0   success
  #|  1   usage error (bad args, missing module, bad module shape)
  #|  2   lint findings at error level      (module commands only)
  #|  3   render crash                      (module commands only)
  #|
  #|ERROR FORMAT
  #|  Diagnostics go to stderr; structured output goes to stdout. Under
  #|  `--json`, errors are emitted as a single-line JSON envelope on stderr:
  #|    {"error":{"code":"ERR_...","message":"...","suggestion":{...},"hint":"..."}}
  #|  Errors include "did you mean" suggestions for unknown commands and flags
  #|  in the same shape as lint suggestions.
  #|

///|
pub fn overview(mode : CliMode) -> String {
  let head = match mode {
    Stock => stock_head
    Embedded => embedded_head
  }
  head + "\n" + shared_tail + "\n"
}
