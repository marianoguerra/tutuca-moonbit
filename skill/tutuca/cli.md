# Tutuca — CLI Reference (embedded)

The `tutuca` CLI inspects, documents, lints, and renders a module. In the
MoonBit port a native binary cannot load user code, so **user projects
embed the CLI**: the module is a `@component.ModuleDef` **value** compiled
into a project binary whose `main` hands `argv` plus the module to
`@cli.plan_with_module` — there is no path-based module loading. Reach
this file when you need command/flag/exit-code details, or when reading
a lint code out of `lint` output. The post-edit verification recipe is
in [Verifying changes](./core.md#verifying-changes).

## Embed / invoke

The minimal embedding shell (the full version with feedback/stdin lives
in this repo's `cmd/main`; this one is `demo/counter_cli/main.mbt`):

```moonbit
// moon.pkg: import "marianoguerra/tutuca/cli", your module lib,
// "moonbitlang/core/env"; supported_targets = "native"; is-main
fn main {
  let argv = @env.args().iter().drop(1).to_array()
  match @cli.plan_with_module(argv, Some(@mylib.module_def())) {
    Done(emit) => {
      if emit.out != "" { println(emit.out) }
      if emit.err != "" { println(emit.err) }
      process_exit(emit.exit_code)
    }
    Feedback(_, ..) => {
      println("feedback is not supported by this demo binary")
      process_exit(1)
    }
  }
}
```

```sh
moon build --target native            # produces the project's tutuca binary
moon run --target native demo/counter_cli -- list   # or run it in place
```

With an embedded module the command comes **first** and an optional
component name second — no module path:

```sh
tutuca <command> [name] [flags]
```

(`agent-context` still describes the JS-compatible
`tutuca <command> <module-path> [name]` schema with a `module-path`
positional and `--module` flag; the embedded binary ignores the path —
the compiled-in module is the module.) `tutuca help` prints the full
reference; `tutuca help <command>` prints per-command detail
(`tutuca help lint` includes the lint-rule table). Bare `tutuca` / `-h`
prints the overview.

## Commands

Module commands (run against the embedded `ModuleDef`):

| Command                  | Purpose                                                                                                                |
| ------------------------ | ---------------------------------------------------------------------------------------------------------------------- |
| `get`                    | Summarize the module's components and counts                                                                          |
| `list [name] [--limit n]` | List components with their views and fields (name + kind). `--limit n` caps; `0` = all (`truncated: true` in JSON when capped) |
| `examples [--limit n]`   | List the module's `ExampleDef`s. `--limit n` caps total items; `0` = all                                               |
| `show [name]`            | Show API docs for components (methods, input handlers, fields with generated accessors) — all or one                  |
| `lint [name]`            | Run the lint checks (view HTML + component provide/lookup shape); exits **2** on any error-level finding               |
| `render [name] [--title t] [--view v]` | Render examples to HTML headlessly (memdom). Filter by component name or `--title`; `--view` overrides the example's view. Exit **3** is reserved for render crashes |

Plain commands (no module needed):

| Command                  | Purpose                                                                                                                |
| ------------------------ | ---------------------------------------------------------------------------------------------------------------------- |
| `help [cmd]`             | Show usage; `help <command>` for per-command detail                                                                    |
| `feedback [message]`     | Append a feedback note (positional or stdin) to `~/.tutuca/feedback.jsonl`                                             |
| `agent-context`          | Print a versioned JSON schema of every command, flag, exit code, error code, and lint code                             |
| `install-skill`          | Copy a bundled Claude Code skill (this one) into `.claude/skills/` — the skill assets are embedded into the binary by the dev `dist` tooling. Flags: `--user`/`--project`, `--dot-agents`, `--dry-run`, `--force`, `--all`, `--margaui-skill` |

**Not in this port:**

- **`tutuca test` does not exist.** `moon test` is the test runner —
  component tests are `test { ... }` blocks over the `@harness` package
  (see [testing.md](./testing.md)). The exit-4 code from the JS CLI is
  gone with it.
- **`tutuca storybook` serves a pre-built gallery, not scanned `*.dev.js`.**
  The port compiles ahead of time and the native binary can't load user
  code, so there is no runtime `*.dev.js` discovery. Stories are the
  compiled example registry (`storybook/`), grouped into sections and baked
  into a wasm host (`demo/storybook_wasm`) at build time. Build the bundle
  with `moon run --target native cmd/dev -- dist`, then
  `tutuca storybook [dir] [--port <n>] [--out <dir>] [--dry-run [--json]]`
  serves it (static HTTP), copies it (`--out`), or lists the registry
  (`--dry-run`). The per-story Lint panel is the CLI's `check_component`.

## Global flags

```
    --json                       shorthand for `--format=json`. Recommended
                                 for agent/script callers — error envelopes
                                 are also JSON (see "Errors" below)
-f, --format <cli|md|json|html>  output format
                                 defaults: get/list/examples/lint → cli
                                           show/render            → md
                                 html is render-only
                                 json works for every module command
-o, --output <file>              write to file instead of stdout
    --pretty                     pretty-print HTML/JSON output
    --module <path>              alternative to the module-path positional
                                 (schema parity; the embedded module wins)
-h, --help                       show help (overview, or for one command)
```

## Exit codes

| Code | Meaning                                                  |
| ---- | -------------------------------------------------------- |
| `0`  | success                                                  |
| `1`  | usage error (bad args, missing module, bad module shape) |
| `2`  | lint findings at error level (lint command)              |
| `3`  | render crash (render command)                            |

## Errors

Diagnostics carry "did you mean" suggestions for unknown commands and
unknown flags (same shape as lint suggestions). Under `--json`, errors
are emitted as a JSON envelope:

```json
{"error":{"code":"ERR_USAGE_UNKNOWN_FLAG","message":"Unknown flag '--titel'","suggestion":{"kind":"replace-name","from":"--titel","to":"--title"},"hint":"Valid flags: ..."}}
```

Stable error codes (`@cli.error_codes` / the `CODE_*` constants):

| Code                          | When                                          |
| ----------------------------- | --------------------------------------------- |
| `ERR_USAGE_UNKNOWN_COMMAND`   | command name not recognized                   |
| `ERR_USAGE_UNKNOWN_FLAG`      | flag not recognized for the command           |
| `ERR_USAGE_BAD_FLAG_VALUE`    | flag rejected the value (e.g. wrong type)     |
| `ERR_USAGE_MISSING_MODULE`    | command needs a module but none was embedded/given |
| `ERR_USAGE_MISSING_ARGUMENT`  | required positional/stdin missing             |
| `ERR_USAGE_MUTUALLY_EXCLUSIVE`| conflicting flags                             |
| `ERR_FORMAT_UNKNOWN`          | `--format` value not in {cli,md,json,html}    |
| `ERR_FORMAT_UNSUPPORTED`      | format chosen doesn't support the result kind |
| `ERR_MODULE_LOAD_FAILED`      | module input failed (path form; stubbed here) |
| `EXAMPLES_SHAPE_MISMATCH`     | module value had a non-conforming shape       |
| `ERR_INTERNAL`                | a command crashed on the module               |
| `ERR_SKILL_ASSETS_MISSING`    | bundled skill assets not found                |
| `ERR_SKILL_TARGET_EXISTS`     | install-skill target exists; use `--force`    |

## Examples

```sh
tutuca get                              # quick overview of the embedded module
tutuca list                             # components, views, fields
tutuca show Button --json               # one component, JSON
tutuca render -f html --pretty -o out/examples.html
tutuca render Button --title "Disabled state"

# Post-edit verification: lint, then render the example for the feature
# you just changed (add the ExampleDef first if none covers it). Add
# --pretty when you need to read the HTML to verify structure.
tutuca lint
tutuca render --title "Disabled state"
tutuca render --title "Disabled state" --pretty

# Component-behavior verification is moon test, not a CLI command:
moon test
```

## Record feedback

`tutuca feedback` appends a freeform feedback record to
`~/.tutuca/feedback.jsonl` (created on first use). Record a note
whenever the CLI, the bundled skill, this reference, or the library
itself was confusing, broken, or surprising — capture it in the
moment instead of reconstructing it later.

```sh
tutuca feedback "lint code FIELD_VAL_NOT_DEFINED didn't suggest the missing field"
echo "render --pretty differed from -f html --pretty" | tutuca feedback
tutuca feedback < notes.txt
```

Each record is one JSON object per line: `{ts, version, message}`.
Empty input (no positional, no piped stdin) exits **1** with a usage
error. (The `Feedback` outcome needs stdin/filesystem, so minimal
embedding shells may opt out — `cmd/main` has the full handling.)

## Linter Rules

`lint` reports findings at three levels — **error**, **warn**, **hint** —
and exits `2` if any finding is at error level.

The codes are not duplicated here, to keep this file from drifting out of
sync with the implementation. The authoritative, always-current list of
component-linter codes (code, level, one-line description, grouped by
category) is available straight from the CLI:

- `tutuca help lint` — human-readable table.
- `tutuca agent-context` — machine-readable: the `lintCodes` array, each
  entry `{ code, level, group, summary }`.

Categories include field/method references, input-handler ↔ method
confusion, iteration helpers (`alter`), dynamic bindings (`*name`),
template/event issues, value-expression errors, and unregistered names.
Representative codes: `FIELD_VAL_NOT_DEFINED`, `METHOD_VAL_IS_FIELD`,
`ALT_HANDLER_NOT_DEFINED`, `DYN_VAL_NOT_DEFINED`, `UNKNOWN_DIRECTIVE`,
`UNSUPPORTED_EXPR_SYNTAX`.

The rule table is ported verbatim from the JS CLI for parity
(`cli/lint_rules.mbt`), but a few codes are **cataloged and can never
fire in MoonBit** — the conditions they detect are statically impossible
here (the type system rules them out at compile time):
`ASYNC_HANDLER`, `FIELD_NAME_RESERVED_BY_RECORD`, `COMP_FIELD_BAD_SHAPE`,
`UNKNOWN_COMPONENT_SPEC_KEY`, `LOOKUP_BAD_SHAPE`,
`SUGGEST_BINDING_MEMBER`.

`lint` also runs an HTML structural linter (fragment mode) that emits
`HTML_*` codes for malformed or misnested template markup; those are
reported through the same channel. Its messages use WHATWG parser
vocabulary:

- **foster-parenting** — the parser moves content that isn't allowed
  inside a table out in front of it.
- **adoption agency** — the algorithm that reorders misnested formatting
  tags (`<b><i></b></i>`).
- **void element** — an element with no close tag (`<br>`, `<img>`); an
  explicit `</br>` is flagged.
- **insertion mode** — the parser context named in "not allowed in …"
  messages (e.g. "in table body").
- **bogus comment** — malformed markup the parser reinterprets as a
  comment, dropping its content.
