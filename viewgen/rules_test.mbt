// The rule layer, from the spec block to the generated module.
//
// What is pinned here is the seam: a `pred` and an `invariant` are declared in
// the SPEC block now, and everything downstream — the method bucket, the
// contract guard woven into an arm, the schema's `invariants` list, and the
// build-time `Init => Inv` test — has to reach them there.

///|
let ledger_html : String =
  #|<script type="tutuca/spec">
  #|  state Ledger {
  #|    here  : Int
  #|    there : Int
  #|    total : Int
  #|
  #|    pred canPush
  #|      format 'nothing left here to push' { .here > 0 }
  #|
  #|    invariant conserved
  #|      format $'{.here} + {.there} is not {.total}' { (.here + .there) is .total }
  #|  }
  #|</script>
  #|
  #|<script type="tutuca/init">
  #|{ "eight": { "value": { "here": 8, "total": 8 } } }
  #|</script>
  #|
  #|<script type="tutuca/script">
  #|  receive push requires canPush {
  #|    .here -= 1
  #|    .there += 1
  #|  }
  #|</script>
  #|
  #|<template>
  #|  <button @on.click="push"><x text=".here"></x></button>
  #|</template>

///|
test "a rule in the spec block compiles into the arm that names it" {
  let f = @viewgen.split_file(ledger_html)
  let ir = @viewgen.emit_ir_module("Ledger", "ledger.html", f)
  // THE PRECONDITION, over the state as the arm received it — the same guard a
  // `pred` in the script block produced, from a `pred` that is no longer there.
  assert_true(ir.contains("pred=\"canPush\""))
  assert_true(ir.contains("sentence=\"nothing left here to push\""))
  // THE INVARIANT, after the body and before the effect queue flushes.
  assert_true(ir.contains("pred=\"conserved\""))
  // And the rule's body, as a callable, so a view's `$conserved` badge and the
  // runtime's after-every-dispatch check ask the same function.
  assert_true(ir.contains("fn ledger_compute_conserved("))
  assert_true(ir.contains("fn ledger_compute_canPush("))
  // The generated comment points at the block that actually holds it.
  assert_true(ir.contains("`<script type=\"tutuca/spec\">` block"))
}

///|
test "the schema carries the invariant's ROLE, not just its body" {
  let f = @viewgen.split_file(ledger_html)
  let types = @viewgen.emit_module("Ledger", "ledger.html", f)
  // The body is one of the methods, the way every `$name` is…
  assert_true(types.contains("methods=[\"canPush\", \"conserved\"]"))
  // …and this is the half nothing else records: that the runtime should ask
  // this one after every dispatch, including the ones no view raised.
  assert_true(types.contains("invariants=[\"conserved\"]"))
}

///|
test "`Init => Inv`: the declared fixtures are asserted at build time" {
  let f = @viewgen.split_file(ledger_html)
  let ir = @viewgen.emit_ir_module("Ledger", "ledger.html", f)
  assert_true(
    ir.contains(
      "test \"Ledger: the declared initial states keep the invariants\"",
    ),
  )
  assert_true(ir.contains("let s = LedgerState::eight()"))
  assert_true(
    ir.contains("msg=\"the `eight` initial state breaks `conserved`\""),
  )
  // Only an explicit `Bool(false)` fails: a rule that cannot be evaluated is
  // unknown, and unknown is not wrong.
  assert_true(ir.contains("is Bool(false)"))
}

///|
test "a file with no fixtures gets no build-time assertion" {
  // The DECLARED initial states, and not the schema's zero. A wrapper is
  // normally called with `init~`, which the generator cannot see, so asserting
  // over all-zeros would fail components that work.
  let f = @viewgen.split_file(
    (
      #|<script type="tutuca/spec">
      #|  state Ledger {
      #|    here : Int
      #|    invariant positive { .here > 0 }
      #|  }
      #|</script>
      #|<template><b @text=".here"></b></template>
    ),
  )
  let ir = @viewgen.emit_ir_module("Ledger", "ledger.html", f)
  assert_false(ir.contains("keep the invariants"))
  // The rule still compiles, and is still asked after every dispatch — the
  // build-time check is the part that needs something declared to check.
  assert_true(ir.contains("fn ledger_compute_positive("))
}

///|
test "a rule with no script block anywhere still gets a body" {
  // An invariant belongs to the COMPONENT, so its existence cannot depend on a
  // handler block the file never writes.
  let f = @viewgen.split_file(
    (
      #|<script type="tutuca/spec">
      #|  state Ledger {
      #|    here : Int
      #|    invariant positive { .here > 0 }
      #|  }
      #|</script>
      #|<template><b @text=".here"></b></template>
    ),
  )
  let ir = @viewgen.emit_ir_module("Ledger", "ledger.html", f)
  assert_true(ir.contains("fn ledger_compute_positive("))
  assert_true(ir.contains("\"positive\": ledger_compute_positive,"))
}

///|
let gallery_html : String =
  #|<script type="tutuca/spec">
  #|  state Gallery {
  #|    items        : Array[String]
  #|    currentIndex : Int
  #|    count        : Int
  #|
  #|    where currentIndex is index of .items
  #|    where count >= 0
  #|  }
  #|</script>
  #|
  #|<template>
  #|  <div><x text=".currentIndex"></x></div>
  #|</template>

///|
test "a `where` in the spec block reaches the generated schema as DATA" {
  // The difference from an invariant, in the one place it shows: an invariant
  // reaches the schema as a NAME, because its body is already a method the
  // runtime can call. A domain has no body — the runtime evaluates the
  // relation itself — so what the schema carries is the relation.
  let f = @viewgen.split_file(gallery_html)
  let types = @viewgen.emit_module("Gallery", "gallery.html", f)
  assert_true(
    types.contains(
      "domains=[{ field: \"currentIndex\", domain: DIndexOf(field=\"items\", allow_none=false) }, { field: \"count\", domain: DCompare(op=DGe, rhs=DLit(0)) }]",
    ),
  )
  // No rule was declared, so nothing claims one — the two lists are separate
  // and a `where` does not become a nameless invariant.
  assert_true(types.contains("invariants=[]") || !types.contains("invariants="))
}

///|
test "a file with no `where` emits no domains at all" {
  // Absent rather than empty, so 143 checked-in generated modules stay
  // byte-identical and the drift check keeps meaning something.
  let f = @viewgen.split_file(ledger_html)
  let types = @viewgen.emit_module("Ledger", "ledger.html", f)
  assert_false(types.contains("domains="))
}
