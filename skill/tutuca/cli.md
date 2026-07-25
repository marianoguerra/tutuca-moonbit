# Tutuca — CLI Reference

The `tutuca` CLI does the work that happens **outside** the compiler:
generating view modules, watching them, serving the pre-built storybook, and
installing this skill. Reach this file for command/flag/exit-code details.

## What this CLI does NOT do, and why

There is no `get`, `list`, `examples`, `show`, `lint` or `render`, and no way
to point the binary at a module. tutuca-mb compiles ahead of time, so the
questions a run-time CLI would answer are answered earlier, and more strictly:

| You want to know | Where it is answered |
| ---------------- | -------------------- |
| does this view reference a field that exists? | `gen-views` — it generates `counter_fields`, and an unknown `.field` fails generation |
| is every `@on` handler handled? | `gen-views` + `moon check` — `update` matches a generated `CounterMsg`, so an unhandled handler is a **build error** |
| does the handler compile against the state? | `moon check` — state is a plain struct; `s.cuont` does not compile |
| does the component behave? | `moon test` over `@harness` — mount it, fire real events, read the DOM back → [testing.md](./testing.md) |
| what does it look like? | `cmd/dev -- dist` then `tutuca storybook` |

So the post-edit loop is `gen-views` (or leave `tutuca watch` running) →
`moon check` → `moon test`. If you find yourself wanting a CLI command to
inspect a component, the answer is a `moon test` block.

## Commands

| Command                  | Purpose                                                                                                                |
| ------------------------ | ---------------------------------------------------------------------------------------------------------------------- |
| `gen-views <file.html>`  | Compile an `.html` file of views into a companion MoonBit module of typed view surfaces. Flags: `--name <Name>`, `--out <dir-or-file>`, `--dry-run`, `--no-ir`. See below |
| `gen-tailwind-css [path...]` | Compile the classes a project's views use into CSS, against stock Tailwind. Flags: `-o/--out <file>`, `--entry <file>`, `--classes <file>`, `--print-classes`, `--polyfills <0..3>`. See below |
| `gen-margaui-css [path...]` | The same, against Tailwind **+ margaui**'s component layers (`btn`, `card`, `stat`, …) |
| `watch [path...]`        | Regenerate view modules on every save. Paths are `.html` files or directories (which contribute the `.html` files that already have a generated sibling). Flags: `--name`, `--out`, `--no-ir`, and `--tailwind-css`/`--margaui-css` (+ `--css-entry`, `--css-classes`) to keep a stylesheet current too |
| `storybook [dir]`        | Serve (or copy with `--out <dir>`) the pre-built storybook gallery bundle over HTTP. Flags: `--port <n>`, `--out <dir>`. A static file server: the gallery is a wasm host built by `cmd/dev -- dist` |
| `install-skill`          | Copy this skill into `.claude/skills/` — the assets are compiled into the binary by the dev `skill-embed` task. Flags: `--user`/`--project`, `--dot-agents`, `--dry-run`, `--force` |
| `feedback [message]`     | Append a feedback note (positional or stdin) to `~/.tutuca/feedback.jsonl`                                             |
| `agent-context`          | Print a versioned JSON schema of every command, flag, exit code and error code |
| `help [cmd]`             | Show usage; `help <command>` for per-command detail                                                                    |

### `gen-views` — ahead-of-time views

Optional. Keeps a component's views in an `.html` file instead of a MoonBit
string literal, and turns the view's vocabulary into types:

```sh
tutuca gen-views demo/counterlib/counter.html --name Counter
# -> demo/counterlib/counter_view_gen.mbt   (checked in; regenerate, never edit)
```

One view file per MoonBit module, not per component — template ids say what
each one is:

| id | |
|---|---|
| *(none)* | the single unnamed component's `main` view |
| `row` | …its `row` view |
| `Counter:main` | the `Counter` component's `main` view |
| `Counter` | shorthand for `Counter:main` |
| `macro:icon` | a macro shared by every component in the file |

A component name is Uppercase-initial, which is what tells `Counter` (a
component) from `row` (a view); a file either names its components or does
not. A macro's `data-*` attributes are the defaults for its body's `^var`
references, and calls are expanded at generation time — so macros belong in
the view file rather than being registered from MoonBit, which no generator
could expand.

A `<style>` inside a template is that view's style; one at file level is the
first component's common style, or the global style with `data-global`. A
view that would emit a parse issue at runtime fails generation instead.

While authoring, `tutuca watch` keeps the modules current on every save
instead of making you remember to regenerate.

For `--name Counter` the module declares `counter_views()` /
`counter_common_style` / `counter_global_style` (feed straight into
`component()` as `views~` / `common_style~` / `global_style~`),
`CounterInput` + `CounterMsg` with `CounterMsg::from_dispatch` (payload types
inferred from the argument shapes at the `@on` call sites: `add 1` ->
`Add(Double)`, `setLabel value` -> `SetLabel(String)`, anything unresolvable
-> `@tutuca.Value`), `CounterMethod` + `counter_mutate`/`_compute`/`_swap`
(the `$`-callables, built from an exhaustive match), `CounterView`,
`CounterId`, and `counter_fields` / `counter_missing_fields`.

`update` then pattern-matches typed messages, so adding an `@on` handler to
the `.html` and regenerating breaks the build until it is handled, instead of
falling into a silent `_ => None`. Handlers served by the auto-generated
field mutators return `None` and fall through to them, as before. The
generated package must import `"marianoguerra/tutuca/core" @tutuca`,
`"marianoguerra/tutuca/component"` and `"moonbitlang/core/debug"`.

