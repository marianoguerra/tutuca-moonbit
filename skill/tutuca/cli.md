# Tutuca — CLI Reference

The `tutuca` CLI does the work that happens **outside** the compiler:
generating view modules, watching them, serving the pre-built storybook, and
installing this skill. Reach this file for command/flag/exit-code details.

## Install

```sh
moon install marianoguerra/tutuca/cmd/tutuca
```

`moon install` names the binary after the package's last segment, so this
installs `tutuca` into `~/.moon/bin/` — already on your PATH from the MoonBit
toolchain. `tutuca help` confirms it.

## What this CLI does NOT do, and why

There is no `get`, `list`, `examples`, `show`, `lint` or `render`, and no way
to point the binary at a module. tutuca-mb compiles ahead of time, so the
questions a run-time CLI would answer are answered earlier, and more strictly:

| You want to know | Where it is answered |
| ---------------- | -------------------- |
| does this view reference a field that exists? | `gen` — the `<script type="tutuca/spec">` schema declares the fields, and an unknown `.field` fails generation, inside a loop as well as at the root — including a loop over CHILD components, whose fields are checked against that child's schema |
| does the component this view renders have the view `as=` names? | `gen` over the whole project (`tutuca gen src/`) — a miss silently falls back to that component's `main` view at run time, and only a run that can see both components can say so. Reported as a hint, because a slot declared as the bare `component` marker takes its component from `component()`'s `slots~` — MoonBit the generator cannot see |
| does this `@show` decide anything? | `gen` — a list or a record is always truthy, so `@show=".items"` never hides; it fails generation and names `empty? .items` as the fix |
| is this `id=` unique? | `gen` — an `id` inside an `@each` is stamped on every item, which only the compiled tree can see |
| is every `@on` handler handled? | `gen` + `moon check` — `update` matches a generated `CounterMsg`, so an unhandled handler is a **build error** |
| does the handler compile against the state? | `moon check` — state is a plain struct; `s.cuont` does not compile |
| does the component behave? | `moon test` over `@harness` — mount it, fire real events, read the DOM back → [testing.md](./testing.md) |
| what does it look like? | a gallery of your own components: `tutuca new-storybook`, then `node build.mjs && tutuca storybook dist` → [storybook.md](./storybook.md) |

So the post-edit loop is `gen` (or leave `tutuca watch` running) →
`moon check` → `moon test`. If you find yourself wanting a CLI command to
inspect a component, the answer is a `moon test` block.

## Commands

| Command                  | Purpose                                                                                                                |
| ------------------------ | ---------------------------------------------------------------------------------------------------------------------- |
| `gen [path...]`  | Compile `.html` files of views into companion MoonBit modules of typed view surfaces. Paths are files or directories (a directory contributes the `.html` files that already have a generated sibling). Flags: `--name <Name>`, `--out <dir-or-file>`, `--dry-run`, `--no-ir`. See below |
| `gen-tailwind-css [path...]` | Compile the classes a project's views use into CSS, against stock Tailwind. Flags: `-o/--out <file>`, `--entry <file>`, `--classes <file>`, `--print-classes`, `--polyfills <0..3>`. See below |
| `gen-margaui-css [path...]` | The same, against Tailwind **+ margaui**'s component layers (`btn`, `card`, `stat`, …) |
| `watch [path...]`        | Regenerate view modules on every save. Paths are `.html` files or directories (which contribute the `.html` files that already have a generated sibling). Flags: `--name`, `--out`, `--no-ir`, and `--tailwind-css`/`--margaui-css` (+ `--css-entry`, `--css-classes`) to keep a stylesheet current too |
| `storybook [dir]`        | Serve (or copy with `--out <dir>`) a pre-built gallery bundle over HTTP — a directory with an `index.html` and a `.wasm` beside it. Flags: `--port <n>` (default 4321, falling back to a free port), `--out <dir>`. A static file server; the gallery itself is a wasm page built from the project's own modules |
| `new-storybook <name>`   | Scaffold that page: a gallery of your own components, one story per example a module declares. Writes the wasm export list, `index.html` and `build.mjs` — the parts a library cannot supply. Flags: `--dir <path>`, `--dry-run`, `--force`. Needs moon + node. See [storybook.md](./storybook.md) |
| `trace [file]`           | Read an execution trace, trim it, or cut it down to one component. Flags: `--trim <n>`, `--at <path>`, `-o/--out <file>`, `--compact`. See [tracing.md](./tracing.md) |
| `install-skill`          | Copy this skill into `.claude/skills/` — the assets are compiled into the binary. Flags: `--user`/`--project`, `--dot-agents`, `--dry-run`, `--force` |
| `feedback [message]`     | Append a feedback note (positional or stdin) to `~/.tutuca/feedback.jsonl`                                             |
| `agent-context`          | Print a versioned JSON schema of every command, flag, exit code and error code |
| `help [cmd]`             | Show usage; `help <command>` for per-command detail                                                                    |

