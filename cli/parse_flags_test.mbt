// The grammar every command shares.

///|
fn emit_of(o : @cli.Outcome) -> @cli.Emit {
  match o {
    Done(e) => e
    _ => { out: "", err: "not done", exit_code: 0, }
  }
}

///|
/// A flag that EXTENDS a real one is unknown, not a malformed version of it.
test "a flag that extends a real one is unknown, not a bad value" {
  for
    probe in [
      (["gen", "a.html", "--output", "x"], "--output"),
      (["gen", "a.html", "--namely", "X"], "--namely"),
      (["gen-margaui-css", "--entrypoint", "x.css"], "--entrypoint"),
      (["watch", "--css-classesx", "f"], "--css-classesx"),
    ] {
    let (argv, flag) = probe
    let e = emit_of(@cli.plan(argv))
    assert_eq(e.exit_code, 1)
    assert_true(e.err.contains("unknown flag '\{flag}'"))
    assert_false(e.err.contains("needs a value"))
  }
}

///|
/// `help_overview` promises "did you mean" for unknown flags and the skill's
/// CLI reference shows the JSON envelope carrying one. The registry supplies
/// the candidates, so every command does.
test "an unknown flag suggests a real one, for every command that has flags" {
  for
    probe in [
      (["gen", "a.html", "--nam"], "--name"),
      (["storybook", "--prot", "80"], "--port"),
      (["install-skill", "--forc"], "--force"),
      (["new-storybook", "app", "--dr"], "--dir"),
    ] {
    let (argv, want) = probe
    let e = emit_of(@cli.plan(argv))
    assert_eq(e.exit_code, 1)
    assert_true(e.err.contains("did you mean '\{want}'?"))
  }
}

///|
/// Both spellings, for every string flag, in every command.
test "a string flag takes its value inline or as the next argument" {
  let split = @cli.plan(["gen", "a.html", "--name", "Counter"])
  let inline = @cli.plan(["gen", "a.html", "--name=Counter"])
  assert_true(split is GenViews(_, name=Some("Counter"), ..))
  assert_true(inline is GenViews(_, name=Some("Counter"), ..))
  let short = @cli.plan(["gen-margaui-css", "-o", "app.css"])
  assert_true(short is GenCss(_, plan={ out: Some("app.css"), .. }))
}

///|
/// A boolean is present or absent, which is the shape `agent-context`
/// publishes — so `--dry-run=false` is a mistake worth naming rather than a
/// switch that silently stays on.
test "a boolean flag takes no value" {
  let e = emit_of(@cli.plan(["gen", "a.html", "--dry-run=false"]))
  assert_eq(e.exit_code, 1)
  assert_true(e.err.contains("takes no value"))
}

///|
/// `--` is how a path beginning with a dash gets passed at all.
test "everything after -- is a positional" {
  assert_true(
    @cli.plan(["gen", "--", "--weird.html"])
    is GenViews(_, roots=["--weird.html"], ..),
  )
}

///|
/// An enum flag reports what it accepts AND what the values mean — the second
/// half is the flag's own registry description, so it is not written twice.
test "an enum flag rejects an outside value and explains the set" {
  let e = emit_of(@cli.plan(["gen-margaui-css", "--polyfills", "9"]))
  assert_eq(e.exit_code, 1)
  assert_true(e.err.contains("'--polyfills' expects 0, 1, 2, 3, got '9'"))
  assert_true(e.err.contains("2=color-mix"))
}

///|
/// `help_overview.mbt` is hand-written prose that restates the registry's
/// flags — the one place a flag is deliberately written twice, because prose
/// says WHEN to reach for something and generated text cannot.
///
/// The cost of writing it twice is a flag that exists and is undocumented, so
/// this makes that cost visible: every flag the registry declares must appear
/// in the overview under its long spelling. Adding a flag and not documenting
/// it fails here rather than shipping a CLI whose `--help` is incomplete.
test "every registered flag appears in the hand-written overview" {
  let overview = @cli.agent_context_text()
  let text = @cli.overview()
  let missing : Array[String] = []
  for name in @cli.command_names() {
    let spec = @cli.command_spec(name)
    for f in spec.flags {
      // `--help` is on every command and documented once, under global flags.
      if f.name == "help" {
        continue
      }
      if !text.contains("--" + f.name) {
        missing.push("\{name} --\{f.name}")
      }
    }
  }
  assert_eq(missing, [])
  // and the schema really does carry them, so the two halves agree
  assert_true(overview.contains("polyfills"))
}