Caveat on `counter_fields`: it lists only fields read at a view's ROOT scope.
A `.field` under an `@each`, `@enrich-with`, push-view or `<x render>`
addresses the loop item or the child component, so it is not listed. Use it in
a test (`assert_eq(counter_missing_fields(init), [])`), not as a startup
check; fields declared through `specs~` go in `extra~`.

**Not in this port:**

- **`tutuca test` does not exist.** `moon test` is the test runner —
  component tests are `test { ... }` blocks over the `@harness` package
  (see [testing.md](./testing.md)). The exit-4 code from the JS CLI is
  gone with it.
- **`tutuca lint` does not exist.** View checking happens at generation
  time (`gen-views` fails on a view that would emit a parse issue), and
  everything else the JS linter checked — undefined fields, unimplemented
  `$`-methods, bad handler names — is a type error in the generated view
  module. There is no run-time linter and no lint-code table.
- **`tutuca storybook` serves a pre-built gallery, not scanned `*.dev.js`.**
  The port compiles ahead of time and the native binary can't load user
  code, so there is no runtime `*.dev.js` discovery. Stories are the
  compiled example registry (`storybook/`), grouped into sections and baked
  into a wasm host (`demo/storybook_wasm`) at build time. Build the bundle
  with `moon run --target native cmd/dev -- dist`, then
  `tutuca storybook [dir] [--port <n>] [--out <dir>]` serves it (static
  HTTP) or copies it (`--out`).

### `gen-tailwind-css` / `gen-margaui-css` — build-time CSS

The class set a running host collects before injecting a `<style>`, collected
from the view **files** instead — so an ahead-of-time project ships a stylesheet
holding only the utilities it actually uses.

```sh
tutuca gen-margaui-css src/ -o public/app.css
```

Paths are `.html` files or directories, and follow `watch`'s rule: a directory
contributes the `.html` files that already have a generated sibling, so pointing
this at a project root does not try to compile `index.html`. Defaults to the
current directory. The stylesheets are compiled into the binary — no Node, no
CDN, no checkout. The two commands differ only in which stylesheets the classes
compile against; `gen-margaui-css` output is a superset of `gen-tailwind-css`
for the same views.

Only **literal** class names are collected, the same limit the runtime collector
has: a name the view assembles at run time (`:class="$'bg-{.color}'"`, or
anything a handler computes) is not in the source to be found.

- `--print-classes` prints what was collected, one per line, instead of the CSS.
  Start here when a style is missing. Note that `$'badge badge-{.kind}'`
  contributes its literal prefix `badge-` — a stub that compiles to nothing, not
  the real name.
- `--classes <file>` adds candidates from a file, one per line, for exactly
  those names.
- `--entry <file>` compiles your own CSS entry instead of the embedded one,
  resolving its `@import`s from disk — use it for a project theme, `@source`
  directives or custom utilities.
- `--polyfills <0..3>` — 0=none, 1=`@property`, 2=`color-mix`, 3=all (default).

### `watch --margaui-css` — keep the stylesheet current too

The full authoring loop in one process: view modules regenerate on save, and the
stylesheet is rewritten with them.

```sh
tutuca watch src/ --margaui-css public/app.css
```

`--tailwind-css` is the same for stock Tailwind; the two are alternatives, the
same choice the two CSS commands make. `--css-entry` and `--css-classes` are the
CSS commands' `--entry` / `--classes` — pass them here if your build passes
them, or watch will write a stylesheet that differs from the one you ship.
Polyfills are always the default (3).

The stylesheet is rebuilt over **every** watched view, once per settled batch —
not per changed file. It is a whole-project artifact, so a class you delete has
to leave it too, and compiling is the expensive half of the loop. A view that
will not parse is reported once by the regeneration pass and leaves the previous
stylesheet in place; the next save fixes it.

## Global flags

```
--json       emit errors as a single-line JSON envelope on stderr
             (recommended for agent/script callers)
-h, --help   show help (the overview, or one command's detail)
```

There is no `--format`, `--output`, `--pretty` or `--module`: no command
emits a structured result to format, and nothing loads a module from a path.

## Exit codes

| Code | Meaning                              |
| ---- | ------------------------------------ |
| `0`  | success                              |
| `1`  | usage error, or the command failed   |

## Errors

Diagnostics carry "did you mean" suggestions for unknown commands and
unknown flags. Under `--json`, errors are emitted as a JSON envelope:

```json
{"error":{"code":"ERR_USAGE_UNKNOWN_FLAG","message":"Unknown flag '--titel'","suggestion":{"kind":"replace-name","from":"--titel","to":"--title"},"hint":"Valid flags: ..."}}
```

Stable error codes (`@cli.error_codes` / the `CODE_*` constants):

| Code                          | When                                          |
| ----------------------------- | --------------------------------------------- |
| `ERR_USAGE_UNKNOWN_COMMAND`   | command name not recognized                   |
| `ERR_USAGE_UNKNOWN_FLAG`      | flag not recognized for the command           |
| `ERR_USAGE_BAD_FLAG_VALUE`    | flag rejected the value (e.g. wrong type)     |
| `ERR_USAGE_MUTUALLY_EXCLUSIVE`| conflicting flags                             |
| `ERR_USAGE_MISSING_ARGUMENT`  | required positional/stdin missing             |
| `ERR_VIEW_GEN_FAILED`         | gen-views could not compile the view file     |
| `ERR_SKILL_ASSETS_MISSING`    | bundled skill assets not found                |
| `ERR_SKILL_TARGET_EXISTS`     | install-skill target exists; use `--force`    |
| `ERR_INTERNAL`                | a command crashed                             |

## Examples

```sh
# The authoring loop
tutuca gen-views src/counter.html --name Counter
tutuca watch src/                 # …or leave this running instead

# Verification is the compiler and the test runner, not the CLI
moon check
moon test

# Look at components
moon run --target native cmd/dev -- dist
tutuca storybook
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
