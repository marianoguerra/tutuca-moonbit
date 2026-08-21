// plan(): dispatch for the one command set there is.

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
  assert_true(emit.out.has_prefix("tutuca — the CLI for tutuca projects"))
}

///|
test "the overview explains where the compile-time checks are" {
  let text = @cli.overview()
  assert_false(text.contains("<module-path>"))
  assert_false(text.contains("--module"))
  assert_true(text.contains("WHERE THE CHECKS ARE"))
  assert_true(text.contains("gen-views"))
  assert_true(text.contains("moon test"))
}

///|
test "the removed module commands are simply unknown commands now" {
  // No special case, no "needs a module" hint, no stub: this CLI has no
  // concept of a module, so `lint` is a name it does not know.
  for name in ["get", "list", "examples", "show", "lint", "render"] {
    let emit = done([name])
    assert_eq(emit.exit_code, 1)
    assert_eq(emit.out, "")
    assert_true(emit.err.has_prefix("tutuca: Unknown command '\{name}'"))
    assert_false(emit.err.contains("module"))
  }
}

///|
test "unknown command gets did-you-mean and exit 1" {
  let emit = done(["wach"])
  assert_eq(emit.exit_code, 1)
  assert_eq(emit.out, "")
  assert_eq(
    emit.err,
    "tutuca: Unknown command 'wach'\n" +
    "  did you mean 'watch'?\n" +
    "  hint: Run `tutuca help` for the full reference.\n",
  )
}

///|
test "unknown command under --json is a one-line envelope" {
  let emit = done(["--json", "wach"])
  assert_eq(emit.exit_code, 1)
  assert_eq(
    emit.err,
    "{\"error\":{\"code\":\"ERR_USAGE_UNKNOWN_COMMAND\",\"message\":\"Unknown command 'wach'\"," +
    "\"suggestion\":{\"kind\":\"replace-name\",\"from\":\"wach\",\"to\":\"watch\"}," +
    "\"hint\":\"Run `tutuca help` for the full reference.\"}}\n",
  )
}

///|
test "global -h routes a command to the help one-liner" {
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
  assert_true(done(["help"]).out == @cli.overview())
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
  // `help lint` is now just an unknown command, like any other name
  let gone = done(["help", "lint"])
  assert_eq(gone.exit_code, 1)
  assert_true(gone.err.contains("Unknown command 'lint'"))
  // `tutuca help -h` appends --help as the target and
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
