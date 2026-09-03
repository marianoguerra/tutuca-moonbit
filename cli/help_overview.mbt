// The `tutuca help` reference. One text, because there is one command set.
//
// HAND-WRITTEN, and deliberately so: it restates flags `registry.mbt` already
// declares, but as prose that says when to reach for each one, grouped and
// ordered for a person reading top to bottom. Generated text cannot do that,
// and the attempt would make both worse. So this is the one place a flag is
// written twice on purpose — everything else (dispatch, parsing, the
// `agent-context` schema, `help <command>`) reads the registry.
//
// The cost is that a flag added to the registry does not appear here until
// somebody adds it. `agent_context_test.mbt` pins the registry against this
// text so that stays visible rather than silent.

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
  #|  gen [path...] [--name <Name>] [--out <dir|file>] [--dry-run] [--no-ir]
  #|      Compile .html files of views into companion MoonBit modules of typed
  #|      view surfaces, plus a compiled-tree module beside each. The generated
  #|      files are checked in; regenerate, never edit them. Paths follow the
  #|      same rule as `watch` and the CSS commands — a directory contributes
  #|      the .html files that already have a generated sibling.
  #|
  #|      Pass the whole project when you have one: the checks that span
  #|      components (does the component this view renders exist? does it have
  #|      the view `as=` names?) see exactly the paths you passed, and report
  #|      nothing about a component outside them.
  #|        --name    component name heading the generated types
  #|                  (default: the file's basename). One component, so it is
  #|                  refused with more than one path.
  #|        --out     output directory, or an explicit .mbt path (the .mbt form
  #|                  names one file, so it too is refused for a batch)
  #|        --dry-run print the generated modules instead of writing them
  #|        --no-ir   skip the companion <stem>_view_ir_gen.mbt
  #|
  #|  migrate [path...] [--write]
  #|      Rewrite view files from a retired spelling of the language to the
  #|      current one. A rename lands with the old spelling still parsing for
  #|      one release; this carries a tree across in between. Paths follow the
  #|      same rule as gen.
  #|
  #|      Says what would change and writes nothing without --write. Each line
  #|      is `path:offset  rule  old -> new`, where `rule` names the retirement.
  #|      Every edit replaces a span of the original text, so comments, blank
  #|      lines and alignment come back untouched — nothing here re-serialises a
  #|      declaration. Running it twice is running it once.
  #|        --write   apply the edits (without it nothing on disk is touched)
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
  #|  trace <file> [--trim <n>] [--at <place>] [--compact] [-o <file>]
  #|      Read an execution trace — the state a component tree started in, plus
  #|      every message and intent that crossed the runtime afterwards. With no
  #|      flags it says what is in one: which component, how many events, how
  #|      many of those a rerun would feed, and every address it touched. Run
  #|      that before --at; the places it lists are the ones there is anything
  #|      to cut to.
  #|        --trim    keep the first n events. Slices lines and never reads an
  #|                  event, so a trace holding a kind this build has never
  #|                  heard of shortens just the same.
  #|        --at      cut it down to one subtree and rewrite every address, so
  #|                  `.rows[1]` becomes the root. What a parent sent INTO that
  #|                  subtree survives as an input; what the subtree did for
  #|                  itself stays derived, because a rerun does it again.
  #|        --compact also drop the derived events. Smaller, and the result can
  #|                  no longer be relocated.
  #|      Rebasing — replacing a prefix with the state it produced — is not here
  #|      and cannot be: it means running the app, and a CLI does not have your
  #|      compiled components.
  #|
  #|  watch [path...] [--name <Name>] [--out <dir>] [--no-ir]
  #|        [--tailwind-css <file> | --margaui-css <file>]
  #|        [--css-entry <file>] [--css-classes <file>]
  #|      Re-run gen on every save. Paths are .html files or directories;
  #|      a directory contributes the .html files that already have a generated
  #|      sibling, so pointing it at a project root does not try to compile
  #|      index.html. Defaults to the current directory.
  #|        --tailwind-css / --margaui-css  also rewrite that stylesheet after
  #|                  every settled batch, so a class you just added is styled
  #|                  by the time you reload. Rebuilt over every watched view,
  #|                  once per batch — a stylesheet is a whole-project artifact.
  #|        --css-entry, --css-classes  the CSS commands' --entry / --classes.
  #|                  Pass them here if your build passes them.
  #|
  #|  storybook [dir] [--port <n>] [--out <dir>]
  #|      Serve a pre-built storybook gallery bundle over HTTP (default port
  #|      4321, falling back to a free one), or copy it with --out. A bundle is
  #|      a directory with an index.html and a .wasm beside it, built ahead of
  #|      time by the project's own build script (see new-storybook); this
  #|      command is a static file server and nothing more.
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
  #|  new-storybook <name> [--dir <path>] [--dry-run] [--force]
  #|      Scaffold a storybook gallery of YOUR components: a sidebar of stories
  #|      with a live pane each, and Instance/Trace/Fuzz/Spec inspectors beside
  #|      them. A story is an example on a ModuleDef, so the gallery is a
  #|      projection of your own modules and there is no story list to keep.
  #|      The gallery itself is a library (storybook/ui/wasm); what this writes
  #|      is the page around it — the wasm export list, index.html, build.mjs.
  #|      You need moon and node.
  #|        <name>        kebab-case; becomes the directory and module name
  #|        --dir <path>  write somewhere other than ./<name>/
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
  #|    - `gen` compiles your view files into typed MoonBit. A field that
  #|      does not exist, or an `@on` handler nothing handles, is a BUILD
  #|      error — not a finding you have to remember to go looking for. Point
  #|      it at the whole project and the checks that need two components
  #|      (a missing child view, a read against the wrong child's schema)
  #|      come with it.
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
