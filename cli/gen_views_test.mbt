///|
let no_opts : @cli.GlobalOpts = { json: false, help: false, }

///|
fn plan_gen(args : Array[String]) -> @cli.Outcome {
  @cli.plan(["gen", ..args])
}

///|
test "the roots reach the shell as written; it expands them" {
  // A directory is a legal root — the shell contributes the .html files under
  // it that already have a generated sibling, the same rule watch uses. The
  // pure half cannot expand it, so it does not try.
  assert_true(
    plan_gen(["demo/counterlib/counter.tutu"])
    is GenViews(
      _,
      roots=["demo/counterlib/counter.tutu"],
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
    @cli.gen_views_target("demo/counterlib/counter.tutu"),
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
    content="tutuca: gen requires an input .tutu file or a directory\n  hint: `tutuca gen path/to/counter.tutu --name Counter`, or `tutuca gen src/`\n",
  )
  // The suggestion is the registry's doing: `parse_flags` offers every
  // spelling the command declares as a candidate, so this is the behaviour
  // `help_overview` has always promised for unknown flags.
  inspect(
    emit_of(plan_gen(["a.html", "--nope"])),
    content="tutuca: unknown flag '--nope' for gen\n  did you mean '--name'?\n  hint: see `tutuca gen -h` for the accepted flags\n",
  )
  // A flag that EXTENDS a real one is UNKNOWN, not a malformed version of it.
  // No suggestion here because `--output` is three edits from `--out` and the
  // budget is two; reporting the right error without a guess beats reporting
  // the wrong error confidently.
  inspect(
    emit_of(plan_gen(["a.html", "--output", "x"])),
    content="tutuca: unknown flag '--output' for gen\n  hint: see `tutuca gen -h` for the accepted flags\n",
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
    "view:\n  Counter:\n    button(id: \"go\", ~on_click: go(1)):\n      \"x\"\n",
    name="Counter",
    input="views/counter.tutu",
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
test "a declared macro is expanded into the compiled tree" {
  let r = @cli.gen_views(
    (
      #|view:
      #|  macro card(~tone: "plain", ~body: ""):
      #|    section(class: "card", data_tone: tone):
      #|      @(body)
      #|
      #|  Cards:
      #|    card(~tone: "loud", ~body: "hi")
    ),
    name="Cards",
    input="views/cards.tutu",
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
    "view:\n  Counter:\n    @div{@each(value in it.rows, ~when: nope()){@p{x}}}\n",
    name="Counter",
    input="views/counter.tutu",
    target="views/counter_view_gen.mbt",
    ir=false,
  )
  guard! r is Err(shape)
  inspect(shape.code, content="ERR_VIEW_GEN_FAILED")
  inspect(
    shape.message,
    content=(
      #|views/counter.tutu: view "Counter": `~when` names a handler — declare it in the logic section and name it here
    ),
  )
}

///|
test "a successful plan carries one file" {
  let r = @cli.gen_views(
    "view:\n  Counter:\n    button(~on_click: go):\n      \"x\"\n",
    name="Counter",
    input="views/counter.tutu",
    target="views/counter_view_gen.mbt",
    ir=false,
  )
  guard! r is Ok(plan)
  assert_eq(plan.files.length(), 1)
  assert_eq(plan.files[0].0, "views/counter_view_gen.mbt")
  assert_true(plan.files[0].1.contains("pub(all) enum CounterMsg {\n  Go\n"))
  // The header cites the file's basename, not the path it was written from.
  assert_true(
    plan.files[0].1.has_prefix("// GENERATED by `tutuca gen` from counter.tutu"),
  )
}

///|
test "gen is in the command registry, so help and agent-context see it" {
  assert_true(@cli.find_command("gen") is Some(_))
  assert_true(@cli.command_names().contains("gen"))
  let _ = no_opts
  assert_true(@cli.plan(["help", "gen"]) is Done(_))
}

///|
test "view-only advisory rules report at generation time" {
  // The HTML linter went with the notation: an unclosed element is a thing a
  // tokenizer repairs, and at-notation has no way to write one. What is left
  // is the advice about what a view REACHES — which is about the tree, so it
  // survives the format.
  let r = @cli.gen_views(
    (
      #|view:
      #|  LintMe:
      #|    div():
      #|      each(value, key in it.rows):
      #|        button(~on_click: go(e.target.ownerDocument.x)):
      #|          "x"
    ),
    name="LintMe",
    input="views/lintme.tutu",
    target="views/lintme_view_gen.mbt",
    ir=false,
  )
  guard! r is Ok(plan)
  assert_true(
    plan.diagnostics.join("\n").contains("event-path allowlist"),
    msg=plan.diagnostics.join("\n"),
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
      #|spec:
      #|  protocol Openable = "tutuca.dev/std/Openable@1":
      #|    message setOpen(Bool)
      #|
      #|  Node:
      #|    field open :: Bool
      #|    implements Openable
      #|    message Openable::setOpen(Bool)
      #|
      #|logic:
      #|  Node:
      #|    receive Openable::setOpen(b):
      #|      it.open := b
      #|
      #|view:
      #|  Node:
      #|    b():
      #|      @(it.open)
    ),
    name="Node",
    input="views/node.tutu",
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
      #|spec:
      #|  Toggle:
      #|    field theme :: String
      #|    message setTheme(String)
      #|
      #|logic:
      #|  Toggle:
      #|    receive setTheme(t):
      #|      it.theme := t
      #|
      #|view:
      #|  Toggle:
      #|    b():
      #|      @(it.theme)
    ),
    name="Toggle",
    input="views/toggle.tutu",
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
      #|spec:
      #|  Counter:
      #|    field count :: Int
      #|    field label :: String
      #|    message add(Int)
      #|
      #|logic:
      #|  Counter:
      #|    receive add(d):
      #|      it.count += d
      #|
      #|view:
      #|  Counter:
      #|    b():
      #|      @(it.count)
    ),
    name="Counter",
    input="views/counter.tutu",
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
      #|spec:
      #|  Group:
      #|    field label :: String
      #|
      #|  App:
      #|    field models :: List.of(Instance.of(Group))
      #|    message redraw(List.of(Instance.of(Group)))
      #|
      #|logic:
      #|  App:
      #|    receive redraw(models):
      #|      it.models := models
      #|
      #|view:
      #|  Group:
      #|    b():
      #|      @(it.label)
      #|
      #|  App:
      #|    div():
      #|      each(value, key in it.models):
      #|        render(value)
    ),
    name="App",
    input="views/app.tutu",
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
      #|spec:
      #|  protocol Openable = "tutuca.dev/std/Openable@1":
      #|    message setOpen(Bool)
      #|
      #|  Node:
      #|    field open :: Bool
      #|    implements Openable
      #|    message Openable::setOpen(Bool)
      #|
      #|logic:
      #|  Node:
      #|    receive Openable::setOpen(b):
      #|      it.open := b
      #|
      #|view:
      #|  Node:
      #|    b():
      #|      @(it.open)
    ),
    name="Node",
    input="views/node.tutu",
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
      #|spec:
      #|  protocol Openable = "tutuca.dev/std/Openable@1":
      #|    message setOpen(Bool)
      #|
      #|  Node:
      #|    field open :: Bool
      #|    implements Openable
      #|    message Openable::SetOpen(Bool)
      #|
      #|view:
      #|  Node:
      #|    b():
      #|      @(it.open)
    ),
    name="Node",
    input="views/node.tutu",
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
      #|spec:
      #|  Thermostat:
      #|    field target :: Int
      #|    message Init
      #|    message Nudge(Int)
      #|    intent SetMode(String)
      #|
      #|view:
      #|  Thermostat:
      #|    button(~on_click: init):
      #|      "go"
    ),
    name="Thermostat",
    input="views/thermostat.tutu",
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
      #|spec:
      #|  Thermostat:
      #|    field target :: Int
      #|    message init
      #|    message nudge(Int)
      #|
      #|view:
      #|  Thermostat:
      #|    button(~on_click: init):
      #|      "go"
    ),
    name="Thermostat",
    input="views/thermostat.tutu",
    target="views/thermostat_view_gen.mbt",
    ir=false,
  )
  guard! r is Ok(plan)
  assert_eq(plan.diagnostics, [])
}

