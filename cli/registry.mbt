// Command registry: single source of truth for dispatch, `help`, and the
// `agent-context` schema.
//
// There are TWO command sets, because there are two binaries.
//
//   STOCK — what `moon run cmd/main` (and a released `tutuca`) ships. A native
//   binary cannot load user code, so it has no way to reach a user's
//   components: everything here works on files or on itself.
//
//   MODULE — get/list/examples/show/lint/render. These run against a
//   `@component.ModuleDef` VALUE, so they exist only in a project binary that
//   compiles its module in and calls `plan_with_module` (demo/counter_cli is
//   the worked example). They take an optional component-name filter as their
//   first positional and NO module path: the module is the one compiled in.
//
// The JS CLI's module-path convention has no analogue here, so neither set
// carries a `module-path` positional or a `--module` flag. `CliMode` picks the
// set, and `agent-context` reports the set the running binary actually has.

///|
let help_flag : FlagSpec = flag("help", short="h", type_="boolean")

///|
fn flag(
  name : String,
  short? : String,
  type_~ : String,
  enum_? : Array[String],
  description? : String,
) -> FlagSpec {
  { name, short, type_, enum_, description }
}

///|
fn positional(
  name : String,
  required~ : Bool,
  description? : String,
  note? : String,
) -> PositionalSpec {
  { name, required, description, note }
}

///|
/// The one positional every module command shares: which component to operate
/// on. Omit it for all of them.
fn module_positionals() -> Array[PositionalSpec] {
  [
    positional(
      "name",
      required=false,
      description="Component name filter (operate on one component).",
    ),
  ]
}

///|
fn module_cmd(
  name : String,
  describe : String,
  default_format~ : String,
  needs_env? : Bool = false,
  flags? : Array[FlagSpec] = [],
) -> CommandSpec {
  {
    name,
    describe,
    needs_module: true,
    needs_env,
    default_format: Some(default_format),
    flags,
    positionals: module_positionals(),
  }
}

///|
/// Commands that run against the embedded `ModuleDef`. Present only in
/// `Embedded` mode; `plan_with_module` is the only thing that runs them.
let module_commands : Array[CommandSpec] = [
  module_cmd(
    "get",
    "Summarize the module's components and counts.",
    default_format="cli",
  ),
  module_cmd("list", "List components in the module.", default_format="cli", flags=[
    flag(
      "limit",
      type_="string",
      description="Cap number of components emitted (0 = all). Truncated output is signaled by `truncated: true` in JSON.",
    ),
  ]),
  module_cmd("examples", "List examples in the module.", default_format="cli", flags=[
    flag(
      "limit",
      type_="string",
      description="Cap total number of example items emitted (0 = all).",
    ),
  ]),
  module_cmd(
    "show",
    "Show API docs for components (optional <name> for one).",
    default_format="md",
  ),
  // view HTML linting + component provide/lookup shape checks; exit code 2 on
  // error-level findings.
  module_cmd(
    "lint",
    "Run the lint checks on components (optional <name> for one).",
    default_format="cli",
    needs_env=true,
  ),
  // examples mounted headlessly on memdom, output cleaned via clean_vdom.
  // Exit code 3 (render crash) is reserved and documented but unreachable.
  module_cmd(
    "render",
    "Render examples to HTML (optional <name> to filter by component).",
    default_format="md",
    needs_env=true,
    flags=[
      flag("title", type_="string", description="Filter by example title."),
      flag("view", type_="string", description="Override example's view name."),
    ],
  ),
]

// No `test` command: MoonBit's own `moon test` is the test runner. Component
// tests are authored as native `moon test "..." { ... }` blocks using the
// built-in assertions (`assert_eq`, `assert_true(x is Pattern)`,
// `@test.assert_raise`, `inspect`/`debug_inspect`) and the reusable headless
// harness in `marianoguerra/tutuca/testing/harness` (mount + drive + read DOM
// back). See AGENTS.md for the jest-matcher → built-in mapping. The `dev`
// task runner wraps `moon test` (moon run --target native cmd/dev -- test).

