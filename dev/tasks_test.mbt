///|
test "every task has a name and one-line help and at least one command" {
  for task in @dev.tasks() {
    assert_true(task.name != "")
    assert_true(task.about != "")
    assert_true(task.commands.length() > 0)
  }
}

///|
test "plan returns None for an unknown task" {
  assert_true(@dev.plan("bogus") is None)
}

///|
test "CI checks generated artifacts before checking sources" {
  let steps = @dev.plan("ci").unwrap()
  guard steps[0] is Run(command) else { fail("expected generated check first") }
  assert_true(command.args.contains("scripts/check-generated.mbtx"))
  for name in ["check", "test", "build", "check-publish-graph", "check-skill"] {
    for required in @dev.plan(name).unwrap() {
      assert_true(steps.contains(required))
    }
  }
  for task in @dev.tasks() {
    assert_true(@dev.plan(task.name) is Some(_))
  }
}

///|
test "generation updates artifacts without comparing against git" {
  for name in ["gen", "skill-embed", "storybook-template-embed", "rt-embed"] {
    for step in @dev.plan(name).unwrap() {
      if step is Run(command) {
        assert_true(command.prog != "git" && command.prog != "diff")
      }
    }
  }
}

///|
test "dist plan builds all targets then assembles dist/" {
  let steps = @dev.plan("dist").unwrap_or([])
  // Both asset-embed codegens precede the target builds: each writes a module
  // that the native binary compiles in, and each ends in its own `moon fmt`.
  //
  // Assert relative order so additional preparation steps can be inserted.
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