///|
test "a clean view produces no diagnostics" {
  let r = @cli.gen_views(
    "view:\n  Clean:\n    div():\n      button(~on_click: go):\n        \"x\"\n",
    name="Clean",
    input="views/clean.tutu",
    target="views/clean_view_gen.mbt",
    ir=false,
  )
  guard! r is Ok(plan)
  assert_eq(plan.diagnostics, [])
}

///|
test "a batch names every file that failed, and writes none of them" {
  // The defect this covers: `gen src/` returned on the FIRST bad file, so
  // a directory with three problems took three builds to even see the three —
  // and wrote nothing in the meantime, including for the files that had
  // already compiled.
  let r = @cli.gen_views_all(
    [
      {
        input: "views/a.tutu",
        target: "views/a_view_gen.mbt",
        name: "A",
        source: "view:\n  A:\n    @div{@each(v in it.rows, ~when: nope()){@p{x}}}\n",
      },
      {
        input: "views/b.tutu",
        target: "views/b_view_gen.mbt",
        name: "B",
        source: "view:\n  B:\n    button(~on_click: go):\n      \"x\"\n",
      },
      {
        input: "views/c.tutu",
        target: "views/c_view_gen.mbt",
        name: "C",
        source: "view:\n  C:\n    @div{@each(v in it.rows, ~when: nor()){@p{x}}}\n",
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
  assert_true(shape.message.contains("  views/a.tutu: "))
  assert_true(shape.message.contains("  views/c.tutu: "))
  // The file that DID compile is not in the message — and there is no plan to
  // write it from, which is the atomicity half.
  assert_true(!shape.message.contains("views/b.tutu"))
}

///|
test "one failing file in a batch still reads as one file" {
  // `where_` has one slot, so it says something only when there is one thing
  // to say — and then the message is what a single-file run has always given.
  let r = @cli.gen_views_all(
    [
      {
        input: "views/a.tutu",
        target: "views/a_view_gen.mbt",
        name: "A",
        source: "view:\n  A:\n    button(~on_click: go):\n      \"x\"\n",
      },
      {
        input: "views/b.tutu",
        target: "views/b_view_gen.mbt",
        name: "B",
        source: "view:\n  B:\n    @div{@each(v in it.rows, ~when: nope()){@p{x}}}\n",
      },
    ],
    ir=false,
  )
  guard! r is Err(shape)
  debug_inspect(shape.where_, content="Some(\"views/b.tutu\")")
  assert_true(shape.message.has_prefix("views/b.tutu: "), msg=shape.message)
}

///|
test "a file that does not read stops the batch before the emit pass" {
  // A file that did not read is a hole in the component table, and the emit
  // pass reads that table — so a cross-file reference below it would report a
  // SECOND problem that is an artefact of the first. Read failures are
  // answered on their own.
  let r = @cli.gen_views_all(
    [
      {
        input: "views/bad.tutu",
        target: "views/bad_view_gen.mbt",
        name: "Bad",
        source: "spec:\n  Bad:\n    field n :: Nope\n\nview:\n  Bad:\n    b():\n      \"x\"\n",
      },
      {
        input: "views/uses.tutu",
        target: "views/uses_view_gen.mbt",
        name: "Uses",
        source: "view:\n  Uses:\n    card()\n",
      },
    ],
    ir=false,
  )
  guard! r is Err(shape)
  inspect(shape.code, content="ERR_VIEW_GEN_FAILED")
  // The read failure, alone and named — `uses.tutu` is never emitted, so it
  // says nothing about the macro the hole would have hidden.
  debug_inspect(shape.where_, content="Some(\"views/bad.tutu\")")
  assert_true(shape.message.contains("Nope"), msg=shape.message)
  assert_true(!shape.message.contains("views/uses.tutu"))
}

///|
/// `gen` does NOT report a stale mutator, and this pins the reason rather than
/// the absence.
///
/// The component below is the shape that made 0.49.5's version wrong: a script
/// block that answers SOME of its names, with the rest answered in MoonBit
/// because they must also do something a script arm cannot express. The block's
/// presence was read as "every handler is here", which is true of a card and
/// false of a compiled component — `gen` reads .html and the missing arm is in
/// .mbt. Warning here named `.name = v` as the repair, which is the bug the
/// author avoided by declaring `name` a message rather than a writable
/// property.
///
/// The check still runs where it is decidable: `tgc`'s card backend, where
/// there is no MoonBit for an arm to hide in.
test "gen does not guess at a handler it cannot see" {
  let r = @cli.gen_views(
    (
      #|spec:
      #|  Editor:
      #|    field name :: String
      #|    field nameError :: String
      #|    message save
      #|    message setName(String)
      #|
      #|logic:
      #|  Editor:
      #|    receive save:
      #|      it.nameError := ""
      #|
      #|view:
      #|  Editor:
      #|    input(~on_input: setName(e.value))
      #|    button(~on_click: save):
      #|      "s"
    ),
    name="Editor",
    input="views/editor.tutu",
    target="views/editor_view_gen.mbt",
    ir=false,
  )
  guard! r is Ok(plan)
  assert_eq(plan.diagnostics.filter(d => d.contains("STALE_MUTATOR")), [])
}
