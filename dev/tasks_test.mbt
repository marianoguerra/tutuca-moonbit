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
      #|        args: ["test", "--target", "native"],
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
  let expected = @dev.plan("check").unwrap_or([]) +
    @dev.plan("check-examples").unwrap_or([]) +
    @dev.plan("test").unwrap_or([]) +
    @dev.plan("build").unwrap_or([])
  assert_true(ci == expected)
}

///|
test "plan returns None for an unknown task" {
  assert_true(@dev.plan("bogus") is None)
}

///|
test "dist plan builds all targets then assembles dist/" {
  let steps = @dev.plan("dist").unwrap_or([])
  // the skill-embed codegen precedes the target builds
  assert_true(steps[0] is GenSkillAssets(_))
  let builds = steps.iter().take(4).filter(fn(s) { s is Run(_) }).count()
  assert_eq(builds, 3)
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
test "help_text lists every task name" {
  let help = @dev.help_text()
  for task in @dev.tasks() {
    assert_true(help.contains(task.name))
  }
  assert_true(help.contains("ci"))
  assert_true(help.contains("dist"))
}
