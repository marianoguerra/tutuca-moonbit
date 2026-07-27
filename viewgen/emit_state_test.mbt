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
test "a state block emits the struct, its zero and its declared field kinds" {
  let file = @viewgen.split_file(counter_state_html)
  assert_eq(file.state.length(), 1)
  assert_eq(file.state[0].component, "Counter")
  let src = @viewgen.emit_module("Counter", "counter.html", file)
  // The struct the author no longer writes.
  assert_true(src.contains("pub(all) struct CounterState {"))
  assert_true(src.contains("  label : String"))
  assert_true(src.contains("  count : Int"))
  assert_true(src.contains("  history : Array[Int]"))
  // No `derive(ToJson, FromJson)`: the state struct is a plain struct now.
  // The generated codec does the conversion, and there is no JSON bridge left
  // for a derive to serve.
  assert_false(src.contains("derive(ToJson"))
  // The zero, so `init` spreads it and names only what differs. Public,
  // because a file with no generated `component()` wrapper has nothing else to
  // default `init~` from.
  assert_true(src.contains("\npub fn CounterState::zero() -> CounterState {"))
  assert_true(src.contains("label: \"\","))
  assert_true(src.contains("count: 0,"))
  assert_true(src.contains("history: [],"))
  // The declared field kinds — `count` is FInt because the schema says s32,
  // not because the seed value happened to be integral.
  //
  // Asserted on the descriptor and not on a `CounterField` enum: the kinds have
  // exactly one home now, and it is the one an inspector holding a bare
  // `@tutuca.Value` can read.
  assert_false(src.contains("enum CounterField"))
  assert_true(src.contains("FieldInfo::new(\"count\", \"s32\", FInt)"))
  assert_true(src.contains("FieldInfo::new(\"label\", \"string\", FText)"))
  assert_true(
    src.contains(
      "FieldInfo::new(\"history\", \"list<s32>\", FList, elem=\"s32\")",
    ),
  )
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
  assert_false(src.contains("pub(all) struct CounterState"))
  assert_false(src.contains("CounterState::zero"))
  assert_false(src.contains("counter_specs"))
  assert_false(src.contains("SchemaInfo::new"))
  // ...and the view half is untouched.
  assert_true(src.contains("pub let counter_common_style"))
}

///|
test "sets, ordered maps and child slots are described in the schema" {
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
  // Every field is described, with the things a runtime spec has no room
  // for: the WIT spelling, a collection's element type, the component a slot
  // holds, and a `flags` set's declared membership.
  // Each field is one `FieldInfo::new` call: the trimming constructor states
  // the parts this field HAS and writes no line for the ones it does not.
  assert_true(src.contains("\"vis\", \"visibility\", FSet"))
  assert_true(src.contains("members=[\"done\", \"active\"]"))
  assert_true(src.contains("\"tags\", \"text-set\", FSet"))
  assert_true(src.contains("\"order\", \"an ordered map of any\", FOMap"))
  assert_true(src.contains("slot=\"Card\""))
  // ...and a plain field is described too — the descriptor is the whole
  // schema, not only the parts the runtime would get wrong.
  assert_true(src.contains("\"plain\", \"string\", FText"))
  // Two components, two states.
  assert_true(src.contains("pub(all) struct CardState {"))
  assert_true(src.contains("pub(all) struct BoardState {"))
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
  // `pub(all)`, like the rest of the generated vocabulary: an `update` matches
  // these and a test constructs them.
  assert_true(src.contains("pub(all) enum EditorMode {"))
  assert_true(src.contains("pub(all) struct EditorItem {"))
  assert_true(src.contains("  items : Array[EditorItem]"))
  assert_true(src.contains("m: EditorMode::View,"))
  // The runtime name stays `type` — it is what the view reads and what the
  // fields map carries — so only the MoonBit binding bends. It used to take a
  // `derive(ToJson(fields(type_(rename="type"))))` to put the name back; the
  // codec keys by the runtime name directly, so there is no derive at all.
  assert_true(src.contains("  type_ : String"))
  assert_false(src.contains("derive(ToJson"))
  assert_true(src.contains("\"type\": Str(s.type_)"))
}

///|
test "a schema interface with no template declares state anyway" {
  // Legitimate: a component whose views are built in MoonBit still wants a
  // state type, and one file often holds both kinds. It is ALSO what a
  // mistyped interface name looks like, so the CLI reports it on its
  // non-fatal diagnostic channel rather than failing generation.
  let html =
    #|<script type="tutuca/state">
    #|  interface countr { record state { n: s32 } }
    #|</script>
    #|<template><p>hi</p></template>
  let file = @viewgen.split_file(html)
  assert_eq(@viewgen.declared_components(file, "Counter"), ["Counter"])
  let src = @viewgen.emit_module("Counter", "c.html", file)
  // The state is generated...
  assert_true(src.contains("pub(all) struct CountrState {"))
  // ...but no view surface is invented for it.
  assert_false(src.contains("CountrView"))
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

///|
test "a schema-only file declares state for views built at runtime" {
  // No <template> at all. This is how a component whose views are assembled
  // in MoonBit — a macro user, a dynamically built tree — still gets a
  // generated state type: the schema lives in a view file, so it needs a
  // view file even when it has no views.
  let html =
    #|<script type="tutuca/state">
    #|  interface bar-chart {
    #|    record state { title: string, values: values }
    #|  }
    #|</script>
  let file = @viewgen.split_file(html)
  assert_eq(file.components.length(), 0)
  assert_eq(file.state.length(), 1)
  let src = @viewgen.emit_module("BarChart", "bar_chart.html", file)
  assert_true(src.contains("pub(all) struct BarChartState {"))
  assert_true(src.contains("FieldInfo::new(\"title\", \"string\", FText)"))
  // ...and NO view surface: there are no views to describe, and the schema
  // block itself must not become one.
  assert_false(src.contains("bar_chart_common_style"))
  assert_false(src.contains("bar_chart_views"))
  assert_false(src.contains("@anode"))
  assert_false(src.contains("script"))
  // There is no tree to compile either, so the IR module is simply absent.
  assert_true(@viewgen.emit_ir_module_opt("BarChart", "b.html", file) is None)
}

///|
test "a schema block is lifted out of a file that is its own main view" {
  // A file with no <template> IS the main view. The schema must not end up
  // inside it — before the block was lifted like a <style>, it compiled to a
  // literal <script> element in the view tree.
  let html =
    #|<script type="tutuca/state">
    #|  interface widget { record state { n: s32 } }
    #|</script>
    #|<p><x text=".n"></x></p>
  let file = @viewgen.split_file(html)
  assert_eq(file.components.length(), 1)
  let view = file.components[0].views[0]
  assert_false(view.source.contains("script"))
  assert_false(view.source.contains("interface widget"))
  assert_true(view.source.contains("<x text=\".n\">"))
}
