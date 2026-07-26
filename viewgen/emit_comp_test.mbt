// The generated `component()` wrapper.
//
// Assertions rather than a whole-module snapshot: emit_test.mbt already pins
// the IR module's text in full, and what matters here is which arguments the
// wrapper fills and which it leaves to the author — a fact per assertion,
// each with a reason to exist.

///|
/// Schema + template: the case the wrapper is for.
let wrapper_html : String =
  #|<script type="tutuca/state">
  #|  interface counter {
  #|    record state {
  #|      label: string,
  #|      count: s32,
  #|    }
  #|  }
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
  // Package-private, because it names the private state type — the same
  // reason `<v>_encode` is.
  assert_true(ir.contains("\nfn counter_component(\n"))
  // Everything counter.html states, filled in.
  assert_true(ir.contains("  name? : String = \"Counter\","))
  assert_true(
    ir.contains("  views? : Map[String, @anode.View] = counter_views(),"),
  )
  assert_true(ir.contains("  init? : CounterState = CounterState::zero(),"))
  assert_true(ir.contains("  common_style? : String = counter_common_style,"))
  assert_true(ir.contains("  global_style? : String = counter_global_style,"))
  assert_true(ir.contains("    encode=counter_encode,"))
  assert_true(ir.contains("    decode=counter_decode,"))
  assert_true(ir.contains("    schema=counter_schema(),"))
  // The handlers, typed on the state rather than on a type variable — which
  // is what lets the call site write `(s, msg, _ctx)` with no annotation.
  assert_true(
    ir.contains(
      "  update? : (CounterState, @component.Dispatch, &@tutuca.Ctx) -> CounterState?,",
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
  // An absent update stays absent: component() takes it as an Option and the
  // wrapper forwards one rather than inventing a no-op.
  assert_true(ir.contains("    update?=update,"))
  // Pass-through, unmerged: component() already applies user specs over the
  // ones it derives from the schema.
  assert_true(
    ir.contains("  specs? : Map[String, @component.FieldSpec] = Map([]),"),
  )
}

///|
/// A record field used to be the case that got NO direct codec, on the
/// grounds that it had its own derived ToJson. That left the JSON bridge as
/// the runtime's answer for it — and a fallback something still needs is a
/// fallback that cannot be deleted. Nested types now get a codec like every
/// other shape, and the wrapper names it.
test "a nested record still gets a direct codec, named by the wrapper" {
  let f = @viewgen.split_file(
    (
      #|<script type="tutuca/state">
      #|  interface card {
      #|    record point { x: s32, y: s32 }
      #|    record state { at: point }
      #|  }
      #|</script>
      #|
      #|<template><i @text=".at"></i></template>
    ),
  )
  let ir = @viewgen.emit_ir_module("Card", "card.html", f)
  assert_true(ir.contains("\nfn card_component(\n"))
  assert_true(ir.contains("    encode=card_encode,"))
  assert_true(ir.contains("    decode=card_decode,"))
  // The schema reaches component() too: it is what declares the kinds.
  assert_true(ir.contains("    schema=card_schema(),"))
  assert_true(ir.contains("its schema\n/// and its direct codec."))
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
      #|<script type="tutuca/state">
      #|  interface headless { record state { n: s32 } }
      #|  interface shown { record state { n: s32 } }
      #|</script>
      #|
      #|<template id="Shown"><x text=".n"></x></template>
    ),
  )
  let ir = @viewgen.emit_ir_module("Ignored", "two.html", f)
  assert_true(ir.contains("\nfn shown_component(\n"))
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
      #|<script type="tutuca/state">
      #|  interface dse-root { record state { n: s32 } }
      #|</script>
      #|
      #|<template id="DseRoot"><x text=".n"></x></template>
    ),
  )
  let ir = @viewgen.emit_ir_module("Ignored", "dse.html", f)
  assert_true(ir.contains("\nfn dse_root_component(\n"))
  assert_true(ir.contains("  name? : String = \"DseRoot\","))
}
