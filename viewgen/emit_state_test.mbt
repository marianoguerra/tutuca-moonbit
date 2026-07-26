// The state half of the generated module.
//
// Snapshots, like emit_test.mbt: the generated text IS the contract, and a
// diff here is a deliberate change to what every migrated component gets.

///|
let counter_state_html : String =
  #|<script type="tutuca/state">
  #|  interface counter {
  #|    record state {
  #|      label: string,
  #|      count: s32,
  #|      history: list<s32>,
  #|    }
  #|  }
  #|</script>
  #|
  #|<template>
  #|  <h1><x text=".label"></x>: <x text=".count"></x></h1>
  #|</template>

///|
test "a state block emits the struct, its zero and its field table" {
  let file = @viewgen.split_file(counter_state_html)
  assert_eq(file.state.length(), 1)
  assert_eq(file.state[0].component, "Counter")
  let src = @viewgen.emit_module("Counter", "counter.html", file)
  // The struct the author no longer writes.
  assert_true(src.contains("priv struct CounterState {"))
  assert_true(src.contains("  label : String"))
  assert_true(src.contains("  count : Int"))
  assert_true(src.contains("  history : Array[Int]"))
  assert_true(src.contains("} derive(ToJson, FromJson)"))
  // The zero, so `init` spreads it and names only what differs. Package-
  // private like the struct: a public function may not depend on a private
  // type.
  assert_true(src.contains("\nfn CounterState::zero() -> CounterState {"))
  assert_true(src.contains("label: \"\","))
  assert_true(src.contains("count: 0,"))
  assert_true(src.contains("history: [],"))
  // The declared field kinds — `count` is FInt because the schema says s32,
  // not because the seed value happened to be integral.
  assert_true(src.contains("Count => @component.FInt"))
  assert_true(src.contains("History => @component.FList"))
  assert_true(src.contains("Label => @component.FText"))
}

///|
test "a file with no state block generates exactly what it did before" {
  let without =
    #|<template>
    #|  <h1><x text=".label"></x></h1>
    #|</template>
  let file = @viewgen.split_file(without)
  assert_eq(file.state.length(), 0)
  let src = @viewgen.emit_module("Counter", "counter.html", file)
  // Nothing from the state half leaks into an unmigrated file — this is what
  // lets the view files migrate one at a time.
  assert_false(src.contains("priv struct CounterState"))
  assert_false(src.contains("CounterField"))
  assert_false(src.contains("counter_specs"))
  // ...and the view half is untouched.
  assert_true(src.contains("pub(all) enum CounterView {"))
}

///|
test "sets, ordered maps and child slots become the specs map" {
  let html =
    #|<script type="tutuca/state">
    #|  interface card {
    #|    record state { title: string }
    #|  }
    #|  interface board {
    #|    flags visibility { done, active }
    #|    record state {
    #|      vis: visibility,
    #|      tags: text-set,
    #|      order: value-omap,
    #|      lead: card,
    #|      plain: string,
    #|    }
    #|  }
    #|</script>
    #|
    #|<template id="Card"><p><x text=".title"></x></p></template>
    #|<template id="Board"><div><x render=".lead"></x></div></template>
  let src = @viewgen.emit_module(
    "Ignored",
    "board.html",
    @viewgen.split_file(html),
  )
  // Every kind the runtime cannot infer from an encoded init value, and
  // nothing else: `plain` is a String, which FieldSpec::of_default gets right.
  assert_true(
    src.contains(
      "\"vis\": @component.FieldSpec::set(members=[\"done\", \"active\"])",
    ),
  )
  assert_true(src.contains("\"tags\": @component.FieldSpec::set()"))
  assert_true(src.contains("\"order\": @component.FieldSpec::omap()"))
  assert_true(src.contains("\"lead\": @component.FieldSpec::comp(\"Card\")"))
  assert_false(src.contains("\"plain\": @component.FieldSpec"))
  // Two components, two states.
  assert_true(src.contains("priv struct CardState {"))
  assert_true(src.contains("priv struct BoardState {"))
}

