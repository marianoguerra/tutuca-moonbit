// Full CLI reference text, ported verbatim from tools/cli/commands/help.js
// OVERVIEW (the JEST_MATCHERS interpolation is inlined as its rendered
// literal).
//
// GENERATED from `node tools/tutuca.js help` output — regenerate from the JS
// CLI if the reference changes.

///|
let overview_body : String =
  #|tutuca — CLI for inspecting, documenting, linting and rendering tutuca
  #|components defined in an ES module.
  #|
  #|SYNOPSIS
  #|  tutuca <command> <module-path> [name] [flags]
  #|  tutuca help [command]
  #|  tutuca {-h | --help}
  #|
  #|INVOCATION SHAPE
  #|  - <command> comes FIRST. <module-path> is the second positional — a path
  #|    to an ES module resolvable by Node (absolute, or relative to cwd).
  #|    Use --module=<path> as an alternative if the path conflicts.
  #|  - [name] is an OPTIONAL component-name filter. Omit it to operate on all
  #|    components; pass it to operate on exactly one (e.g. `show Button`).
  #|  - Per-command flags follow the module path; global flags can appear
  #|    anywhere. Unknown flags are rejected by the subcommand's parser.
  #|  - `help`, `feedback`, `install-skill`, `storybook`, `agent-context` do NOT
  #|    take a module path.
  #|
  #|MODULE CONVENTION
  #|  A module passed to tutuca must export one or more of:
  #|
  #|    export function getComponents()       // required for all module commands
  #|      -> Component[]                      // results of tutuca's component()
  #|
  #|    export function getExamples()         // required for render
  #|      -> Section | Section[]              // single section or an array
  #|      where Section = { title: string, description?: string,
  #|                        items: Example[] }
  #|      and   Example = { title, description?, value, view? }
  #|      and   value   = an instance returned by <Component>.make(...)
  #|      and   view    = a view name (defaults to "main")
  #|
  #|    export function getMacros()           // optional
  #|      -> Record<string, Macro>            // from tutuca's macro()
  #|
  #|    export function getRequestHandlers()  // optional
  #|      -> Record<string, Function>
  #|
  #|    export function getRoot()             // optional; returned by info
  #|
  #|COMMANDS (require <module-path>)
  #|  get <module>
  #|      Summarize which getX() exports are present and count components,
  #|      macros, request handlers, examples, and sections. Good first step.
  #|
  #|  list <module> [name] [--limit <n>]
  #|      List each component with its declared views and fields (name, type).
  #|      --limit caps the number of components emitted (0 = all). Truncated
  #|      output ends with a "… N more" footer in cli/md, or `truncated:true`
  #|      in JSON.
  #|
  #|  examples <module> [--limit <n>]
  #|      Print the module's example sections: title, description, items.
  #|      Each item shows its resolved component name and view.
  #|      --limit caps the total number of items emitted (0 = all).
  #|
  #|  show <module> [name]
  #|      Show API docs (methods, input handlers, fields with their
  #|      auto-generated accessor/mutator methods) for every component, or
  #|      for the single component whose name matches [name].
  #|
  #|  lint <module> [name]
  #|      Run the built-in component linter. Reports at levels error / warn
  #|      / hint. Exits 2 if ANY finding is at error level.
  #|
  #|  render <module> [name] [--title <t>] [--view <v>]
  #|      Render examples to HTML by running each example value through the
  #|      component tree in a headless DOM. Filters:
  #|        [name]       only examples whose value is an instance of <name>
  #|        --title <t>  only the example with that title
  #|        --view <v>   override the example's view name
  #|      Exits 3 if any render crashes.
  #|
  #|COMMANDS (no module required)
  #|  help [command]
  #|      Without [command]: prints this full reference.
  #|      With [command]: prints that command's one-line description.
  #|
  #|  feedback [message]
  #|      Append a feedback record (one JSON object per line) to
  #|      ~/.tutuca/feedback.jsonl. Use for bugs, confusing messages,
  #|      or suggestions about the CLI, skills, docs, or the library.
  #|      Message comes from the positional arg or piped stdin.
  #|
  #|  storybook [dir] [--port <n>] [--out <dir>] [--dry-run [--json]]
  #|      Serve the pre-built storybook gallery: the compiled example registry,
  #|      grouped into sections, rendered as one interactive WebAssembly app
  #|      (sidebar + live preview + a Lint panel per story). Unlike the JS CLI
  #|      this does NOT scan for *.dev.js — the port compiles ahead of time and
  #|      the native binary can't load user code, so stories are the compiled
  #|      examples baked into the host at build time (see `moon run --target
  #|      native cmd/dev -- dist`).
  #|        [dir]         a pre-built bundle directory to serve
  #|                      (default: the bundle shipped next to the binary)
  #|        --port <n>    preferred port (default 4321; else a free port)
  #|        --out <dir>   copy the static bundle to <dir> instead of serving
  #|        --dry-run     print the compiled story registry (add --json)
  #|
  #|  agent-context
  #|      Print a machine-readable schema of every command, flag, exit code,
  #|      and error code as JSON on stdout. Use this once to teach an agent the
  #|      shape of the CLI; the schema is versioned (schemaVersion field).
  #|
  #|  install-skill [--user | --project] [--margaui-skill | --immutable-skill | --all] [--dot-agents] [--dry-run] [--force]
  #|      Copy bundled Claude Code skill assets into .claude/skills/<name>/.
  #|      Scope: --project (cwd, default) or --user (~/.claude/skills/).
  #|      Selection (default is the tutuca skill):
  #|        --margaui-skill    install the margaui skill instead
  #|        --immutable-skill  install the immutable-js skill instead
  #|        --all              install every bundled skill
  #|      --dot-agents installs into .agents/skills/ instead of .claude/skills/.
  #|      --dry-run prints the files that would be written without touching disk.
  #|      --force overwrites existing files.
  #|
  #|GLOBAL FLAGS
  #|      --json                 Shorthand for `--format=json`. Recommended for
  #|                             agent/script consumers — error envelopes are
  #|                             also emitted as JSON on stderr.
  #|  -f, --format <cli|md|json|html>
  #|      Output format. Defaults per command:
  #|        get, list, examples, lint, test -> cli
  #|        show, render                    -> md
  #|      html is only supported by render.
  #|      json is supported by every command and serializes the result
  #|      class directly — useful for piping into other tools or agents.
  #|
  #|  -o, --output <file>        Write to <file> instead of stdout.
  #|      --pretty               Pretty-print HTML (md/html formats) via
  #|                             prettier; JSON formatter uses indent 2.
  #|  -h, --help                 Show this help.
  #|      --module <path>        Alternative to first-positional module path.
  #|
  #|EXIT CODES
  #|  0   success
  #|  1   usage error (bad args, missing module, bad module shape)
  #|  2   lint findings at error level
  #|  3   render crash
  #|  4   test failures
  #|
  #|ERROR FORMAT
  #|  Diagnostics go to stderr; structured output goes to stdout. Under
  #|  `--json`, errors are emitted as a single-line JSON envelope on stderr:
  #|    {"error":{"code":"ERR_...","message":"...","suggestion":{...},"hint":"..."}}
  #|  Errors include "did you mean" suggestions for unknown commands and flags
  #|  in the same shape as lint suggestions.
  #|
  #|EXAMPLES
  #|  # Inspect a module
  #|  tutuca get ./src/components.js
  #|
  #|  # Machine-readable docs for one component
  #|  tutuca show ./src/components.js Button --json -o docs/button.json
  #|
  #|  # Render every example, pretty-printed HTML to a file
  #|  tutuca render ./src/components.js -f html --pretty -o out/examples.html
  #|
  #|  # Render a single example
  #|  tutuca render ./src/components.js Button --title "Disabled state"
  #|
  #|  # Post-edit verification: lint, then render the example you changed
  #|  tutuca lint ./src/components.js
  #|  tutuca render ./src/components.js --title "Disabled state"

///|
pub fn overview() -> String {
  overview_body + "\n"
}
