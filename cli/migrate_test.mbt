// The codemod, and — more importantly — what it refuses.
//
// A tool that is 95% right on 500 sites leaves 25 broken ones in a diff nobody
// reads, so the tests that matter here are the ones asserting a file was left
// EXACTLY as it was. `files` empty and `refused` non-empty is the shape of a
// correct answer, not of a failure.

///|
fn mig(path : String, src : String) -> @cli.MigratePlan {
  @cli.migrate_source(path, src)
}

///|
/// The rewritten text, or "" when nothing was rewritten.
fn rewritten(p : @cli.MigratePlan) -> String {
  match p.files.get(0) {
    Some(f) => f.1
    None => ""
  }
}

// -- the block language ------------------------------------------------------

///|
test "on becomes receive and bubble becomes intent" {
  let src =
    #|<script type="tutuca/script">
    #|  on inc { .count += 1 }
    #|  bubble rowPicked(k) { .last = k }
    #|</script>
    #|<template id="C"><div></div></template>
  let out = rewritten(mig("c.html", src))
  assert_true(out.contains("receive inc {"))
  assert_true(out.contains("intent rowPicked(k) {"))
  assert_false(out.contains("on inc"))
  assert_false(out.contains("bubble rowPicked"))
}

///|
test "a bubble effect becomes intent dyn, and a request becomes intent lex" {
  // The design's claim, as a rewrite: the ROUTE says which scope answers, where
  // v1's verb said it. Nothing else about the statement moves.
  let src =
    #|<script type="tutuca/script">
    #|  on go(k) { bubble 'rowPicked' k }
    #|  on load { request 'loadRows' .query }
    #|</script>
    #|<template id="C"><div></div></template>
  let out = rewritten(mig("c.html", src))
  assert_true(out.contains("intent dyn 'rowPicked' k"))
  assert_true(out.contains("intent lex 'loadRows' .query"))
}

///|
test "an effect inside a branch moves too" {
  // A `bubble` inside an `if` is as much a bubble as one at the top, and a
  // rewrite that only walked the top level would leave it behind.
  let src =
    #|<script type="tutuca/script">
    #|  on go(k) {
    #|    if k { bubble 'yes' k } else { request 'no' }
    #|  }
    #|</script>
    #|<template id="C"><div></div></template>
  let out = rewritten(mig("c.html", src))
  assert_true(out.contains("intent dyn 'yes' k"))
  assert_true(out.contains("intent lex 'no'"))
}

// -- the refusals ------------------------------------------------------------

///|
test "a response arm is refused, and the file is untouched" {
  // THE refusal. `response load(res, err)` becomes `receive loadOk(res)` and
  // `receive loadError(err)`, and which half of the body belongs to which is a
  // reading of the code rather than a transformation of it.
  let src =
    #|<script type="tutuca/script">
    #|  on go { request 'load' }
    #|  response load(res, err) { .rows = res }
    #|</script>
    #|<template id="C"><div></div></template>
  let p = mig("c.html", src)
  assert_eq(p.files.length(), 0)
  assert_eq(p.refused.length(), 1)
  assert_true(p.refused[0].contains("becomes two `receive` arms"))
  assert_true(p.refused[0].contains("loadOk"))
  // ...and the `on go` above it was NOT rewritten, which is the whole point:
  // the file is refused WHOLE.
  assert_eq(rewritten(p), "")
}

///|
test "a response variant in the state block is refused" {
  let src =
    #|<script type="tutuca/state">
    #|  state C { rows: Array[Any] }
    #|  response C { LoadRows(Array[Any]) }
    #|</script>
    #|<template id="C"><div></div></template>
  let p = mig("c.html", src)
  assert_eq(p.files.length(), 0)
  assert_eq(p.refused.length(), 1)
  assert_true(p.refused[0].contains("`response` variant"))
}

///|
test "a script block that does not parse refuses the file rather than guessing" {
  let src =
    #|<script type="tutuca/script">
    #|  on go { .count += }
    #|</script>
    #|<template id="C"><div></div></template>
  let p = mig("c.html", src)
  assert_eq(p.files.length(), 0)
  assert_eq(p.refused.length(), 1)
  assert_true(p.refused[0].contains("does not parse"))
}

// -- the state block ---------------------------------------------------------

///|
test "a bubble variant becomes an intent variant, keeping its indentation" {
  let src =
    #|<script type="tutuca/state">
    #|  state C { rows: Array[Any] }
    #|  bubble  C { RowPicked(Int) }
    #|</script>
    #|<template id="C"><div></div></template>
  let out = rewritten(mig("c.html", src))
  assert_true(out.contains("  intent  C { RowPicked(Int) }"))
  assert_false(out.contains("bubble  C"))
}

///|
test "the word bubble away from a declaration position is left alone" {
  // The keyword is the first word of a declaration. A field called `bubbles`,
  // or the word inside a doc comment, is not one — and a substitution that did
  // not care would rewrite both.
  let src =
    #|<script type="tutuca/state">
    #|  /// this component bubbles a lot
    #|  state C { bubbles: Int }
    #|</script>
    #|<template id="C"><div></div></template>
  let out = rewritten(mig("c.html", src))
  // Nothing changed at all, so no file comes back.
  assert_eq(out, "")
}

// -- the views ---------------------------------------------------------------

///|
test "an event accessor in an argument slot gains e." {
  let src =
    #|<template id="C">
    #|  <input @on.input="setQuery value">
    #|  <button @on.click="pick @key">x</button>
    #|  <div @on.keydown="go key isCtrl"></div>
    #|</template>
  let out = rewritten(mig("c.html", src))
  assert_true(out.contains("@on.input=\"setQuery e.value\""))
  assert_true(out.contains("@on.click=\"pick @key\""))
  assert_true(out.contains("@on.keydown=\"go e.key e.isCtrl\""))
}

