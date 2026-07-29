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
| does this view reference a field that exists? | `gen-views` — the `<script type="tutuca/state">` schema declares the fields, and an unknown `.field` fails generation, inside a loop as well as at the root — including a loop over CHILD components, whose fields are checked against that child's schema |
| does the component this view renders have the view `as=` names? | `gen-views` over the whole project (`tutuca gen-views src/`) — a miss renders blank at run time, and only a run that can see both components can say so. Reported as a hint, because `component()`'s `slots~` can point a slot at a different component than the schema names |
| does this `@show` decide anything? | `gen-views` — a list or a record is always truthy, so `@show=".items"` never hides; it fails generation and names `empty? .items` as the fix |
| is this `id=` unique? | `gen-views` — an `id` inside an `@each` is stamped on every item, which only the compiled tree can see |
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
| `gen-views [path...]`  | Compile `.html` files of views into companion MoonBit modules of typed view surfaces. Paths are files or directories (a directory contributes the `.html` files that already have a generated sibling). Flags: `--name <Name>`, `--out <dir-or-file>`, `--dry-run`, `--no-ir`. See below |
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

tutuca gen-views src/            # the whole project, in one invocation
```

**Pass the whole project when you have one.** Two checks need more than one
component's schema, and they see exactly the paths you passed:

- `<x render=".slot" as="edit">` where the child has no `edit` view. At run time
  `resolve_view` returns None and the site renders **nothing**. Reported as a
  hint rather than an error, because `component()`'s `slots~` can point a
  declared slot at a different component and the generator cannot see that.
- `.field` and `@value.member` inside a loop over `list<todo>`, checked against
  the **Todo** component's schema rather than skipped.

A component outside the paths you passed is unknown, and unknown is never
reported as wrong — so `tutuca gen-views one.html` still works and simply
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
`CounterInput` + `CounterMsg` with `CounterMsg::from_dispatch` (payload types
inferred from the argument shapes at the `@on` call sites: `add 1` ->
`Add(Double)`, `setLabel value` -> `SetLabel(String)` — `value` becomes
`Bool` on a checkbox and `@tutuca.Value` on a file input, per the host
element's static `type` — anything unresolvable
-> `@tutuca.Value`), `CounterMethod` + `counter_compute`/`_swap`
(the `$`-callables, built from an exhaustive match). A file that also carries
a `<script type="tutuca/state">` block gets the state half: `CounterState`
(a plain struct — no derives), `CounterState::zero()`, an
`impl @component.Fields for CounterState` carrying the whole contract as
static metadata plus the direct encode/decode, and a typed
`CounterReceive`/`CounterBubble`/`CounterResponse` for each message bucket the
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
falling into a silent `_ => None`. Handlers served by the auto-generated
field mutators return `None` and fall through to them, as before. The
generated package must import `"marianoguerra/tutuca/core" @tutuca`,
`"marianoguerra/tutuca/component"` and `"moonbitlang/core/debug"`.

The schema goes in a `<script>` and not a `<template>`, because script
content is raw text to an HTML parser and template content is markup — a
`list<s32>` inside a template would be read as an `<s32>` element.

A component with no schema block gets the view half only — no state type, no
codec and no descriptor. There is no weaker substitute: a `counter_fields` /
`counter_missing_fields` pair used to be emitted for such a file, because the
generator could not check a read. It listed the names and left you to assert in
a test that the state carried them, and it only ever covered a view's ROOT
scope — a `.field` under an `@each`, `@enrich-with`, push-view or `<x render>`
was not listed and not checked. A schema-backed component checks every read at
generation time, loop bodies included, so the answer to a file without one is
to declare the schema.

## The state schema

A view file may declare its component's data contract in a small subset of
WIT, alongside the templates that read it:

```html
<script type="tutuca/state">
  interface counter {
    record state {
      label: string,
      count: s32,
      history: list<s32>,
    }
    variant receive { reset-to(s32) }
  }
</script>
```

One `interface` per component, named after the template id it gives views to
(`id="Counter"` -> `interface counter`), and exactly one `record state` in
each. No `package` line: the module supplies it.

| you mean | you write |
| -------- | --------- |
| bool | `bool` |
| int | `s8`..`s32`, `u8`..`u32` (each range-checked on decode) |
| float | `f32` / `f64` |
| text | `string`, `char`, or an `enum` |
| list | `list<T>`, `tuple<A, B>` |
| nullable | `option<T>` |
| record / variant | `record R`, `variant V` |
| set, closed members | `flags F` |
| set, open members | `text-set` |
| ordered map | `value-omap`, `text-omap` |
| a child component | the sibling interface's name, or `component` |
| anything at all | `any`, `values` |

The last four rows are marker names rather than WIT constructs: WIT has no
open type and no user generics, so a set with open membership, an ORDERED map
(WIT's own `map` is unordered by definition) and a child-component slot have
no structural spelling. A slot declared here is checked in the views and
generates its `specs~` entry, but does NOT become a struct field — the
runtime still creates it through the registration scope.

`values` is exactly `list<any>` — the spelling for a heterogeneous list,
most often a list of component instances:

```html
<script type="tutuca/state">
  interface items {
    record state { items: values }
  }
</script>
```

generates `items : Array[@tutuca.Value]`. Iterate it with
`<div @each=".items"><x render-it></x></div>` and append instances with
`Some({ items: s.items + [item.make(Map([]))] })` (the complete pairing
is in [patterns/todo-list.md](./patterns/todo-list.md)). When every
element has one known shape, prefer `list<T>` — the reads stay typed and
the views are checked against the element schema. `any` is the scalar
counterpart: one `@tutuca.Value` field.

Out of the subset, each with its own message: `s64`/`u64` (state travels as
JSON, where integers past 2^53 lose precision), `result`, `future`, `stream`,
`world`s and freestanding `func`s. `map<K, V>` is real WIT but the parser
does not carry it yet.

A file may carry a schema and **no** `<template>` at all. That is how a
component whose views are built in MoonBit — a macro user, a dynamically
assembled tree — still gets a generated state type: the schema lives in a
view file, so it needs a view file even when it has no views. Such a file
emits the state half only, and no view surface. The same applies per
interface: one file may give templates to some components and declare state
alone for others, and `gen-views` reports the latter as a hint rather than an
error, since it is also what a mistyped interface name looks like.

Named initial states go in a block of their own, because a default is a value
and not a type:

```html
<script type="tutuca/init">
{ "fresh": { "label": "Counter" },
  "with-history": { "count": 3, "history": [1, 2, 3] } }
</script>
```

Each is checked against the schema — a fixture setting a field the schema
dropped fails the build — and becomes `CounterState::fresh()` plus a public
`counter_init_args("fresh")` for a ModuleDef example.

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
