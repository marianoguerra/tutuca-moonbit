// extract_globals: there are only two global flags, and everything else is a
// positional for the command's own parser.

///|
test "the two global flags" {
  let (opts, rest) = @cli.extract_globals(["watch", "--json", "src", "-h"])
  assert_true(opts.json)
  assert_true(opts.help)
  @debug.assert_eq(rest, ["watch", "src"])
  assert_true(@cli.extract_globals(["--help"]).0.help)
  assert_false(@cli.extract_globals([]).0.json)
}

///|
test "globals can appear anywhere; positionals keep order" {
  let (opts, rest) = @cli.extract_globals(["gen-views", "--json", "a.html"])
  assert_true(opts.json)
  @debug.assert_eq(rest, ["gen-views", "a.html"])
}

///|
test "the module-era global flags are gone, not silently accepted" {
  // --module, --format, --output and --pretty existed to point at a module
  // and to shape module-command output. They now fall through as positionals
  // (and a command's own parser rejects them as unknown flags).
  let (_, rest) = @cli.extract_globals([
    "watch", "--module=./m.js", "--format=json", "-o", "out.html", "--pretty",
  ])
  @debug.assert_eq(rest, [
    "watch", "--module=./m.js", "--format=json", "-o", "out.html", "--pretty",
  ])
  for gone in ["module", "format", "output", "pretty"] {
    assert_false(@cli.global_flag_names.contains(gone))
  }
  @debug.assert_eq(@cli.global_flag_names, ["json", "help"])
}
