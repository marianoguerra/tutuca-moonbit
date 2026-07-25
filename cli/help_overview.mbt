// The `tutuca help` reference. One text, because there is one command set.

///|
let overview_body : String =
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
  #|  gen-tailwind-css [path...] [-o <file>] [--entry <file>] [--classes <file>]
  #|                   [--print-classes] [--polyfills <0..3>]
  #|  gen-margaui-css  [path...] (same flags)
  #|      Compile the classes a project's views use into CSS: gen-tailwind-css
  #|      against stock Tailwind, gen-margaui-css against Tailwind + margaui's
  #|      component layers. Paths follow the same rule as `watch` — a directory
  #|      contributes the .html files that already have a generated sibling —
  #|      and default to the current directory. The stylesheets are compiled
  #|      into the binary; no Node, no CDN, no checkout.
  #|        -o, --out       write the CSS here (default: stdout)
  #|        --entry         compile this CSS entry instead of the embedded one,
  #|                        resolving its @imports from disk
  #|        --classes       extra candidate class names, one per line
  #|        --print-classes print the collected classes instead of the CSS
  #|        --polyfills     0=none, 1=@property, 2=color-mix, 3=all (default 3)
  #|
  #|      Only LITERAL class names are collected, the same limit a running host
  #|      has: a name the view assembles at run time (`:class="$'bg-{.color}'"`)
  #|      is not in the source to be found. --print-classes shows what was
  #|      collected; --classes adds back what was not.
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
  #|      file server and nothing more.
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
  #|      Print a machine-readable schema of the commands, flags, exit codes
  #|      and error codes as JSON. Use it once to teach an agent the shape of
  #|      the CLI; the schema is versioned (schemaVersion).
  #|
  #|  help [command]
  #|      Without [command]: this reference. With one: that command's
  #|      description.
  #|
  #|WHERE THE CHECKS ARE
  #|  There is no `lint`, `render`, `show`, `list`, `get` or `examples`
  #|  command, and no way to point this binary at a module. That is not a
  #|  missing feature — tutuca-mb compiles ahead of time, so those questions
  #|  are answered earlier, and more strictly, than a CLI could:
  #|
  #|    - `gen-views` compiles your view file into typed MoonBit. A field that
  #|      does not exist, or an `@on` handler nothing handles, is a BUILD
  #|      error — not a finding you have to remember to go looking for.
  #|    - `moon check` type-checks every handler against its state struct.
  #|    - `moon test` runs component behaviour through the real event
  #|      pipeline; mount and drive a module with the
  #|      marianoguerra/tutuca/testing/harness package.
  #|    - `moon run --target native cmd/dev -- dist` builds the storybook and
  #|      `tutuca storybook` serves it, to look at components rendered.
  #|
  #|GLOBAL FLAGS
  #|      --json                 Emit errors as a single-line JSON envelope on
  #|                             stderr. Recommended for agent/script callers.
  #|  -h, --help                 Show help.
  #|
  #|EXIT CODES
  #|  0   success
  #|  1   usage error, or a command failed
  #|
  #|ERROR FORMAT
  #|  Diagnostics go to stderr; command output goes to stdout. Under `--json`,
  #|  errors are emitted as a single-line JSON envelope on stderr:
  #|    {"error":{"code":"ERR_...","message":"...","suggestion":{...},"hint":"..."}}
  #|  Errors include "did you mean" suggestions for unknown commands and flags.
  #|

///|
pub fn overview() -> String {
  overview_body + "\n"
}
