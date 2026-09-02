///|
let no_opts : @cli.GlobalOpts = { json: false, help: false, }

///|
fn plan_gen(args : Array[String]) -> @cli.Outcome {
  @cli.plan(["gen-views", ..args])
}

///|
test "the roots reach the shell as written; it expands them" {
  // A directory is a legal root — the shell contributes the .html files under
  // it that already have a generated sibling, the same rule watch uses. The
  // pure half cannot expand it, so it does not try.
  assert_true(
    plan_gen(["demo/counterlib/counter.html"])
    is GenViews(
      _,
      roots=["demo/counterlib/counter.html"],
      out=None,
      name=None,
      dry_run=false,
      ..
    ),
  )
  assert_true(
    plan_gen(["src/", "other/x.html"])
    is GenViews(_, roots=["src/", "other/x.html"], ..),
  )
}

///|
test "the input path decides the component name and the output file" {
  assert_eq(
    @cli.gen_views_target("demo/counterlib/counter.html"),
    ("demo/counterlib/counter_view_gen.mbt", "Counter"),
  )
  // Without --name the basename is capitalized: "todo-list" -> "TodoList".
  assert_eq(
    @cli.gen_views_target("views/todo-list.html"),
    ("views/todo-list_view_gen.mbt", "TodoList"),
  )
}

///|
test "--name and --out override, in both spellings" {
  assert_true(
    plan_gen(["views/todo-list.html", "--name", "Todos", "--out", "src/"])
    is GenViews(_, out=Some("src/"), name=Some("Todos"), ..),
  )
  assert_true(
    plan_gen(["views/todo-list.html", "--name=Todos", "--out=src/gen.mbt"])
    is GenViews(_, out=Some("src/gen.mbt"), name=Some("Todos"), ..),
  )
  assert_eq(
    @cli.gen_views_target("views/todo-list.html", out="src/", name="Todos"),
    ("src/todo-list_view_gen.mbt", "Todos"),
  )
  assert_eq(
    @cli.gen_views_target(
      "views/todo-list.html",
      out="src/gen.mbt",
      name="Todos",
    ),
    ("src/gen.mbt", "Todos"),
  )
}

