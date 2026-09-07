// The state half of the generated module.
//
// Snapshots, like emit_test.mbt: the generated text IS the contract, and a
// diff here is a deliberate change to what every migrated component gets.

///|
let counter_state_src : String =
  #|spec:
  #|  Counter:
  #|    field label :: String
  #|    field count :: Int
  #|    field history :: List.of(Int)
  #|
  #|view:
  #|  Counter:
  #|    h1():
  #|      @(it.label)
  #|      ": "
  #|      @(it.count)

///|
test "a `spec:` section emits the struct, its zero and its field kinds" {
  let file = @viewgen.read_file(counter_state_src)
  assert_eq(file.state.length(), 1)
  assert_eq(file.state[0].component, "Counter")
  let src = @viewgen.emit_module("Counter", "counter.tutu", file)
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
  // default `initial~` from.
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
  assert_true(
    src.contains("FieldInfo::new(\"count\", TyInt(width=32, signed=true))"),
  )
  assert_true(src.contains("FieldInfo::new(\"label\", TyText)"))
  // Structural, not two strings: a reader can descend into the list.
  assert_true(
    src.contains(
      "FieldInfo::new(\"history\", TyList(TyInt(width=32, signed=true)))",
    ),
  )
}

///|
test "a file with no `spec:` section generates only the view half" {
  let without =
    #|view:
    #|  Counter:
    #|    h1():
    #|      @(it.label)
  let file = @viewgen.read_file(without)
  assert_eq(file.state.length(), 0)
  let src = @viewgen.emit_module("Counter", "counter.tutu", file)
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
  let src = @viewgen.emit_module(
    "Ignored",
    "board.tutu",
    @viewgen.read_file(
      (
        #|spec:
        #|  enum Visibility:
        #|    Done
        #|    Active
        #|
        #|  Card:
        #|    field title :: String
        #|
        #|  Board:
        #|    field vis :: Set.of(Visibility)
        #|    field tags :: Set.of(String)
        #|    field order :: Map.of(String, Any)
        #|    field lead :: Instance.of(Card)
        #|    field plain :: String
        #|
        #|view:
        #|  Card:
        #|    p():
        #|      @(it.title)
        #|
        #|  Board:
        #|    div():
        #|      render(it.lead)
      ),
    ),
  )
  // Every field is described by its TYPE, and the things a runtime spec has
  // no room for follow from it: the WIT spelling, a collection's element type,
  // the component a slot holds, and a closed set's declared membership.
  //
  // A closed set inlines its members, because the declaration they name does
  // not exist at runtime; an open one has none to inline, which is a real
  // answer and a different one.
  assert_true(
    src.contains("\"vis\", TyFlags(\"Visibility\", [\"Done\", \"Active\"])"),
  )
  assert_true(src.contains("\"tags\", TySet"))
  assert_true(src.contains("\"order\", TyOMap(TyAny)"))
  assert_true(src.contains("\"lead\", TyComp(Some(\"Card\"))"))
  // ...and a plain field is described too — the descriptor is the whole
  // schema, not only the parts the runtime would get wrong.
  assert_true(src.contains("\"plain\", TyText"))
  // Two components, two states.
  assert_true(src.contains("pub(all) struct CardState {"))
  assert_true(src.contains("pub(all) struct BoardState {"))
}

///|
test "named types become MoonBit types, and a keyword field escapes" {
  let src = @viewgen.emit_module(
    "Editor",
    "editor.tutu",
    @viewgen.read_file(
      (
        #|spec:
        #|  enum Mode:
        #|    View
        #|    Edit
        #|
        #|  struct Item(title :: String, done :: Bool)
        #|
        #|  Editor:
        #|    field m :: Mode
        #|    field items :: List.of(Item)
        #|    field type :: String
        #|
        #|view:
        #|  Editor:
        #|    p():
        #|      @(it.m)
      ),
    ),
  )
  // `pub(all)`, like the rest of the generated vocabulary: an `update` matches
  // these and a test constructs them.
  assert_true(src.contains("pub(all) enum EditorMode {"))
  assert_true(src.contains("pub(all) struct EditorItem {"))
  assert_true(src.contains("  items : Array[EditorItem]"))
  // Bare, not `EditorMode::View`: the zero sits in a field of the state struct
  // whose type is already known (see `StateDef::zero_expr`).
  assert_true(src.contains("m: View,"))
  // The runtime name stays `type` — it is what the view reads and what the
  // fields map carries — so only the MoonBit binding bends.
  assert_true(src.contains("  type_ : String"))
  assert_false(src.contains("derive(ToJson"))
  assert_true(src.contains("\"type\": Str(s.type_)"))
}

