// plan(): dispatch for the STOCK binary — the one that ships. The embedded
// half (module commands over a compiled-in ModuleDef) is module_commands_test.

///|
fn done(argv : Array[String]) -> @cli.Emit {
  match @cli.plan(argv) {
    Done(emit) => emit
    _ => abort("expected Done for \{@debug.to_string(argv)}")
  }
}

///|
test "no args prints the stock overview" {
  let emit = done([])
  assert_eq(emit.exit_code, 0)
  assert_true(emit.out == @cli.overview(Stock))
  assert_true(emit.out.has_prefix("tutuca — the CLI for tutuca projects"))
}

///|
test "the stock overview does not advertise a module path" {
  let text = @cli.overview(Stock)
  assert_false(text.contains("<module-path>"))
  assert_false(text.contains("--module"))
  // it does explain where the module commands live
  assert_true(text.contains("plan_with_module"))
  assert_true(text.contains("demo/counter_cli"))
}

///|
test "unknown command gets did-you-mean and exit 1" {
  let emit = done(["lnit"])
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
  let emit = done(["--json", "lnit"])
  assert_eq(emit.exit_code, 1)
  assert_eq(
    emit.err,
    "{\"error\":{\"code\":\"ERR_USAGE_UNKNOWN_COMMAND\",\"message\":\"Unknown command 'lnit'\"," +
    "\"suggestion\":{\"kind\":\"replace-name\",\"from\":\"lnit\",\"to\":\"lint\"}," +
    "\"hint\":\"Run `tutuca help` for the full reference.\"}}\n",
  )
}

///|
test "a module command in the stock binary explains what it needs" {
  // The command is real; this binary just has no module. Saying "unknown
  // command" would send the reader looking for a typo instead of for
  // plan_with_module.
  for name in ["get", "list", "examples", "show", "lint", "render"] {
    let emit = done([name])
    assert_eq(emit.exit_code, 1)
    assert_eq(emit.out, "")
    assert_true(
      emit.err.has_prefix(
        "tutuca: '\{name}' needs a module, and this binary has none compiled in\n",
      ),
    )
    assert_true(emit.err.contains("plan_with_module"))
    assert_true(emit.err.contains("demo/counter_cli"))
  }
}

///|
test "the module-command error is coded, so --json consumers can branch" {
  let emit = done(["--json", "render"])
  assert_eq(emit.exit_code, 1)
  assert_true(emit.err.contains("\"code\":\"ERR_USAGE_MISSING_MODULE\""))
}

///|
test "help on a module command in stock mode explains rather than documents" {
  let emit = done(["help", "lint"])
  assert_eq(emit.exit_code, 1)
  assert_true(emit.err.contains("needs a module"))
}

///|
test "global -h routes a stock command to the help one-liner" {
  let emit = done(["storybook", "-h"])
  assert_eq(emit.exit_code, 0)
  assert_true(emit.out.has_prefix("tutuca storybook"))
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
test "storybook rejects the flags it used to accept and ignore" {
  // --no-margaui / --no-check / --no-tests were build-time concerns for the
  // compiled host and never did anything here; --dry-run listed a story
  // registry this package no longer knows about.
  for f in ["--no-margaui", "--no-check", "--no-tests", "--dry-run"] {
    let emit = done(["storybook", f])
    assert_eq(emit.exit_code, 1)
    assert_true(emit.err.contains("unknown flag '\{f}' for storybook"))
  }
}

///|
test "storybook rejects a bad --port with a coded error" {
  let emit = done(["storybook", "--port", "zero"])
  assert_eq(emit.exit_code, 1)
  assert_true(emit.err.contains("invalid --port value 'zero'"))
}

///|
test "help routing" {
  assert_true(done(["help"]).out == @cli.overview(Stock))
  assert_eq(
    done(["help", "help"]).out,
    "help: Show usage. `help <command>` for per-command detail.\n",
  )
  let watch_help = done(["help", "watch"]).out
  assert_true(watch_help.has_prefix("watch: Watch view files"))
  assert_true(
    watch_help.contains(
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
  assert_true(emit.out == @cli.agent_context_text(Stock))
}
