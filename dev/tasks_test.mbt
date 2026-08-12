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
  let expected = @dev.plan("gen-views").unwrap_or([]) +
    @dev.plan("check").unwrap_or([]) +
    @dev.plan("check-examples").unwrap_or([]) +
    @dev.plan("check-skill").unwrap_or([]) +
    @dev.plan("check-guest-list").unwrap_or([]) +
    @dev.plan("check-guest-template").unwrap_or([]) +
    @dev.plan("test").unwrap_or([]) +
    @dev.plan("build").unwrap_or([])
  assert_true(ci == expected)
}

///|
/// `gen-views` regenerating is only a guarantee if CI also checks that what it
/// regenerated is what is checked in — the step that makes the whole ahead-of-
/// time story enforceable rather than conventional. Pinned here because it is
/// the last command, and appending anything after it would silently disarm it.
test "gen-views ends in a drift check over the generated modules" {
  let steps = @dev.plan("gen-views").unwrap_or([])
  guard steps[steps.length() - 1] is Run(cmd) else {
    fail("last gen-views step is not a command")
  }
  assert_eq(cmd.prog, "git")
  assert_eq(cmd.args, [
    "diff", "--exit-code", "HEAD", "--", "*_view_gen.mbt", "*_view_ir_gen.mbt",
  ])
}

///|
test "plan returns None for an unknown task" {
  assert_true(@dev.plan("bogus") is None)
}

///|
test "dist plan builds all targets then assembles dist/" {
  let steps = @dev.plan("dist").unwrap_or([])
  // both asset-embed codegens precede the target builds: each writes a module
  // that the native binary compiles in, and each ends in its own `moon fmt`
  assert_true(steps[0] is GenSkillAssets(_))
  assert_true(steps.iter().any(fn(s) { s is GenGuestTemplate(_) }))
  let builds = steps.iter().take(6).filter(fn(s) { s is Run(_) }).count()
  assert_eq(builds, 4)
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

///|
/// The two bundle-hosting pages are assembled by ONE function, so this pins
/// what varies (the directory, the demo package, the .wasm name) and what must
/// not (the four loader files, the repointing, the packed archives beside the
/// page). A page missing `abi.mjs` mounts, draws, and fails on the first
/// bundle with a message about a module nobody mentioned — the failure the
/// comment in `dyncomp_page_steps` is about.
test "both dyncomp pages are assembled the same way, into their own directory" {
  let pages = [
    ("universal", "universal_wasm.wasm", @dev.universal_steps()),
    (
      "dyncomp-storybook",
      "dyncomp_storybook_wasm.wasm",
      @dev.dyncomp_storybook_steps(),
    ),
  ]
  for page in pages {
    let (into, wasm_name, steps) = page
    let dests : Array[String] = []
    for st in steps {
      match st {
        Copy(from=_, to~) => dests.push(to)
        WriteRewritten(from=_, to~, old_src=_, new_src=_) => dests.push(to)
        _ => ()
      }
    }
    for
      name in [
        "loader.mjs", "app-loader.mjs", "dyncomp-loader.mjs", "abi.mjs", "index.html",
        wasm_name,
      ] {
      assert_true(dests.contains("dist/\{into}/\{name}"))
    }
    // nothing lands in the OTHER page's directory
    let other = if into == "universal" {
      "dyncomp-storybook"
    } else {
      "universal"
    }
    for d in dests {
      assert_false(d.has_prefix("dist/\{other}/"))
    }
  }
}
