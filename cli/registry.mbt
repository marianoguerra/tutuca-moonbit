// Command registry: single source of truth for dispatch, `help`, and the
// `agent-context` schema. Merges the JS CLI's two tables
// (tools/cli/commands/_registry.js for module commands,
// tools/cli/commands/_no-module.js for the rest) keeping their order:
// module commands first, then no-module, because agent-context emits
// `commands` and did-you-mean candidates in exactly this order.

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
/// The two positionals every module command shares (agent-context.js
/// moduleCommandSchema).
fn module_positionals() -> Array[PositionalSpec] {
  [
    positional(
      "module-path",
      required=true,
      description="Path to the ES module to inspect.",
    ),
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
  missing~ : Array[String],
) -> CommandSpec {
  {
    name,
    describe,
    needs_module: true,
    needs_env,
    default_format: Some(default_format),
    flags,
    positionals: module_positionals(),
    impl_: Stub(missing),
  }
}

///|
/// Blockers shared by every command that introspects a user module. Written
/// once here; the per-command TODO(port) comments below reference it.
fn module_blockers() -> Array[String] {
  [
    "module-input: a native binary cannot load user code; the module-shape convention EXISTS (@component.ModuleDef) and these commands ARE wired for it — build a project binary whose main calls @cli.plan_with_module(argv, your_module)",
  ]
}

///|
pub let commands : Array[CommandSpec] = [
  // `get` (and every module command below) IS runnable via
  // plan_with_module(argv, Some(module)) — the path-based stock-binary form
  // stays stubbed because a native binary cannot load user code.
  module_cmd(
    "get",
    "Summarize the module's exports and counts.",
    default_format="cli",
    missing=module_blockers(),
  ),
  // `list`: runnable via plan_with_module; path form stubbed (see `get`).
  module_cmd(
    "list",
    "List components in the module.",
    default_format="cli",
    flags=[
      flag(
        "limit",
        type_="string",
        description="Cap number of components emitted (0 = all). Truncated output is signaled by `truncated: true` in JSON.",
      ),
    ],
    missing=module_blockers(),
  ),
  // `examples`: runnable via plan_with_module; path form stubbed (see `get`).
  module_cmd(
    "examples",
    "List examples in the module.",
    default_format="cli",
    flags=[
      flag(
        "limit",
        type_="string",
        description="Cap total number of example items emitted (0 = all).",
      ),
    ],
    missing=module_blockers(),
  ),
  // `show`: runnable via plan_with_module; path form stubbed (see `get`).
  module_cmd(
    "show",
    "Show API docs for components (optional <name> for one).",
    default_format="md",
    missing=module_blockers(),
  ),
  // `lint`: runnable via plan_with_module (view HTML linting + component
  // provide/lookup shape checks; exit code 2 on findings); path form stubbed.
  // Exit code 2 (findings at error level) is reserved and documented but
  // unreachable until then.
  module_cmd(
    "lint",
    "Run the lint checks on components (optional <name> for one).",
    default_format="cli",
    needs_env=true,
    missing=module_blockers(),
  ),
  // `render`: runnable via plan_with_module (examples mounted headlessly on
  // memdom, output cleaned via clean_vdom); path form stubbed.
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
    missing=module_blockers(),
  ),
  // No `test` command: MoonBit's own `moon test` is the test runner. Component
  // tests are authored as native `moon test "..." { ... }` blocks using the
  // built-in assertions (`assert_eq`, `assert_true(x is Pattern)`,
  // `@test.assert_raise`, `inspect`/`debug_inspect`) and the reusable headless
  // harness in `marianoguerra/tutuca/testing/harness` (mount + drive + read DOM
  // back). See AGENTS.md for the jest-matcher → built-in mapping. The `dev`
  // task runner wraps `moon test` (moon run --target native cmd/dev -- test).
  {
    name: "help",
    describe: "Show usage. `help <command>` for per-command detail.",
    needs_module: false,
    needs_env: false,
    default_format: None,
    flags: [help_flag],
    positionals: [positional("command", required=false)],
    impl_: Wired,
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
    impl_: Wired,
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
    impl_: Wired,
  },
  // The MoonBit port compiles AOT and the native binary can't load user code,
  // so there is no runtime *.dev.js discovery: the gallery is the compiled
  // example registry (storybook/), baked into a wasm host at build time. This
  // command SERVES that pre-built bundle (or copies it with --out, or lists it
  // with --dry-run). See storybook.mbt + help_overview.mbt.
  {
    name: "storybook",
    describe: "Serve the pre-built storybook gallery (the compiled example registry).",
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
      flag(
        "no-margaui",
        type_="boolean",
        description="Accepted for parity; a build-time concern for the compiled host (no effect on serving).",
      ),
      flag(
        "no-check",
        type_="boolean",
        description="Accepted for parity; the Lint panel is baked into the host (no effect on serving).",
      ),
      flag(
        "no-tests",
        type_="boolean",
        description="Accepted for parity; run tests with `moon test` (no effect on serving).",
      ),
      flag(
        "dry-run",
        type_="boolean",
        description="Print the compiled story registry instead of serving. Pass --json for structured output.",
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
    impl_: Wired,
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
    impl_: Wired,
  },
  {
    name: "agent-context",
    describe: "Print a machine-readable schema (commands, flags, exit codes) as JSON.",
    needs_module: false,
    needs_env: false,
    default_format: None,
    flags: [],
    positionals: [],
    impl_: Wired,
  },
]

///|
pub fn find_command(name : String) -> CommandSpec? {
  for c in commands {
    if c.name == name {
      return Some(c)
    }
  }
  None
}

///|
pub fn command_names() -> Array[String] {
  commands.map(c => c.name)
}