///|
test "a `spec:` entry with no view declares state anyway" {
  // Legitimate: a component whose views are built in MoonBit still wants a
  // state type, and one file often holds both kinds. It is ALSO what a
  // mistyped component name looks like, so the CLI reports it on its
  // non-fatal diagnostic channel rather than failing generation.
  let file = @viewgen.read_file(
    "spec:\n  Countr:\n    field n :: Int\n\nview:\n  Counter:\n    p():\n      \"hi\"\n",
  )
  assert_eq(@viewgen.declared_components(file, "Counter"), ["Counter"])
  let src = @viewgen.emit_module("Counter", "c.tutu", file)
  // The state is generated...
  assert_true(src.contains("pub(all) struct CountrState {"))
  // ...but no view surface is invented for it.
  assert_false(src.contains("CountrView"))
}

///|
test "a `spec:` error names the repair" {
  // The reader points at the declaration, and says what to write instead —
  // `Int64` is the one integer type the value layer cannot carry, and a
  // verdict with no next step is a finding an author has to go and derive.
  let msg = try {
    @viewgen.read_file(
      "spec:\n  Counter:\n    field n :: Int64\n\nview:\n  Counter:\n    p():\n      \"hi\"\n",
    )
    |> ignore
    "no error"
  } catch {
    e => @viewgen.GenError::message(e)
  }
  assert_true(msg.contains("2^53"), msg~)
}

///|
test "two `spec:` sections in one file are refused" {
  let src =
    #|spec:
    #|  A:
    #|    field n :: Int
    #|
    #|spec:
    #|  B:
    #|    field n :: Int
    #|
    #|view:
    #|  A:
    #|    p(): "hi"
  let msg = try {
    @viewgen.read_file(src) |> ignore
    "no error"
  } catch {
    e => @viewgen.GenError::message(e)
  }
  assert_true(msg.contains("twice"), msg~)
}

///|
test "a compound type reads as the type it spells" {
  // The reason the old notation put the schema in a `<script>` rather than a
  // `<template>`: an HTML parser reads template content as markup, so
  // `Array[Int]` became an `<Int>` element. There is no tokenizer between the
  // file and the reader now, so a type is read as written.
  let file = @viewgen.read_file(
    (
      #|spec:
      #|  C:
      #|    field a :: List.of(Int)
      #|    field b :: maybe(String)
      #|    field c :: Tuple.of(Int, Bool)
      #|
      #|view:
      #|  C:
      #|    p():
      #|      "hi"
    ),
  )
  assert_eq(file.state.length(), 1)
  assert_eq(file.state[0].fields.map(f => f.name), ["a", "b", "c"])
  let src = @viewgen.emit_module("C", "c.tutu", file)
  assert_true(src.contains("  a : Array[Int]"))
  assert_true(src.contains("  b : String?"))
  assert_true(src.contains("  c : (Int, Bool)"))
}

///|
test "a spec-only file declares state for views built at runtime" {
  // No `view:` section at all. This is how a component whose views are
  // assembled in MoonBit — a macro user, a dynamically built tree — still gets
  // a generated state type: the schema lives in a view file, so it needs a
  // view file even when it has no views.
  let file = @viewgen.read_file(
    (
      #|spec:
      #|  BarChart:
      #|    field title :: String
      #|    field values :: List.of(Any)
    ),
  )
  assert_eq(file.components.length(), 0)
  assert_eq(file.state.length(), 1)
  let src = @viewgen.emit_module("BarChart", "bar_chart.tutu", file)
  assert_true(src.contains("pub(all) struct BarChartState {"))
  assert_true(src.contains("FieldInfo::new(\"title\", TyText)"))
  // ...and NO view surface: there are no views to describe.
  assert_false(src.contains("bar_chart_common_style"))
  assert_false(src.contains("bar_chart_views"))
  assert_false(src.contains("@anode"))
  // There is no tree to compile either, so the IR module is simply absent.
  assert_true(@viewgen.emit_ir_module_opt("BarChart", "b.tutu", file) is None)
}