///|
test "the handler name stays bare — it is the one unprefixed name v2 keeps" {
  // A handler happening to be CALLED `value` is still the message name, and
  // the first token is never an argument.
  let src =
    #|<template id="C"><input @on.input="value value"></template>
  let out = rewritten(mig("c.html", src))
  assert_true(out.contains("@on.input=\"value e.value\""))
}

///|
test "a literal, a field and a bind are left alone" {
  let src =
    #|<template id="C">
    #|  <button @on.click="add 1">+</button>
    #|  <button @on.click="save .draft">s</button>
    #|  <button @on.click="pick @value">p</button>
    #|  <button @on.click="go 'x' true">g</button>
    #|</template>
  let p = mig("c.html", src)
  assert_eq(p.files.length(), 0)
  assert_eq(p.reports.length(), 0)
}

///|
test "a bare name that is not an accessor is reported, not rewritten" {
  // A latent v1 bug the rewrite surfaces: it read as Null at run time, and the
  // tool cannot know what it was meant to be.
  let src =
    #|<template id="C"><button @on.click="go nonsense">x</button></template>
  let p = mig("c.html", src)
  assert_eq(p.reports.length(), 1)
  assert_true(p.reports[0].contains("`nonsense` is a bare name"))
  assert_true(p.reports[0].contains("read as Null"))
  // Reported, and left exactly as it was.
  assert_eq(p.files.length(), 0)
}

// -- .mbt --------------------------------------------------------------------

///|
test "the dispatch arms move" {
  let src =
    #|match msg {
    #|  Input("inc", _) => Next(s)
    #|  Bubble("rowPicked", [k]) => Next(s)
    #|  _ => Unhandled
    #|}
  let out = rewritten(mig("c.mbt", src))
  assert_true(out.contains("Receive(\"inc\", _)"))
  assert_true(out.contains("Intent(\"rowPicked\", [k])"))
}

///|
test "a Response arm refuses the file" {
  let src =
    #|match msg {
    #|  Response("load", [res, err]) => Next(s)
    #|  _ => Unhandled
    #|}
  let p = mig("c.mbt", src)
  assert_eq(p.files.length(), 0)
  assert_eq(p.refused.length(), 1)
  assert_true(p.refused[0].contains("two `Receive` arms"))
}

///|
test "on_res_name refuses the file, because v2 has no field for it" {
  let src = "ctx.request(\"x\", [], RequestOpts::new(on_res_name=\"y\"))"
  let p = mig("c.mbt", src)
  assert_eq(p.files.length(), 0)
  assert_true(p.refused[0].contains("on_res_name"))
}

///|
test "a ctx.send is reported, because the widening changed what it does" {
  // v1 dropped a `ctx.send` naming a generated mutator; v2 mutates. The tool
  // cannot tell which names are mutators without the schema, so it says so
  // rather than guessing.
  let src = "ctx.send(\"setQuery\", [Str(\"x\")])"
  let p = mig("c.mbt", src)
  assert_eq(p.reports.length(), 1)
  assert_true(p.reports[0].contains("GENERATED MUTATOR"))
}

///|
test "ctx.bubble gains the dyn route, and the parens are matched" {
  // The closing paren is found by matching, not by scanning to the next `)`:
  // an argument list holds calls of its own.
  let out = rewritten(mig("c.mbt", "ctx.bubble(\"picked\", [k])"))
  assert_eq(
    out, "ctx.intent(\"picked\", [k], @tutuca.IntentOpts::new(route=[Dyn]))",
  )
  let nested = rewritten(mig("c.mbt", "ctx.bubble(\"x\", [f(g(1)), 2])"))
  assert_eq(
    nested, "ctx.intent(\"x\", [f(g(1)), 2], @tutuca.IntentOpts::new(route=[Dyn]))",
  )
  // Two in one file, and the second is found after the first has moved.
  let two = rewritten(
    mig("c.mbt", "ctx.bubble(\"a\", [])\nctx.bubble(\"b\", [])"),
  )
  assert_eq(two.split("IntentOpts").collect().length(), 3)
}

///|
test "an unbalanced call refuses the file rather than half-editing it" {
  let p = mig("c.mbt", "ctx.bubble(\"x\", [k]")
  assert_eq(p.files.length(), 0)
  assert_eq(p.refused.length(), 1)
  assert_true(p.refused[0].contains("do not balance"))
}

///|
test "a generated file is never edited" {
  // `AGENTS.md` is explicit, and the reason applies exactly to a codemod: an
  // edit here survives until the next `gen-views` and then silently does not.
  // The SOURCE moves and the generator re-runs.
  let src = "match msg { Input(\"inc\", _) => Next(s) }"
  assert_eq(mig("counter_view_gen.mbt", src).files.length(), 0)
  assert_eq(mig("counter_view_ir_gen.mbt", src).files.length(), 0)
  // ...and the same file under a hand-written name does move.
  assert_eq(mig("counter.mbt", src).files.length(), 1)
}

///|
test "a file with nothing to migrate comes back with nothing" {
  assert_eq(mig("c.mbt", "let x = 1\n").files.length(), 0)
  assert_eq(
    mig("c.html", "<template id=\"C\"><div></div></template>").files.length(),
    0,
  )
  // A path the tool does not handle is not an error, it is not its business.
  assert_eq(mig("README.md", "on bubble response").files.length(), 0)
}