///|
test "the flags that name ONE thing are refused for a batch" {
  let emit_of = (o : @cli.Outcome) => {
    match o {
      Done(e) => e.err
      _ => "not done"
    }
  }
  assert_true(
    emit_of(plan_gen(["a.html", "b.html", "--name", "X"])).contains(
      "--name names one component",
    ),
  )
  assert_true(
    emit_of(plan_gen(["a.html", "b.html", "--out", "gen.mbt"])).contains(
      "is one file, so it cannot take 2 paths",
    ),
  )
  // A directory --out is fine for a batch: each file keeps its own stem.
  assert_true(
    plan_gen(["a.html", "b.html", "--out", "src/"])
    is GenViews(_, out=Some("src/"), ..),
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
    content="tutuca: gen-views requires an input .html file or a directory\n  hint: `tutuca gen-views path/to/counter.html --name Counter`, or `tutuca gen-views src/`\n",
  )
  // The suggestion is the registry's doing: `parse_flags` offers every
  // spelling the command declares as a candidate, so this is the behaviour
  // `help_overview` has always promised for unknown flags.
  inspect(
    emit_of(plan_gen(["a.html", "--nope"])),
    content="tutuca: unknown flag '--nope' for gen-views\n  did you mean '--name'?\n  hint: see `tutuca gen-views -h` for the accepted flags\n",
  )
  // A flag that EXTENDS a real one is UNKNOWN, not a malformed version of it.
  // No suggestion here because `--output` is three edits from `--out` and the
  // budget is two; reporting the right error without a guess beats reporting
  // the wrong error confidently.
  inspect(
    emit_of(plan_gen(["a.html", "--output", "x"])),
    content="tutuca: unknown flag '--output' for gen-views\n  hint: see `tutuca gen-views -h` for the accepted flags\n",
  )
  // Two paths is no longer an error: it is the whole point of a batch, and
  // what lets a view reference a component another file declares.
  assert_true(
    plan_gen(["a.html", "b.html"])
    is GenViews(_, roots=["a.html", "b.html"], ..),
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
  guard! r is Ok(plan)
  assert_eq(plan.files.map(f => f.0), [
    "views/counter_view_gen.mbt", "views/counter_view_ir_gen.mbt",
  ])
  let ir = plan.files[1].1
  assert_true(ir.contains("pub fn counter_views() -> Map[String, @anode.View]"))
  assert_true(ir.contains("@anode.View::from_ir("))
  // The handler survives into the event table, args and all.
  assert_true(
    ir.contains("@tutuca.Expr::name(\"go\")") &&
    ir.contains("@anode.const_num(1.0)"),
  )
}

///|
test "a macro must be declared in the view file" {
  // An undeclared macro is an error naming the fix rather than a view that
  // silently renders `bad macro: card`.
  let r = @cli.gen_views(
    "<x:card :title=\".a\"></x:card>",
    name="Counter",
    input="views/counter.html",
    target="views/counter_view_gen.mbt",
    ir=true,
  )
  guard! r is Err(shape)
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
  guard! r is Ok(plan)
  assert_eq(plan.files.length(), 2)
  let ir = plan.files[1].1
  // Expanded in place: the macro's <section> is in the tree and no macro
  // node survives.
  assert_true(ir.contains("@anode.h(\"section\""))
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
  guard! r is Err(shape)
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
  guard! r is Ok(plan)
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

///|
test "view-only lint rules report at generation time" {
  // Nothing about these depends on a live component — only on the view text
  // the generator is already parsing, which is why they can be build errors.
  let r = @cli.gen_views(
    (
      #|<template>
      #|  <div>
      #|    <span>unclosed
      #|    <x render-each=".rows" @when="$ok"></x>
      #|  </div>
      #|</template>
    ),
    name="LintMe",
    input="views/lintme.html",
    target="views/lintme_view_gen.mbt",
    ir=false,
  )
  guard! r is Ok(plan)
  inspect(
    plan.diagnostics.join("\n"),
    content=(
      #|HTML_UNCLOSED_BEFORE_END (warning) LintMe/main: <span> still open when </div> was seen — implicitly closed at line 4, col 3
    ),
  )
  // Diagnostics do not stop generation: the emitted types are still sound,
  // which is why anything that WOULD make them wrong fails instead.
  assert_eq(plan.files.length(), 1)
}

///|
/// A protocol member's declared name and its runtime name differ by design —
/// the alias is local, the canonical id is the identity — and the two rules
/// that read those names both used to treat the difference as a mistake: the
/// case lint asked for a spelling the grammar cannot parse, and the script
/// emitter could not find the declaration at all, so a qualified `receive`
/// lost its payload types and was refused into MoonBit.
test "a protocol member keeps its payload and draws no case warning" {
  let r = @cli.gen_views(
    (
      #|<script type="tutuca/spec">
      #|  protocol Openable = "tutuca.dev/std/Openable@1" {
      #|    handle { message { setOpen(Bool) } }
      #|  }
      #|  state Node implements Openable { open: Bool }
      #|  handle Node { message { Openable::setOpen(Bool) } }
      #|</script>
      #|<script type="tutuca/script" for="Node">
      #|  receive Openable::setOpen(b) {
      #|    .open = b
      #|  }
      #|</script>
      #|<template id="Node"><b @text=".open"></b></template>
    ),
    name="Node",
    input="views/node.html",
    target="views/node_view_gen.mbt",
    ir=false,
  )
  guard! r is Ok(plan)
  // No case warning for `Openable::setOpen`, and — the second half — no script
  // refusal, which is what an untyped `b` would have produced right here.
  inspect(plan.diagnostics.join("\n"), content="")
  // And the payload survived as the type the protocol declared.
  assert_true(plan.files[0].1.contains("OpenableSetOpen(Bool)"))
}

///|
/// A transition that only ASSIGNS never reads the state it was handed, and on
/// a one-field state the rebind is a whole record literal rather than
/// `{ ..s, … }` — so the parameter went unread and the generated module was
/// the thing that warned, in a file nobody can edit.
test "a transition that reads no state takes an underscored parameter" {
  let r = @cli.gen_views(
    (
      #|<script type="tutuca/spec">
      #|  state Toggle { theme: String }
      #|  handle Toggle { message { setTheme(String) } }
      #|</script>
      #|<script type="tutuca/script" for="Toggle">
      #|  receive setTheme(t) { .theme = t }
      #|</script>
      #|<template id="Toggle"><b @text=".theme"></b></template>
    ),
    name="Toggle",
    input="views/toggle.html",
    target="views/toggle_view_gen.mbt",
    ir=true,
  )
  guard! r is Ok(plan)
  assert_true(plan.files.map(f => f.1).join("\n").contains("_s : ToggleState,"))
}

///|
/// …and one that DOES read it keeps the name, or the arm would not compile.
test "a transition that reads state keeps its parameter" {
  let r = @cli.gen_views(
    (
      #|<script type="tutuca/spec">
      #|  state Counter { count: Int, label: String }
      #|  handle Counter { message { add(Int) } }
      #|</script>
      #|<script type="tutuca/script" for="Counter">
      #|  receive add(d) { .count += d }
      #|</script>
      #|<template id="Counter"><b @text=".count"></b></template>
    ),
    name="Counter",
    input="views/counter.html",
    target="views/counter_view_gen.mbt",
    ir=true,
  )
  guard! r is Ok(plan)
  assert_true(
    plan.files.map(f => f.1).join("\n").contains("  s : CounterState,"),
  )
}

///|
/// A list of COMPONENTS is `Array[@tutuca.Value]` at runtime, exactly as
/// `Array[Any]` is, so declaring the element type costs nothing at the
/// handler. It used to cost the whole handler: the payload bound raw and the
/// assignment into the typed field was refused into MoonBit, which is what an
/// author got for taking 0.40's advice to type their collections.
test "a component-typed list payload stays in the script language" {
  let r = @cli.gen_views(
    (
      #|<script type="tutuca/spec">
      #|  state Group { label: String }
      #|  state App { models: Array[Group] }
      #|  handle App { message { redraw(Array[Group]) } }
      #|</script>
      #|<script type="tutuca/script" for="App">
      #|  receive redraw(models) { .models = models }
      #|</script>
      #|<template id="Group"><b @text=".label"></b></template>
      #|<template id="App"><div><x render-each=".models"></x></div></template>
    ),
    name="App",
    input="views/app.html",
    target="views/app_view_gen.mbt",
    ir=true,
  )
  guard! r is Ok(plan)
  // no script refusal…
  inspect(plan.diagnostics.join("\n"), content="")
  // …and the arm takes the payload apart as the list it is
  assert_true(
    plan.files.map(f => f.1).join("\n").contains("is Some(List(models_))"),
  )
}

///|
/// The rule still fires on the half it is for: the MEMBER's spelling. The
/// suggestion keeps the file's own qualifier, because that is the only
/// spelling the declaration grammar accepts.
test "a script handler for a protocol message answers the canonical name" {
  // The arm has to MATCH what a sender emits, and a sender emits the runtime
  // name. Written with the declaration spelling it listened for
  // `"Openable::setOpen"` while every `send` addressed
  // `"tutuca.dev/std/Openable@1::setOpen"`, so the handler never ran — in a
  // component with no `update~`, without a word.
  let r = @cli.gen_views(
    (
      #|<script type="tutuca/spec">
      #|  protocol Openable = "tutuca.dev/std/Openable@1" {
      #|    handle { message { setOpen(Bool) } }
      #|  }
      #|  state Node implements Openable { open: Bool }
      #|  handle Node { message { Openable::setOpen(Bool) } }
      #|</script>
      #|<script type="tutuca/script" for="Node">
      #|  receive Openable::setOpen(b) {
      #|    .open = b
      #|  }
      #|</script>
      #|<template id="Node"><b @text=".open"></b></template>
    ),
    name="Node",
    input="views/node.html",
    target="views/node_view_gen.mbt",
    ir=true,
  )
  guard! r is Ok(plan)
  let all = plan.files.map(f => f.1).join("\n")
  assert_true(
    all.contains("Receive(\"tutuca.dev/std/Openable@1::setOpen\", args)"),
  )
  assert_false(all.contains("Receive(\"Openable::setOpen\""))
}

///|
test "a mis-cased protocol member is reported under its alias" {
  let r = @cli.gen_views(
    (
      #|<script type="tutuca/spec">
      #|  protocol Openable = "tutuca.dev/std/Openable@1" {
      #|    handle { message { setOpen(Bool) } }
      #|  }
      #|  state Node implements Openable { open: Bool }
      #|  handle Node { message { Openable::SetOpen(Bool) } }
      #|</script>
      #|<template id="Node"><b @text=".open"></b></template>
    ),
    name="Node",
    input="views/node.html",
    target="views/node_view_gen.mbt",
    ir=false,
  )
  guard! r is Ok(plan)
  inspect(
    plan.diagnostics.join("\n"),
    content=(
      #|message-case (warning) Node: `receive` declares `Openable::SetOpen`, but every use of it is `Openable::setOpen` — a handler writes `receive Openable::setOpen` and a view writes `'Openable::setOpen'`. Declare it `Openable::setOpen`.
    ),
  )
}

///|
test "a message declared in a spelling nothing uses is reported" {
  // The schema is the one place a message name is written UPPER and read
  // lower: the parser derives the runtime name and the MoonBit variant from
  // whatever was written, so `Init` and `init` declare the same message —
  // which is exactly why the mismatch can sit there unnoticed while every
  // handler and every call site writes the other spelling.
  let r = @cli.gen_views(
    (
      #|<script type="tutuca/spec">
      #|  state Thermostat { target: Int }
      #|  handle Thermostat {
      #|    message { Init, Nudge(Int) }
      #|    intent { SetMode(String) }
      #|  }
      #|</script>
      #|<template><button @on.click="init">go</button></template>
    ),
    name="Thermostat",
    input="views/thermostat.html",
    target="views/thermostat_view_gen.mbt",
    ir=false,
  )
  guard! r is Ok(plan)
  inspect(
    plan.diagnostics.join("\n"),
    content=(
      #|message-case (warning) Thermostat: `receive` declares `Init`, but every use of it is `init` — a handler writes `receive init` and a view writes `'init'`. Declare it `init`.
      #|message-case (warning) Thermostat: `receive` declares `Nudge`, but every use of it is `nudge` — a handler writes `receive nudge` and a view writes `'nudge'`. Declare it `nudge`.
      #|message-case (warning) Thermostat: `intent` declares `SetMode`, but every use of it is `setMode` — a handler writes `intent setMode` and a view writes `'setMode'`. Declare it `setMode`.
    ),
  )
  // A warning, so the module is still generated.
  assert_eq(plan.files.length(), 1)
}

///|
test "a message declared the way it is used is silent" {
  let r = @cli.gen_views(
    (
      #|<script type="tutuca/spec">
      #|  state Thermostat { target: Int }
      #|  handle Thermostat { message { init, nudge(Int) } }
      #|</script>
      #|<template><button @on.click="init">go</button></template>
    ),
    name="Thermostat",
    input="views/thermostat.html",
    target="views/thermostat_view_gen.mbt",
    ir=false,
  )
  guard! r is Ok(plan)
  assert_eq(plan.diagnostics, [])
}

///|
test "the block's old name is a warning, once per file" {
  // Once per FILE and not once per component: the spelling is a property of
  // the `<script>` tag, and a file has one tag however many components it
  // declares.
  let r = @cli.gen_views(
    (
      #|<script type="tutuca/state">
      #|  state Thermostat { target: Int }
      #|  state Dial { angle: Int }
      #|</script>
      #|<template id="Thermostat"><b @text=".target"></b></template>
      #|<template id="Dial"><i @text=".angle"></i></template>
    ),
    name="Thermostat",
    input="views/thermostat.html",
    target="views/thermostat_view_gen.mbt",
    ir=false,
  )
  guard! r is Ok(plan)
  inspect(
    plan.diagnostics.join("\n"),
    content=(
      #|spec-block-name (warning) Thermostat: `<script type="tutuca/state">` is now `<script type="tutuca/spec">` — the block declares more than state (types, `handle`/`express`, protocols, wiring, and the `pred`s and `invariant`s the component keeps). The old name still parses; rename the `type=`.
    ),
  )
  // A warning and not a failure: the block parsed, so the module is generated.
  assert_eq(plan.files.length(), 1)
}

///|
test "a clean view produces no diagnostics" {
  let r = @cli.gen_views(
    "<div><button @on.click=\"go\">x</button></div>",
    name="Clean",
    input="views/clean.html",
    target="views/clean_view_gen.mbt",
    ir=false,
  )
  guard! r is Ok(plan)
  assert_eq(plan.diagnostics, [])
}

///|
test "a batch names every file that failed, and writes none of them" {
  // The defect this covers: `gen-views src/` returned on the FIRST bad file, so
  // a directory with three problems took three builds to even see the three —
  // and wrote nothing in the meantime, including for the files that had
  // already compiled.
  let r = @cli.gen_views_all(
    [
      {
        input: "views/a.html",
        target: "views/a_view_gen.mbt",
        name: "A",
        source: "<div @nope=\".x\"></div>",
      },
      {
        input: "views/b.html",
        target: "views/b_view_gen.mbt",
        name: "B",
        source: "<button @on.click=\"go\">x</button>",
      },
      {
        input: "views/c.html",
        target: "views/c_view_gen.mbt",
        name: "C",
        source: "<div @nor=\".y\"></div>",
      },
    ],
    ir=false,
  )
  guard! r is Err(shape)
  inspect(shape.code, content="ERR_VIEW_GEN_FAILED")
  // No single place to name, so `where_` claims none.
  assert_true(shape.where_ is None)
  assert_true(
    shape.message.has_prefix(
      "2 of 3 view files failed to generate; nothing was written\n",
    ),
  )
  assert_true(shape.message.contains("  views/a.html: "))
  assert_true(shape.message.contains("  views/c.html: "))
  // The file that DID compile is not in the message — and there is no plan to
  // write it from, which is the atomicity half.
  assert_true(!shape.message.contains("views/b.html"))
}

///|
test "one failing file in a batch still reads as one file" {
  // `where_` has one slot, so it says something only when there is one thing
  // to say — and then the message is what a single-file run has always given.
  let r = @cli.gen_views_all(
    [
      {
        input: "views/a.html",
        target: "views/a_view_gen.mbt",
        name: "A",
        source: "<button @on.click=\"go\">x</button>",
      },
      {
        input: "views/b.html",
        target: "views/b_view_gen.mbt",
        name: "B",
        source: "<div @nope=\".x\"></div>",
      },
    ],
    ir=false,
  )
  guard! r is Err(shape)
  debug_inspect(shape.where_, content="Some(\"views/b.html\")")
  inspect(
    shape.message,
    content=(
      #|views/b.html: view "main": unknown directive '@nope=".x"' on <div>
    ),
  )
}

///|
test "a file that does not split stops the batch before the emit pass" {
  // A file that did not split is a hole in the component table, and the emit
  // pass reads that table — so a cross-file reference below it would report a
  // SECOND problem that is an artefact of the first. Split failures are
  // answered on their own.
  let r = @cli.gen_views_all(
    [
      {
        input: "views/bad.html",
        target: "views/bad_view_gen.mbt",
        name: "Bad",
        source: "<template id=\"macro:card\"><b>",
      },
      {
        input: "views/uses.html",
        target: "views/uses_view_gen.mbt",
        name: "Uses",
        source: "<x:card></x:card>",
      },
    ],
    ir=false,
  )
  guard! r is Err(shape)
  inspect(shape.code, content="ERR_VIEW_GEN_FAILED")
  // The split failure, alone and named — `uses.html` split fine and was never
  // emitted, so it says nothing about the macro the hole would have hidden.
  debug_inspect(shape.where_, content="Some(\"views/bad.html\")")
  assert_true(shape.message.contains("unclosed <template"))
  assert_true(!shape.message.contains("views/uses.html"))
}