///|
/// Commands the stock binary ships: they need no user module, so they work
/// the same whether or not a module is compiled in. Present in BOTH modes.
let stock_commands : Array[CommandSpec] = [
  {
    name: "help",
    describe: "Show usage. `help <command>` for per-command detail.",
    needs_module: false,
    needs_env: false,
    default_format: None,
    flags: [help_flag],
    positionals: [positional("command", required=false)],
  },
  {
    name: "feedback",
    describe: "Record freeform feedback (bug, confusion, suggestion) to ~/.tutuca/feedback.jsonl.",
    needs_module: false,
    needs_env: false,
    default_format: None,
    flags: [help_flag],
    positionals: [
      positional(
        "message",
        required=false,
        note="Falls back to piped stdin when omitted.",
      ),
    ],
  },
  // The skill assets are embedded in the binary at compile time
  // (skill_assets_gen.mbt, regenerated by `cmd/dev -- skill-embed`). Only
  // the tutuca skill ships with the MoonBit port — no margaui/immutable-js
  // selection flags.
  {
    name: "install-skill",
    describe: "Install the bundled tutuca Claude Code skill into .claude/skills/.",
    needs_module: false,
    needs_env: false,
    default_format: None,
    flags: [
      flag("user", type_="boolean", description="Install at ~/.claude/skills/."),
      flag(
        "project",
        type_="boolean",
        description="Install at ./.claude/skills/ (default).",
      ),
      flag(
        "dot-agents",
        type_="boolean",
        description="Use .agents/skills/ instead of .claude/skills/.",
      ),
      flag(
        "dry-run",
        type_="boolean",
        description="Print files that would be written; don't touch disk.",
      ),
      flag(
        "force",
        short="f",
        type_="boolean",
        description="Overwrite existing files.",
      ),
      help_flag,
    ],
    positionals: [],
  },
  // A pre-built static bundle, served or copied. The gallery itself is a wasm
  // host built by `cmd/dev -- dist`; this command is a static file server and
  // nothing else, so it needs no knowledge of the story registry.
  {
    name: "storybook",
    describe: "Serve (or copy) the pre-built storybook gallery bundle.",
    needs_module: false,
    needs_env: false,
    default_format: None,
    flags: [
      flag(
        "port",
        type_="string",
        description="Preferred port (default 4321; falls back to a free port).",
      ),
      flag(
        "out",
        type_="string",
        description="Copy the static bundle to <dir> instead of serving.",
      ),
      help_flag,
    ],
    positionals: [
      positional(
        "dir",
        required=false,
        description="A pre-built bundle directory to serve (default: the bundle shipped next to the binary, dist/storybook).",
      ),
    ],
  },
  // Ahead-of-time view compilation (gen_views.mbt + the viewgen package).
  // Needs no module: it reads an .html file and writes a .mbt file, so it
  // works before the component that will use the generated types exists.
  {
    name: "gen-views",
    describe: "Compile an .html file of views into a MoonBit module of typed view surfaces.",
    needs_module: false,
    needs_env: false,
    default_format: None,
    flags: [
      flag(
        "name",
        type_="string",
        description="Component name heading the generated types (default: the file's basename).",
      ),
      flag(
        "out",
        type_="string",
        description="Output directory, or an explicit .mbt path (default: beside the input).",
      ),
      flag(
        "dry-run",
        type_="boolean",
        description="Print the generated modules instead of writing them.",
      ),
      flag(
        "no-ir",
        type_="boolean",
        description="Skip the companion compiled-tree module (<stem>_view_ir_gen.mbt).",
      ),
      help_flag,
    ],
    positionals: [
      positional(
        "file",
        required=true,
        description="The .html file holding the component's views.",
      ),
    ],
  },
  // The authoring loop for views: `gen-views` on every save (watch.mbt).
  {
    name: "watch",
    describe: "Watch view files and regenerate their MoonBit modules on change.",
    needs_module: false,
    needs_env: false,
    default_format: None,
    flags: [
      flag(
        "name",
        type_="string",
        description="Component name, when watching a single unnamed file.",
      ),
      flag(
        "out",
        type_="string",
        description="Output directory (default: beside each input).",
      ),
      flag(
        "no-ir",
        type_="boolean",
        description="Skip the companion compiled-tree module.",
      ),
      help_flag,
    ],
    positionals: [
      positional(
        "path",
        required=false,
        description="View files or directories to watch (default: the current directory).",
      ),
    ],
  },
  {
    name: "agent-context",
    describe: "Print a machine-readable schema (commands, flags, exit codes) as JSON.",
    needs_module: false,
    needs_env: false,
    default_format: None,
    flags: [],
    positionals: [],
  },
]

///|
/// The commands a binary in `mode` actually has. Module commands come first so
/// `agent-context` and the did-you-mean candidate list keep a stable order
/// with the module surface up top, where it is the interesting part.
fn commands_for(mode : CliMode) -> Array[CommandSpec] {
  match mode {
    Stock => stock_commands
    Embedded => module_commands + stock_commands
  }
}

///|
pub fn find_command(mode : CliMode, name : String) -> CommandSpec? {
  for c in commands_for(mode) {
    if c.name == name {
      return Some(c)
    }
  }
  None
}

///|
pub fn command_names(mode : CliMode) -> Array[String] {
  commands_for(mode).map(c => c.name)
}

///|
/// True for a command that only a module-embedding binary has. Stock dispatch
/// uses it to say "this needs an embedded module" instead of the misleading
/// "unknown command".
fn is_module_command(name : String) -> Bool {
  for c in module_commands {
    if c.name == name {
      return true
    }
  }
  false
}

///|
/// Did-you-mean candidates: every name the CLI knows in either mode, so a typo
/// for `lint` is recognized as one even in a stock binary that cannot run it
/// (dispatch then explains why, rather than pretending the name is unknown).
fn all_command_names() -> Array[String] {
  commands_for(Embedded).map(c => c.name)
}
