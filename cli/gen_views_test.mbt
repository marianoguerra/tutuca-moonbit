///|
let no_opts : @cli.GlobalOpts = {
  format: None,
  output: None,
  pretty: false,
  module_path: None,
  help: false,
}

///|
fn plan_gen(args : Array[String]) -> @cli.Outcome {
  @cli.plan(["gen-views", ..args])
}

///|
test "the input path decides the component name and the output file" {
  assert_true(
    plan_gen(["demo/counterlib/counter.html"])
    is GenViews(
      _,
      input="demo/counterlib/counter.html",
      target="demo/counterlib/counter_view_gen.mbt",
      name="Counter",
      dry_run=false
    ),
  )
}

///|
test "--name and --out override, in both spellings" {
  assert_true(
    plan_gen(["views/todo-list.html", "--name", "Todos", "--out", "src/"])
    is GenViews(_, target="src/todo-list_view_gen.mbt", name="Todos", ..),
  )
  assert_true(
    plan_gen(["views/todo-list.html", "--name=Todos", "--out=src/gen.mbt"])
    is GenViews(_, target="src/gen.mbt", name="Todos", ..),
  )
  // Without --name the basename is capitalized: "todo-list" -> "TodoList".
  assert_true(
    plan_gen(["views/todo-list.html"]) is GenViews(_, name="TodoList", ..),
  )
}

///|
test "--dry-run stays an outcome: the shell still reads the input file" {
  assert_true(
    plan_gen(["a.html", "--dry-run"]) is GenViews(_, dry_run=true, ..),
  )
}

///|
test "usage errors" {
  let emit_of = (o : @cli.Outcome) => {
    match o {
      Done(e) => e.err
      _ => "not done"
    }
  }
  inspect(
    emit_of(plan_gen([])),
    content="tutuca: gen-views requires an input .html file\n  hint: `tutuca gen-views path/to/counter.html --name Counter`\n",
  )
  inspect(
    emit_of(plan_gen(["a.html", "--nope"])),
    content="tutuca: unknown flag '--nope' for gen-views\n  hint: see `tutuca gen-views -h` for the accepted flags\n",
  )
  inspect(
    emit_of(plan_gen(["a.html", "b.html"])),
    content="tutuca: gen-views takes one input file, got a second positional 'b.html'\n  hint: generate one component's views per invocation\n",
  )
}

///|
test "the compiled tree is a second file, unless --no-ir" {
  assert_true(plan_gen(["a.html", "--no-ir"]) is GenViews(_, ir=false, ..))
  let r = @cli.gen_views(
    "<button id=\"go\" @on.click=\"go 1\">x</button>",
    name="Counter",
    input="views/counter.html",
    target="views/counter_view_gen.mbt",
    ir=true,
  )
  guard r is Ok(plan)
  assert_eq(plan.files.map(f => f.0), [
    "views/counter_view_gen.mbt", "views/counter_view_ir_gen.mbt",
  ])
  let ir = plan.files[1].1
  assert_true(
    ir.contains("pub fn counter_compiled_views() -> Map[String, @anode.View]"),
  )
  assert_true(ir.contains("@anode.ParseContext::from_ir(root, events)"))
  // The handler survives into the event table, args and all.
  assert_true(
    ir.contains("HandlerName(name=\"go\", ns=Input)") &&
    ir.contains("Const(lit=LNum(1.0), from_macro=false)"),
  )
}

///|
test "a macro must be declared in the view file" {
  // Macros used to be registered from MoonBit, which no generator could
  // expand; now an undeclared one is an error naming the fix rather than a
  // view that silently renders `bad macro: card`.
  let r = @cli.gen_views(
    "<x:card :title=\".a\"></x:card>",
    name="Counter",
    input="views/counter.html",
    target="views/counter_view_gen.mbt",
    ir=true,
  )
  guard r is Err(shape)
  inspect(
    shape.message,
    content=(
      #|views/counter.html: view "main": no macro named 'card' — declare it as <template id="macro:card">
    ),
  )
}

///|
test "a declared macro is expanded into the compiled tree" {
  let r = @cli.gen_views(
    (
      #|<template id="macro:card" data-tone="'plain'">
      #|  <section class="card" :data-tone="^tone"><x:slot></x:slot></section>
      #|</template>
      #|<template><x:card tone="loud"><b>hi</b></x:card></template>
    ),
    name="Cards",
    input="views/cards.html",
    target="views/cards_view_gen.mbt",
    ir=true,
  )
  guard r is Ok(plan)
  assert_eq(plan.files.length(), 2)
  let ir = plan.files[1].1
  // Expanded in place: the macro's <section> is in the tree and no macro
  // node survives.
  assert_true(ir.contains("tag: \"section\""))
  assert_true(!ir.contains("MacroCall"))
}

///|
test "generation failures come back as a coded CLI error" {
  let r = @cli.gen_views(
    "<div @nope=\".x\"></div>",
    name="Counter",
    input="views/counter.html",
    target="views/counter_view_gen.mbt",
    ir=false,
  )
  guard r is Err(shape)
  inspect(shape.code, content="ERR_VIEW_GEN_FAILED")
  inspect(
    shape.message,
    content=(
      #|views/counter.html: view "main": unknown directive '@nope=".x"' on <div>
    ),
  )
}

///|
test "a successful plan carries one file" {
  let r = @cli.gen_views(
    "<button @on.click=\"go\">x</button>",
    name="Counter",
    input="views/counter.html",
    target="views/counter_view_gen.mbt",
    ir=false,
  )
  guard r is Ok(plan)
  assert_eq(plan.files.length(), 1)
  assert_eq(plan.files[0].0, "views/counter_view_gen.mbt")
  assert_true(plan.files[0].1.contains("pub(all) enum CounterInput {\n  Go\n}"))
  // The header cites the file's basename, not the path it was written from.
  assert_true(
    plan.files[0].1.has_prefix(
      "// GENERATED by `tutuca gen-views` from counter.html",
    ),
  )
}

///|
test "gen-views is in the command registry, so help and agent-context see it" {
  assert_true(@cli.find_command("gen-views") is Some(_))
  assert_true(@cli.command_names().contains("gen-views"))
  let _ = no_opts
  assert_true(@cli.plan(["help", "gen-views"]) is Done(_))
}
