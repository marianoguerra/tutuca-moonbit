///|
fn plan_watch(args : Array[String]) -> @cli.Outcome {
  @cli.plan(["watch", ..args])
}

///|
test "watch defaults to the current directory" {
  assert_true(
    plan_watch([])
    is Watch(_, plan={ paths: ["."], name: None, out: None, ir: true }),
  )
}

///|
test "watch takes files and directories, and the gen-views flags" {
  assert_true(
    plan_watch(["src", "views/counter.html", "--no-ir", "--out=gen"])
    is Watch(
      _,
      plan={
        paths: ["src", "views/counter.html"],
        out: Some("gen"),
        ir: false,
        ..,
      }
    ),
  )
}

///|
test "--name is only meaningful for a single file" {
  assert_true(
    plan_watch(["a.html", "--name=Counter"])
    is Watch(_, plan={ name: Some("Counter"), .. }),
  )
  let emit = match plan_watch(["a.html", "b.html", "--name=Counter"]) {
    Done(e) => e.err
    _ => "not done"
  }
  inspect(
    emit,
    content="tutuca: --name applies to a single view file, but 2 paths were given\n  hint: name the components inside the file with `id=\"Comp:view\"` instead\n",
  )
}

///|
test "only .html files are worth reacting to" {
  // The generated modules are written BY the watcher; reacting to them would
  // regenerate forever.
  assert_true(@cli.is_view_path("views/counter.html"))
  assert_true(!@cli.is_view_path("views/counter_view_gen.mbt"))
  assert_true(!@cli.is_view_path("views/counter.mbt"))
}

///|
test "watch and gen-views agree on output paths and names" {
  // Same file, same answer: a drift here would have watch write somewhere
  // `gen-views` never looks.
  assert_eq(
    @cli.watch_target("demo/counterlib/counter.html", None),
    "demo/counterlib/counter_view_gen.mbt",
  )
  assert_eq(@cli.watch_target("a/b.html", Some("gen")), "gen/b_view_gen.mbt")
  assert_eq(@cli.watch_target("a/b.html", Some("g/x.mbt")), "g/x.mbt")
  assert_eq(@cli.watch_name("views/todo-list.html", None), "TodoList")
  assert_eq(@cli.watch_name("views/todo-list.html", Some("Todos")), "Todos")
  // The sibling that marks a file as one gen-views manages.
  assert_eq(@cli.watch_sibling("a/b.html"), "a/b_view_gen.mbt")
  let plan = match plan_watch(["a/b.html"]) {
    Watch(_, plan~) => plan
    _ => fail("expected a watch plan")
  }
  assert_eq(@cli.watch_target("a/b.html", plan.out), "a/b_view_gen.mbt")
}

///|
test "watch is in the registry" {
  assert_true(@cli.find_command("watch") is Some(_))
  assert_true(@cli.plan(["help", "watch"]) is Done(_))
}
