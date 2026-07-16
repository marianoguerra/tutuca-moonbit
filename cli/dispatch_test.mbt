// plan(): dispatch parity with main() in tools/tutuca.js.

///|
fn done(argv : Array[String]) -> @cli.Emit {
  match @cli.plan(argv) {
    Done(emit) => emit
    _ => abort("expected Done for \{@debug.to_string(argv)}")
  }
}

///|
test "no args prints the overview" {
  let emit = done([])
  assert_eq(emit.exit_code, 0)
  assert_true(emit.out == @cli.overview())
  assert_true(emit.out.has_prefix("tutuca — CLI for inspecting"))
}

///|
test "unknown command gets did-you-mean and exit 1" {
  let emit = done(["lnit", "./m.js"])
  assert_eq(emit.exit_code, 1)
  assert_eq(emit.out, "")
  assert_eq(
    emit.err,
    "tutuca: Unknown command 'lnit'\n" +
    "  did you mean 'lint'?\n" +
    "  hint: Run `tutuca help` for the full reference.\n",
  )
}

///|
test "unknown command under --json is a one-line envelope" {
  let emit = done(["--json", "lnit", "./m.js"])
  assert_eq(emit.exit_code, 1)
  assert_eq(
    emit.err,
    "{\"error\":{\"code\":\"ERR_USAGE_UNKNOWN_COMMAND\",\"message\":\"Unknown command 'lnit'\"," +
    "\"suggestion\":{\"kind\":\"replace-name\",\"from\":\"lnit\",\"to\":\"lint\"}," +
    "\"hint\":\"Run `tutuca help` for the full reference.\"}}\n",
  )
}

///|
test "module command without module path" {
  let emit = done(["get"])
  assert_eq(emit.exit_code, 1)
  assert_eq(
    emit.err,
    "tutuca: 'get' requires a module path\n" +
    "  hint: Pass it as the second positional: `tutuca get <module-path>`, or use --module=<path>.\n",
  )
  // A flag in module position is treated as missing too.
  let emit2 = done(["get", "--limit"])
  assert_eq(emit2.exit_code, 1)
  // --module satisfies the requirement; the stub fires instead.
  let emit3 = done(["--module=./m.js", "get"])
  assert_true(emit3.err.has_prefix("tutuca get: not implemented"))
}

///|
test "module command with a module path hits the stub" {
  let emit = done(["render", "./m.js"])
  assert_eq(emit.exit_code, 1)
  assert_eq(emit.out, "")
  assert_true(
    emit.err.has_prefix(
      "tutuca render: not implemented in the MoonBit port yet\nmissing:\n",
    ),
  )
  assert_true(emit.err.contains("plan_with_module"))
}

///|
test "global -h routes module and stub commands to the help one-liner" {
  let emit = done(["get", "-h"])
  assert_eq(emit.exit_code, 0)
  assert_true(emit.out.has_prefix("get: Summarize the module's exports"))
}

///|
test "storybook --help prints its own usage" {
  let emit = done(["storybook", "--help"])
  assert_eq(emit.exit_code, 0)
  assert_true(emit.out.has_prefix("tutuca storybook"))
}

///|
test "storybook serve returns a ServeStorybook outcome" {
  match @cli.plan(["storybook", "some/dir", "--port", "9999"]) {
    ServeStorybook(_, dir~, port~, out~) => {
      assert_eq(dir, "some/dir")
      assert_eq(port, 9999)
      assert_true(out is None)
    }
    _ => fail("expected ServeStorybook outcome")
  }
}

///|
test "storybook --dry-run lists the compiled registry" {
  let emit = done(["storybook", "--dry-run"])
  assert_eq(emit.exit_code, 0)
  assert_true(emit.out.contains("Basics"))
  assert_true(emit.out.contains("- counter"))
}

///|
test "help routing" {
  assert_true(done(["help"]).out == @cli.overview())
  assert_eq(
    done(["help", "help"]).out,
    "help: Show usage. `help <command>` for per-command detail.\n",
  )
  let lint_help = done(["help", "lint"]).out
  assert_true(lint_help.has_prefix("lint: Run the lint checks on components"))
  assert_true(lint_help.contains("FIELD_VAL_NOT_DEFINED"))
  let get_help = done(["help", "get"]).out
  assert_true(
    get_help.contains(
      "Run `tutuca help` for the full reference including signatures and flags.",
    ),
  )
  // JS quirk preserved: `tutuca help -h` appends --help as the target and
  // fails as an unknown command.
  let quirk = done(["help", "-h"])
  assert_eq(quirk.exit_code, 1)
  assert_true(quirk.err.contains("Unknown command '--help'"))
}

///|
test "agent-context ignores its args" {
  let emit = done(["agent-context", "-h"])
  assert_eq(emit.exit_code, 0)
  assert_true(emit.out == @cli.agent_context_text())
}
