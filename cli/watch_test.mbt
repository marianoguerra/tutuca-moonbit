///|
fn plan_watch(args : Array[String]) -> @cli.Outcome {
  @cli.plan(["watch", ..args])
}

///|
test "watch defaults to the current directory" {
  assert_true(
    plan_watch([])
    is Watch(
      _,
      plan={ paths: ["."], name: None, out: None, ir: true, css: None, }
    ),
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
        ..
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

// --- watching the stylesheet too ------------------------------------------

///|
fn watch_plan(args : Array[String]) -> @cli.WatchPlan {
  match plan_watch(args) {
    Watch(_, plan~) => plan
    _ => abort("expected a watch plan")
  }
}

///|
test "watch writes no stylesheet unless asked" {
  assert_eq(watch_plan(["src"]).css, None)
}

///|
/// The CSS plan watch carries is a real `CssPlan`, so the shell runs the very
/// same collect/compile/write path `gen-margaui-css` runs. A stylesheet that
/// differed between watch and a one-shot build would be worse than none.
test "--margaui-css builds the plan gen-margaui-css would have" {
  let css = watch_plan(["src", "--margaui-css", "public/app.css"]).css.unwrap()
  assert_eq(css.margaui, true)
  assert_eq(css.out, Some("public/app.css"))
  // the watched roots, so the class set is the whole project
  assert_eq(css.paths, ["src"])
  assert_eq(css.print_classes, false)
  assert_eq(css.polyfills, 3)
}

///|
test "--tailwind-css picks the other stylesheet set" {
  let css = watch_plan(["--tailwind-css=app.css"]).css.unwrap()
  assert_eq(css.margaui, false)
  assert_eq(css.out, Some("app.css"))
  assert_eq(css.paths, ["."])
}

///|
test "--css-entry and --css-classes pass through to the CSS plan" {
  let css = watch_plan([
    "src", "--margaui-css", "a.css", "--css-entry", "site.css", "--css-classes",
    "extra.txt",
  ]).css.unwrap()
  assert_eq(css.entry, Some("site.css"))
  assert_eq(css.extra_classes, Some("extra.txt"))
}

///|
test "the two stylesheet flags are alternatives, not a pair" {
  let emit = match
    plan_watch(["--tailwind-css", "a.css", "--margaui-css", "a.css"]) {
    Done(emit) => emit
    _ => abort("expected a usage error")
  }
  assert_eq(emit.exit_code, 1)
  assert_true(emit.err.contains("--tailwind-css and --margaui-css"))
}

///|
/// Accepting these silently would leave watch writing a stylesheet that differs
/// from the built one, with nothing on screen to explain why.
test "--css-entry without a stylesheet flag is a usage error" {
  let emit = match plan_watch(["--css-entry", "site.css"]) {
    Done(emit) => emit
    _ => abort("expected a usage error")
  }
  assert_eq(emit.exit_code, 1)
  assert_true(emit.err.contains("need --tailwind-css or --margaui-css"))
}

///|
test "watch_css_line reports the target and the class count" {
  assert_eq(
    @cli.watch_css_line("public/app.css", classes=248),
    "  → public/app.css (248 classes)\n",
  )
}
