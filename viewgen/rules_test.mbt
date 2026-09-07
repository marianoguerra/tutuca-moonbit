// The rule layer, from the `spec:` section to the generated module.
//
// What is pinned here is the seam: a `pred` and an `invariant` are declared in
// the `spec:` section, and everything downstream — the method bucket, the
// contract guard woven into an arm, the schema's `invariants` list, and the
// build-time `Init => Inv` test — has to reach them there.

///|
let ledger_src : String =
  #|spec:
  #|  Ledger:
  #|    field here :: Int
  #|    field there :: Int
  #|    field total :: Int
  #|
  #|    pred canPush:
  #|      ~format: "nothing left here to push"
  #|      it.here > 0
  #|
  #|    invariant conserved:
  #|      ~format: @str{@(it.here) + @(it.there) is not @(it.total)}
  #|      (it.here + it.there) == it.total
  #|
  #|logic:
  #|  Ledger:
  #|    receive push:
  #|      ~requires: canPush
  #|      it.here -= 1
  #|      it.there += 1
  #|
  #|view:
  #|  Ledger:
  #|    button(~on_click: push):
  #|      @(it.here)
  #|
  #|fixtures:
  #|  "eight":
  #|    it.here = 8
  #|    it.total = 8

///|
test "a rule in the `spec:` section compiles into the arm that names it" {
  let f = @viewgen.read_file(ledger_src)
  let ir = @viewgen.emit_ir_module("Ledger", "ledger.tutu", f)
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
  assert_true(ir.contains("`spec:` section"))
}

///|
test "the schema carries the invariant's ROLE, not just its body" {
  let f = @viewgen.read_file(ledger_src)
  let types = @viewgen.emit_module("Ledger", "ledger.tutu", f)
  // The body is one of the methods, the way every `$name` is…
  assert_true(types.contains("methods=[\"canPush\", \"conserved\"]"))
  // …and this is the half nothing else records: that the runtime should ask
  // this one after every dispatch, including the ones no view raised.
  assert_true(types.contains("invariants=[\"conserved\"]"))
}

///|
test "`Init => Inv`: the declared fixtures are asserted at build time" {
  let f = @viewgen.read_file(ledger_src)
  let ir = @viewgen.emit_ir_module("Ledger", "ledger.tutu", f)
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
  // normally called with `initial~`, which the generator cannot see, so asserting
  // over all-zeros would fail components that work.
  let f = @viewgen.read_file(
    (
      #|spec:
      #|  Ledger:
      #|    field here :: Int
      #|    invariant positive: it.here > 0
      #|
      #|view:
      #|  Ledger:
      #|    b():
      #|      @(it.here)
    ),
  )
  let ir = @viewgen.emit_ir_module("Ledger", "ledger.tutu", f)
  assert_false(ir.contains("keep the invariants"))
  // The rule still compiles, and is still asked after every dispatch — the
  // build-time check is the part that needs something declared to check.
  assert_true(ir.contains("fn ledger_compute_positive("))
}

///|
test "a rule with no `logic:` section anywhere still gets a body" {
  // An invariant belongs to the COMPONENT, so its existence cannot depend on a
  // section the file never writes.
  let f = @viewgen.read_file(
    (
      #|spec:
      #|  Ledger:
      #|    field here :: Int
      #|    invariant positive: it.here > 0
      #|
      #|view:
      #|  Ledger:
      #|    b():
      #|      @(it.here)
    ),
  )
  let ir = @viewgen.emit_ir_module("Ledger", "ledger.tutu", f)
  assert_true(ir.contains("fn ledger_compute_positive("))
  assert_true(ir.contains("\"positive\": ledger_compute_positive,"))
}

///|
let gallery_src : String =
  #|spec:
  #|  Gallery:
  #|    field items :: List.of(String)
  #|    field currentIndex :: Int
  #|    field count :: Int
  #|
  #|    where it.currentIndex is_index_of it.items
  #|    where it.count >= 0
  #|
  #|view:
  #|  Gallery:
  #|    div():
  #|      @(it.currentIndex)

///|
test "a `where` in the `spec:` section reaches the generated schema as DATA" {
  // The difference from an invariant, in the one place it shows: an invariant
  // reaches the schema as a NAME, because its body is already a method the
  // runtime can call. A domain has no body — the runtime evaluates the
  // relation itself — so what the schema carries is the relation.
  let f = @viewgen.read_file(gallery_src)
  let types = @viewgen.emit_module("Gallery", "gallery.tutu", f)
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
  let f = @viewgen.read_file(ledger_src)
  let types = @viewgen.emit_module("Ledger", "ledger.tutu", f)
  assert_false(types.contains("domains="))
}

///|
/// A `where` reaches the generated ARM as well, not only the schema.
let gallery_logic_src : String =
  #|spec:
  #|  Gallery:
  #|    field items :: List.of(String)
  #|    field view :: String
  #|
  #|    where it.view is_one_of ["main", "edit"]
  #|
  #|logic:
  #|  Gallery:
  #|    receive toggleView:
  #|      it.view := if it.view == "main" | "edit" | "main"
  #|      send("viewChanged")
  #|
  #|view:
  #|  Gallery:
  #|    button(~on_click: toggleView):
  #|      @(it.view)

///|
test "a `where` is woven into the arm, beside the invariants" {
  // The schema carries the domains and the RUNTIME asks them after every
  // dispatch — which for a long time was the only place they were asked. An
  // arm that raised effects and then put a field out of domain therefore
  // flushed its queue and was refused afterwards: the state rolled back, the
  // messages did not. An `invariant` never had that gap, because its guard is
  // compiled in; this closes it for a domain the same way.
  let f = @viewgen.read_file(gallery_logic_src)
  // The IR module, which is where the arm the `logic:` section compiles to
  // lives.
  let out = @viewgen.emit_ir_module("Gallery", "gallery.tutu", f)
  assert_true(out.contains("@tutuca.first_broken_domain("))
  assert_true(out.contains("@tutuca.domain_failed("))
  // CALLED rather than compiled, which is the opposite of what an invariant's
  // guard does — and deliberate. A rule is an arbitrary expression this
  // backend has to spell; a domain is a closed relation the runtime already
  // evaluates at the door this guard stands in front of, and a second reading
  // of `one of` could only disagree with the first.
  assert_true(
    out.contains(
      "[{ field: \"view\", domain: DOneOf([Str(\"main\"), Str(\"edit\")]) }]",
    ),
  )
  // BEFORE the flush. The queue exists so that a transition is whole or does
  // not happen, and a check after it would be a refusal with the messages
  // already gone.
  // Asked as "what comes first", because that is the claim: the text between
  // the check and the flush is the arm, and the flush has to be after it.
  let upto_flush = out.split("for f in effects").to_array()
  assert_true(upto_flush.length() > 1)
  assert_true(upto_flush[0].contains("@tutuca.first_broken_domain("))
}

///|
test "a component with no `where` gets no check in its arm" {
  // The cost of the feature for everyone who does not use it: nothing at all.
  let f = @viewgen.read_file(ledger_src)
  let out = @viewgen.emit_ir_module("Ledger", "ledger.tutu", f)
  assert_false(out.contains("first_broken_domain"))
}