### `gen` — ahead-of-time views

Optional. Keeps a component's views in an `.html` file instead of a MoonBit
string literal, and turns the view's vocabulary into types:

```sh
tutuca gen demo/counterlib/counter.html --name Counter
# -> demo/counterlib/counter_view_gen.mbt   (checked in; regenerate, never edit)

tutuca gen src/            # the whole project, in one invocation
```

**Pass the whole project when you have one.** Two checks need more than one
component's schema, and they see exactly the paths you passed:

- `<x render=".slot" as="edit">` where the child has no `edit` view. At run time
  the name falls back to the child's `main` view, so the site renders the
  **wrong view** and says nothing about it. Reported as a
  hint rather than an error, because a slot declared as the bare `component`
  marker takes its component from `component()`'s `slots~` — MoonBit the
  generator cannot see.
- `.field` and `@value.member` inside a loop over `Array[Todo]`, checked against
  the **Todo** component's schema rather than skipped.

A component outside the paths you passed is unknown, and unknown is never
reported as wrong — so `tutuca gen one.html` still works and simply
checks less. `--name` and an `--out` ending in `.mbt` each name ONE thing, so
both are refused with more than one path.

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
`CounterMsg` with `CounterMsg::from_dispatch` and `CounterMsg::to_dispatch`
— every addressed name, the schema's `message` cases and the views' `@on`
handlers in one bucket, typed by the schema where it says anything and
otherwise (payload types
inferred from the argument shapes at the `@on` call sites: `add 1` ->
`Add(Double)`, `setLabel e.value` -> `SetLabel(String)` — `e.value` becomes
`Bool` on a checkbox and `@tutuca.Value` on a file input, per the host
element's static `type` — anything unresolvable
-> `@tutuca.Value`) — and `CounterCompute`, the `$`-callables the views name
that a block has NOT already answered. A `compute` in
`<script type="tutuca/script">`, and a `pred` or an `invariant` in
`<script type="tutuca/spec">`, are merged into the bucket ahead of your match,
so an arm for one could never run and its name is dropped from the enum, with a
note on the enum saying which names went; a bucket the blocks answer entirely
emits no enum at all. The same holds for `CounterWhen`, `CounterEnrich` and
`CounterEnrichScope`. A file that also carries
a `<script type="tutuca/spec">` block gets the state half: `CounterState`
(a plain struct — no derives), `CounterState::zero()`, an
`impl @component.Fields for CounterState` carrying the whole contract as
static metadata plus the direct encode/decode, and a typed
`CounterMsg`/`CounterIntent` for each message bucket the
schema declares.

The field names, their declared kinds, the view names, the constant element
ids, the fixture names and the schema fingerprint are all in that one
descriptor — `SchemaInfo` — and not also in enums beside it. That is where the
inspector and the state editor read them from, holding a bare `@tutuca.Value`
and no component registry, which is the only place they CAN be read from; a
typed enum can only be read by code that already knows the component's type,
and such code can spell the name directly.

Schema **and** templates together also get `counter_component(...)`, beside
`counter_views()` in the IR module: `component()` with the name, the views,
the styles and the views already filled in, leaving the handlers.
Call it instead of `@component.component(...)` — a fact the generator learns
then reaches the component by regenerating rather than by editing every call
site. `name`, `views`, `init` and the styles stay overridable; the codec and
the schema are not parameters.

`update` then pattern-matches typed messages, so adding an `@on` handler to
the `.html` and regenerating breaks the build until it is handled, instead of
falling into a silent `_ => Unhandled`. Handlers served by the auto-generated
field mutators return `None` and fall through to them, as before.

