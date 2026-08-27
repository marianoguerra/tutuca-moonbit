// The generated `component()` wrapper.
//
// Assertions rather than a whole-module snapshot: emit_test.mbt already pins
// the IR module's text in full, and what matters here is which arguments the
// wrapper fills and which it leaves to the author — a fact per assertion,
// each with a reason to exist.

///|
/// Schema + template: the case the wrapper is for.
let wrapper_html : String =
  #|<script type="tutuca/spec">
  #|  state Counter { label: String, count: Int }
  #|</script>
  #|
  #|<template>
  #|  <h1><x text=".label"></x>: <x text=".count"></x></h1>
  #|  <button @on.click="add 1">+1</button>
  #|</template>

///|
test "a schema-backed component gets a wrapper over component()" {
  let f = @viewgen.split_file(wrapper_html)
  let ir = @viewgen.emit_ir_module("Counter", "counter.html", f)
  // Public, like every other piece of generated vocabulary. It names the
  // state type in its signature, which is why that is `pub(all)` too — and
  // why a component generated in one package can be built from another, or
  // from a blackbox test.
  assert_true(ir.contains("\npub fn counter_component(\n"))
  // Everything counter.html states, filled in.
  assert_true(ir.contains("  name? : String = \"Counter\","))
  assert_true(
    ir.contains("  views? : Map[String, @anode.View] = counter_views(),"),
  )
  assert_true(ir.contains("  init? : CounterState = CounterState::zero(),"))
  assert_true(ir.contains("  common_style? : String = counter_common_style,"))
  assert_true(ir.contains("  global_style? : String = counter_global_style,"))
  // The schema and the codec are NOT arguments: `CounterState` states them
  // through `@component.Fields`, and `component()` reads them off the bound.
  assert_false(ir.contains("encode="))
  assert_false(ir.contains("decode="))
  assert_false(ir.contains("schema="))
  // The handlers, typed on the state rather than on a type variable — which
  // is what lets the call site write `(s, msg, _ctx)` with no annotation. The
  // answer is `Update[S]` and not `S?`, because "no arm claimed this" and "my
  // arm ran and changed nothing" are different answers and only one of them
  // falls through to a generated mutator.
  assert_true(
    ir.contains(
      "  update? : (CounterState, @component.Dispatch, &@tutuca.Ctx) -> @component.Update[CounterState],",
    ),
  )
  // Keyed by a generated enum, not by a string: the author writes a match the
  // compiler checks, so a name added to the view breaks the build rather than
  // leaving a handler that is never called. `swap` answers Input dispatches,
  // so its key is the input enum.
  assert_true(
    ir.contains(
      "  swap? : (CounterInput) -> ((CounterState, Array[@tutuca.Value], &@tutuca.Ctx) -> @tutuca.Value?)?,",
    ),
  )
  // A bucket the views never use is not a PARAMETER at all, so it cannot be
  // answered by mistake. This view calls no `$name` and names no `@when`.
  assert_false(ir.contains("  compute? :"))
  assert_false(ir.contains("  when? :"))
  // The author's match becomes the map `component()` takes through ONE generic
  // function, given the case list.
  assert_true(
    ir.contains(
      "@component.build_bucket(([Add] : Array[CounterInput]), CounterInput::name, f)",
    ),
  )
  // ...and an unanswered bucket is still the empty map, not a match that
  // answers nothing.
  assert_true(ir.contains("None => Map([])"))
  // An absent update stays absent: component() takes it as an Option and the
  // wrapper forwards one rather than inventing a no-op.
  assert_true(ir.contains("    update?=update,"))
  // What is left of `specs~`, and only what a TYPE cannot say. The kind a
  // field carries and the component a slot holds are both declared in the
  // block, so neither is a parameter any more; a component name kebab-case
  // cannot round-trip, and the arguments a child is built with, are.
  assert_false(ir.contains("specs?"))
  assert_true(ir.contains("  slots? : Map[String, String] = Map([]),"))
  assert_true(
    ir.contains(
      "  slot_args? : Map[String, Map[String, @tutuca.Value]] = Map([]),",
    ),
  )
}

///|
/// A nested record gets a direct codec like every other shape, and the
/// wrapper names it.
test "a nested record still gets a direct codec, named by the wrapper" {
  let f = @viewgen.split_file(
    (
      #|<script type="tutuca/spec">
      #|  struct Point { x: Int, y: Int }
      #|  state Card { at: Point }
      #|</script>
      #|
      #|<template><i @text=".at"></i></template>
    ),
  )
  let ir = @viewgen.emit_ir_module("Card", "card.html", f)
  assert_true(ir.contains("\npub fn card_component(\n"))
  // Neither the codec nor the schema is passed: the state type states both.
  assert_false(ir.contains("encode="))
  assert_false(ir.contains("decode="))
  assert_false(ir.contains("schema="))
  // The doc comment carries the explanation the signature cannot.
  assert_true(
    ir.contains("`CardState` states them\n/// through `@component.Fields`"),
  )
}

///|
/// No schema means no state type, so there are no typed parameters to make a
/// wrapper out of. Those components keep calling `component()` directly.
test "a component with views but no schema gets no wrapper" {
  let f = @viewgen.split_file("<template><b>hi</b></template>")
  let ir = @viewgen.emit_ir_module("Plain", "plain.html", f)
  assert_true(ir.contains("pub fn plain_views()"))
  assert_false(ir.contains("plain_component("))
}

///|
/// A schema entry with no template declares state for a component whose views
/// are built in MoonBit. There is nothing to default `views~` to, and the IR
/// module does not carry the component at all.
test "a schema-only component gets no wrapper" {
  let f = @viewgen.split_file(
    (
      #|<script type="tutuca/spec">
      #|  state Headless { n: Int }
      #|    state Shown { n: Int }
      #|</script>
      #|
      #|<template id="Shown"><x text=".n"></x></template>
    ),
  )
  let ir = @viewgen.emit_ir_module("Ignored", "two.html", f)
  assert_true(ir.contains("\npub fn shown_component(\n"))
  assert_false(ir.contains("headless_component("))
}

///|
/// The wrapper's `name` default is the name the template id declares, not the
/// one a component is registered under — `dynamic_selected_edit.html` names a
/// `DseRoot` template that the module registers as `Root`, and overriding it
/// has to stay possible.
test "the wrapper's name default is the declared component name" {
  let f = @viewgen.split_file(
    (
      #|<script type="tutuca/spec">
      #|  state DseRoot { n: Int }
      #|</script>
      #|
      #|<template id="DseRoot"><x text=".n"></x></template>
    ),
  )
  let ir = @viewgen.emit_ir_module("Ignored", "dse.html", f)
  assert_true(ir.contains("\npub fn dse_root_component(\n"))
  assert_true(ir.contains("  name? : String = \"DseRoot\","))
}
