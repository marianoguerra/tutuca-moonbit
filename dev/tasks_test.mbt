///|
test "every task has a name and one-line help and at least one command" {
  for task in @dev.tasks() {
    assert_true(task.name != "")
    assert_true(task.about != "")
    assert_true(task.commands.length() > 0)
  }
}

///|
test "plan resolves a base task to Run steps" {
  debug_inspect(
    @dev.plan("test"),
    content=(
      #|Some(
      #|  [
      #|    Run({ label: "test · default", prog: "moon", args: ["test"] }),
      #|    Run(
      #|      {
      #|        label: "test · native",
      #|        prog: "moon",
      #|        args: ["test", "--target", "native", "-j", "4"],
      #|      },
      #|    ),
      #|    Run(
      #|      {
      #|        label: "test · js browser adapters",
      #|        prog: "moon",
      #|        args: ["test", "--target", "js", "vdom/browser", "app/browser"],
      #|      },
      #|    ),
      #|  ],
      #|)
    ),
  )
}

///|
test "plan expands the ci composite into its member tasks' steps" {
  let ci = @dev.plan("ci").unwrap_or([])
  let expected = @dev.plan("gen").unwrap_or([]) +
    @dev.plan("skill-embed").unwrap_or([]) +
    @dev.plan("storybook-template-embed").unwrap_or([]) +
    @dev.plan("rt-embed").unwrap_or([]) +
    @dev.plan("check").unwrap_or([]) +
    @dev.plan("check-examples").unwrap_or([]) +
    @dev.plan("check-skill").unwrap_or([]) +
    @dev.plan("check-storybook-template").unwrap_or([]) +
    @dev.plan("check-publish-graph").unwrap_or([]) +
    @dev.plan("check-diagnostics").unwrap_or([]) +
    @dev.plan("check-tgc").unwrap_or([]) +
    @dev.plan("check-cards").unwrap_or([]) +
    @dev.plan("universal").unwrap_or([]) +
    @dev.plan("test").unwrap_or([]) +
    @dev.plan("build").unwrap_or([])
  assert_true(ci == expected)
}

///|
/// `gen` regenerating is only a guarantee if CI also checks that what it
/// regenerated is what is checked in — the step that makes the whole ahead-of-
/// time story enforceable rather than conventional. Pinned here because it is
/// the last command, and appending anything after it would silently disarm it.
test "gen ends in a drift check over the generated modules" {
  let steps = @dev.plan("gen").unwrap_or([])
  guard steps[steps.length() - 1] is Run(cmd) else {
    fail("last gen step is not a command")
  }
  // A CONTENT comparison — the modules as they stood before this run against
  // the same modules after — rather than a `git diff` against `HEAD`. The two
  // answer different questions and agree only on a clean tree: a `.html` edited
  // and regenerated is a consistent pair with neither half committed, which the
  // git form failed and which is exactly when `gen` gets run.
  assert_eq(cmd.prog, "diff")
  assert_eq(cmd.args, ["_build/view_drift.before", "_build/view_drift.after"])
  // …and the "after" reading is taken immediately before it, or the comparison
  // is against a stale file and always passes.
  guard steps[steps.length() - 2] is Run(snap) else {
    fail("the step before the drift check is not a command")
  }
  assert_true(
    snap.args.length() == 2 && snap.args[1].has_suffix("view_drift.after"),
  )
  // The "before" reading is the FIRST step: taken after any generator ran, it
  // would read the regenerated modules and the check could never fail.
  guard steps[0] is Run(first) else { fail("first gen step is not a command") }
  assert_true(
    first.args.length() == 2 && first.args[1].has_suffix("view_drift.before"),
  )
}

///|
test "plan returns None for an unknown task" {
  assert_true(@dev.plan("bogus") is None)
}

///|
test "dist plan builds all targets then assembles dist/" {
  let steps = @dev.plan("dist").unwrap_or([])
  // Both asset-embed codegens precede the target builds: each writes a module
  // that the native binary compiles in, and each ends in its own `moon fmt`.
  //
  // Asserted by ORDER rather than by index. The embed steps carry their own
  // scaffolding — a snapshot taken before regenerating, so the drift check can
  // compare content instead of asking git about a commit — and an assertion on
  // `steps[0]` was really an assertion about how many of those there are, which
  // is not the claim this test means to make.
  let first_of = (pred : (@dev.Step) -> Bool) => {
    let mut at = -1
    for i, st in steps {
      if at < 0 && pred(st) {
        at = i
      }
    }
    at
  }
  let embed = first_of(fn(s) { s is GenSkillAssets(_) })
  let first_build = first_of(fn(s) {
    match s {
      Run(cmd) =>
        cmd.prog == "moon" && cmd.args.length() > 0 && cmd.args[0] == "build"
      _ => false
    }
  })
  assert_true(embed >= 0)
  assert_true(first_build > embed)
  // Four target builds: wasm-gc, native cli, js, and the js playground host.
  let builds = steps
    .iter()
    .filter(fn(s) {
      match s {
        Run(cmd) =>
          cmd.prog == "moon" && cmd.args.length() > 0 && cmd.args[0] == "build"
        _ => false
      }
    })
    .count()
  assert_true(builds >= 4)
  // and it emits copies + the mkdirs
  assert_true(steps.iter().any(fn(s) { s is Mkdir(_) }))
  assert_true(steps.iter().any(fn(s) { s is Copy(_) }))
  // the landing site + playground payload are assembled by node scripts at the end
  let node_scripts = steps
    .iter()
    .filter_map(fn(s) {
      match s {
        Run(cmd) => if cmd.prog == "node" { Some(cmd.args) } else { None }
        _ => None
      }
    })
    .to_array()
  assert_true(node_scripts.contains(["playground/build/assemble.mjs"]))
  assert_true(node_scripts.contains(["playground/build/assemble-site.mjs"]))
}

///|
test "rewrite repoints a demo script src" {
  let html =
    #|<script src="../../_build/js/debug/build/demo/counter/counter.js"></script>
  inspect(
    @dev.rewrite(
      html,
      old_src="../../_build/js/debug/build/demo/counter/counter.js",
      new_src="./counter.js",
    ),
    content=(
      #|<script src="./counter.js"></script>
    ),
  )
}

///|
/// Every RUNNABLE task is listed, which is stronger than it sounds: `guests`
/// was runnable and unlisted for as long as `plan` and `help_text` kept
/// separate lists of the assembled tasks. This walks the names `plan` actually
/// answers, so a task that gains a plan and no line fails here.
test "help_text lists every task name" {
  let help = @dev.help_text()
  for task in @dev.tasks() {
    assert_true(help.contains(task.name))
  }
  for
    name in [
      "ci", "dist", "skill-embed", "storybook-template-embed", "css-bundle",
    ] {
    assert_true(@dev.plan(name) is Some(_))
    assert_true(help.contains(name))
  }
}