The generated package must import `"marianoguerra/tutuca/core" @tutuca`,
`"marianoguerra/tutuca/component"` and `"moonbitlang/core/debug"` — plus
`"marianoguerra/tutuca/anode"` unless you pass `--no-ir`, since the IR module
spells `@anode.View` directly. Each generated file's header repeats the list it
needs.

The schema goes in a `<script>` and not a `<template>`, because script
content is raw text to an HTML parser and template content is markup — a
`Array[Int]` inside a template would be read as an `<Int>` element.

A component with no schema block gets the view half only — no state type, no
codec and no descriptor. There is no weaker substitute: a schema-backed
component checks every read at
generation time, loop bodies included, so the answer to a file without one is
to declare the schema.

### The state schema

A view file may declare its component's data contract in a small language,
alongside the templates that read it. That language — every field spelling, the
mutators each kind generates, message buckets, slots, declared `$`-callables,
schema-only files and `tutuca/fixtures` fixtures — is
[schema.md](./schema.md).

`gen` checks every `.field` read in every view against it, loop bodies and
child components included, and a read of a name the schema lacks fails
generation.

### `gen` diagnostics

Every check `gen` runs reports on one of two channels, and both are worth
recognizing on sight.

**Generation errors** stop the run and name the fix. Beyond the unknown-field and
unknown-handler errors above:

| Error | Means |
| ----- | ----- |
| `NotIterable` | `@each` needs a collection, but the expression is a scalar |
| `NotRenderable` | `<x render>` needs a component, but the field is not a slot |
| `MethodInEventPosition` | a `$name` in an `@on` position; write it bare |

**Lint findings** are printed one per line, as
`CODE (level) <Component>/<view>: message` — for example
`HTML_TAG_NOT_ALLOWED_IN_PARENT (error) Counter/main: <div> is not allowed in <tr>`.
Levels are `error`, `warning` and `hint`. The linter is real and it runs **inside
`gen`**; what does not exist is a separate `tutuca lint` command to invoke
it with.

The codes fall into four families:

- **Directive rules** — `UNKNOWN_DIRECTIVE`, `UNKNOWN_X_OP`, `UNKNOWN_X_ATTR`,
  `BAD_VALUE`, `UNSUPPORTED_EXPR_SYNTAX`, `BINDING_MEMBER_TOO_DEEP`,
  `X_OP_IGNORES_CHILDREN`, `LOOP_DIRECTIVE_ON_X_OP`. The last one is the only
  parse issue that DROPS the node it is about (see
  [iteration.md](./iteration.md)).
- **Nudges** — `MAYBE_ADD_AT_PREFIX`, `MAYBE_DROP_AT_PREFIX`.
- **Event paths** — `EVENT_PATH_UNSAFE_STEP`: an `e.<path>` handler argument
  traverses a step off the allowlist (`e.target.form.action`). It still
  resolves in your own views; the hint exists because a host compiling
  guest-supplied views refuses that bundle over the same step.
- **Structural HTML**, from a WHATWG tokenizer pass over the view text:
  `HTML_TAG_NOT_ALLOWED_IN_PARENT`, `HTML_TEXT_NOT_ALLOWED_IN_PARENT`,
  `HTML_VOID_ELEMENT_HAS_CLOSE_TAG`, `HTML_UNEXPECTED_END_TAG`,
  `HTML_UNCLOSED_BEFORE_END`, `HTML_MISNESTED_FORMATTING`,
  `HTML_NESTED_INTERACTIVE`, `HTML_DUPLICATE_FORM`, `HTML_DUPLICATE_ATTRIBUTE`,
  `HTML_ATTRIBUTES_ON_END_TAG`, `HTML_SELF_CLOSING_END_TAG`,
  `HTML_MISSING_ATTRIBUTE_VALUE`, `HTML_BOGUS_COMMENT`,
  `HTML_CDATA_IN_HTML_NAMESPACE`, `HTML_TAG_NAME_HAS_UPPERCASE`,
  `HTML_SVG_TAG_WILL_LOWERCASE`, `HTML_SVG_ATTR_WILL_LOWERCASE`,
  `HTML_MATHML_ATTR_WILL_LOWERCASE`.

A **void element** is one HTML gives no closing tag (`<br>`, `<input>`);
`HTML_MISNESTED_FORMATTING` is the tokenizer's adoption-agency case
(`<b><i></b></i>`); a **bogus comment** is a `<!…>` the parser recovers as a
comment. These are recovery behaviors, so the view still parses — it just does
not nest the way the source reads.

