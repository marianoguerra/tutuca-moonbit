// What `compile` makes of a file, at the seams `check_card` cannot reach.
//
// A card that CHECKS and does not COMPILE is the failure mode this backend has
// to keep out of the playground, and checking says nothing about it: the issue
// list is about what the card said, and these are about what the module ends up
// holding.

///|
/// The card-wide functions are decided per CARD, so a card whose only effect
/// lives in its second component still has to carry them.
///
/// `tc_flush` is emitted once, for the module, and CALLED from a component's
/// dispatch chain — so the two halves of the decision have to agree about what
/// the whole card uses.
test "an effect in the SECOND component still gets the card's flush" {
  let out = @wasm.compile(
    (
      #|<script type="tutuca/state">
      #|  state Board { rows: Array[Row] }
      #|  state Row { label: String }
      #|</script>
      #|<script type="tutuca/script" for="Board">
      #|  receive add {
      #|    new Row
      #|    @cur.label = 'a'
      #|    .rows.push @cur
      #|  }
      #|</script>
      #|<script type="tutuca/script" for="Row">
      #|  receive ask { intent dyn 'picked' .label }
      #|</script>
      #|<template id="Board:main"><ul><x render-each=".rows"></x></ul></template>
      #|<template id="Row:main"><li @on.click="ask"></li></template>
    ),
    name="Card",
  )
  @debug.assert_eq(out.components, ["Board", "Row"])
  @debug.assert_eq(out.refusals.map(r => r.name), [])
  // The call site and the definition, both present. Reading the Wax rather
  // than the bytes because the bytes only say it linked, and what broke was
  // which of the two the module was missing.
  assert_true(out.wax.contains("fn tc_flush()"))
  assert_true(out.wax.contains("tc_flush();"))
}

///|
/// The same seam from the other side: the card imports what the SECOND
/// component reaches for. An import section is a statement about the module,
/// and a routed effect names four host functions no other card needs.
test "an effect in the SECOND component decides the card's imports" {
  let out = @wasm.compile(
    (
      #|<script type="tutuca/state">
      #|  state Board { rows: Array[Row] }
      #|  state Row { label: String }
      #|</script>
      #|<script type="tutuca/script" for="Board">
      #|  receive add {
      #|    new Row
      #|    @cur.label = 'a'
      #|    .rows.push @cur
      #|  }
      #|</script>
      #|<script type="tutuca/script" for="Row">
      #|  receive ask { intent dyn 'picked' .label }
      #|</script>
      #|<template id="Board:main"><ul><x render-each=".rows"></x></ul></template>
      #|<template id="Row:main"><li @on.click="ask"></li></template>
    ),
    name="Card",
  )
  assert_true(out.wax.contains("fn ctl_intent("))
}