///|
test "named types become MoonBit types, and a keyword field escapes" {
  let html =
    #|<script type="tutuca/state">
    #|  interface editor {
    #|    enum mode { view, edit }
    #|    record item { title: string, done: bool }
    #|    record state { m: mode, items: list<item>, %type: string }
    #|  }
    #|</script>
    #|<template><p><x text=".m"></x></p></template>
  let src = @viewgen.emit_module(
    "Editor",
    "editor.html",
    @viewgen.split_file(html),
  )
  assert_true(src.contains("priv enum EditorMode {"))
  assert_true(src.contains("priv struct EditorItem {"))
  assert_true(src.contains("  items : Array[EditorItem]"))
  assert_true(src.contains("m: EditorMode::View,"))
  // The runtime name stays `type` — it is what the view and the JSON use —
  // so only the MoonBit binding bends, and the derive puts the name back on
  // the wire.
  assert_true(src.contains("  type_ : String"))
  assert_true(
    src.contains(
      "} derive(ToJson(fields(type_(rename=\"type\"))), FromJson(fields(type_(rename=\"type\"))))",
    ),
  )
}

///|
test "a schema for a component the file does not declare is an error" {
  let html =
    #|<script type="tutuca/state">
    #|  interface countr { record state { n: s32 } }
    #|</script>
    #|<template><p>hi</p></template>
  let file = @viewgen.split_file(html)
  try @viewgen.emit_module("Counter", "c.html", file) |> ignore catch {
    e => {
      assert_true(e.message().contains("Countr"))
      assert_true(e.message().contains("no <template>"))
    }
  } noraise {
    _ => fail("expected the orphan schema to be reported")
  }
}

///|
test "a schema error points at the line in the HTML file" {
  let html =
    #|<template><p>hi</p></template>
    #|
    #|<script type="tutuca/state">
    #|  interface counter {
    #|    record state {
    #|      n: s64,
    #|    }
    #|  }
    #|</script>
  try @viewgen.split_file(html) |> ignore catch {
    BadStateBlock(line~, message~) => {
      // `n: s64` is on line 6 of the file, not line 3 of the block: the
      // author has the HTML file open, not the slice we cut out of it.
      assert_eq(line, 6)
      assert_true(message.contains("2^53"))
    }
    e => fail("expected a state-block error, got \{e.message()}")
  } noraise {
    _ => fail("expected a state-block error")
  }
}

///|
test "two state blocks in one file are refused" {
  let html =
    #|<script type="tutuca/state">
    #|  interface a { record state { n: s32 } }
    #|</script>
    #|<script type="tutuca/state">
    #|  interface b { record state { n: s32 } }
    #|</script>
    #|<template><p>hi</p></template>
  try @viewgen.split_file(html) |> ignore catch {
    e => assert_true(e.message().contains("one file declares one schema"))
  } noraise {
    _ => fail("expected the duplicate block to be reported")
  }
}

///|
test "the block's angle brackets survive the HTML tokenizer" {
  // The reason the schema rides in a <script> and not a <template>: an HTML
  // parser reads template content as markup, so `list<s32>` would become an
  // `<s32>` element and `option<string>` an `<string>` one.
  let html =
    #|<script type="tutuca/state">
    #|  interface c {
    #|    record state { a: list<s32>, b: option<string>, c: tuple<s32, bool> }
    #|  }
    #|</script>
    #|<template><p>hi</p></template>
  let file = @viewgen.split_file(html)
  assert_eq(file.state.length(), 1)
  assert_eq(file.state[0].fields.map(f => f.name), ["a", "b", "c"])
  let src = @viewgen.emit_module("C", "c.html", file)
  assert_true(src.contains("  a : Array[Int]"))
  assert_true(src.contains("  b : String?"))
  assert_true(src.contains("  c : (Int, Bool)"))
}