Two diagnostics are not lint codes:

- `state-without-views (hint)` — a schema block with no `<template>` in the
  file. Legitimate for a component whose views are built in MoonBit, and also
  what a mistyped component name looks like, which is why it is reported rather
  than passed in silence.
- `message-case (warning)` — a `receive` or `intent` case declared in a
  spelling nothing else uses: `Nudge` where every handler and call site writes
  `nudge`. Both spellings compile to the same message, so
  this is a warning and the module is still generated; the fix is always the
  name the warning prints.

There is **no** `tutuca-lint-ignore` pragma and no per-line suppression.

### The drift check

`gen` output is checked in, and a stale `*_view_gen.mbt` **type-checks and
tests green** while no longer describing the `.html` beside it. So regenerating
is not optional bookkeeping: it is the only thing that ties the two together.
Run `gen` (or leave `watch` running) after every view edit, and have CI
re-run it and fail on any difference — `tutuca gen src/` followed by
`git diff --exit-code` is the whole check.

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

## Not in this port

- **`tutuca test` does not exist.** `moon test` is the test runner —
  component tests are `test { ... }` blocks over the `@harness` package
  (see [testing.md](./testing.md)). The exit-4 code from the JS CLI is
  gone with it.
- **`tutuca lint` does not exist** as a command. The rules still run, inside
  `gen` (above). What genuinely went away is the part of the JS linter
  that needed a live component — undefined fields, unimplemented `$`-methods,
  bad handler names — because those are type errors in the generated module now.
- **`tutuca storybook` serves a pre-built gallery, not scanned `*.dev.js`.**
  The port compiles ahead of time and the native binary can't load user
  code, so there is no runtime `*.dev.js` discovery. A gallery is a wasm page
  built from the project's own modules — `tutuca new-storybook` scaffolds one,
  `node build.mjs` builds it — and `tutuca storybook [dir] [--port <n>]
  [--out <dir>]` serves it (static HTTP) or copies it (`--out`). Stories come
  from the modules' own `examples`, so there is no story registry either.

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

`code` and `message` are always present; `suggestion`, `hint` and `where` (the
file or view a diagnostic is about) appear when the command has one to give.

Stable error codes (`@cli.error_codes` / the `CODE_*` constants):

| Code                          | When                                          |
| ----------------------------- | --------------------------------------------- |
| `ERR_USAGE_UNKNOWN_COMMAND`   | command name not recognized                   |
| `ERR_USAGE_UNKNOWN_FLAG`      | flag not recognized for the command           |
| `ERR_USAGE_BAD_FLAG_VALUE`    | flag rejected the value (e.g. wrong type)     |
| `ERR_USAGE_MUTUALLY_EXCLUSIVE`| conflicting flags                             |
| `ERR_USAGE_MISSING_ARGUMENT`  | required positional/stdin missing             |
| `ERR_VIEW_GEN_FAILED`         | gen could not compile the view file     |
| `ERR_SKILL_ASSETS_MISSING`    | bundled skill assets not found                |
| `ERR_SKILL_TARGET_EXISTS`     | install-skill target exists; use `--force`    |
| `ERR_INTERNAL`                | a command crashed                             |

## Examples

```sh
# The authoring loop
tutuca gen src/counter.html --name Counter
tutuca watch src/                 # …or leave this running instead

# Verification is the compiler and the test runner, not the CLI
moon check
moon test

# Look at components (the gallery bundle is built from the tutuca repo)
tutuca storybook
```

## Record feedback

`tutuca feedback` appends a freeform feedback record to
`~/.tutuca/feedback.jsonl` (created on first use). Record a note
whenever the CLI, the bundled skill, this reference, or the library
itself was confusing, broken, or surprising — capture it in the
moment instead of reconstructing it later.

```sh
tutuca feedback "HTML_TAG_NOT_ALLOWED_IN_PARENT didn't say which parent it meant"
echo "gen --out swallowed my file when I passed two paths" | tutuca feedback
tutuca feedback < notes.txt
```

Each record is one JSON object per line: `{ts, version, message}`.
Empty input (no positional, no piped stdin) exits **1** with a usage
error. (The `Feedback` outcome needs stdin/filesystem, so minimal
embedding shells may opt out — `cmd/tutuca` has the full handling.)
