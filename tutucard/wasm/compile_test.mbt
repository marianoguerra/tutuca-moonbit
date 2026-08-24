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

///|
/// The wiring a card declares reaches the manifest as SOURCE TEXT.
///
/// Nothing about a dynamic binding crosses the guest ABI: the module a card
/// compiles to is byte-identical whether or not the card provides anything.
/// The host parses these expressions and evaluates them against the instance
/// while rendering, exactly as it does for a component written in MoonBit —
/// which is why a card gets `provide` / `lookup` with no new import.
test "a card's provide/lookup sections reach the manifest" {
  let out = @wasm.compile(
    (
      #|<script type="tutuca/state">
      #|  state Board {
      #|    theme: String
      #|    slot: Slot
      #|    provide { theme = .theme, Cell = self }
      #|  }
      #|  state Slot {
      #|    made: String
      #|    lookup { theme, color = 'gray', Cell }
      #|  }
      #|</script>
      #|<template id="Board:main"><div><x render=".slot"></x></div></template>
      #|<template id="Slot:main"><em :style="$'color: {*theme}'"></em></template>
    ),
    name="Card",
  )
  guard! out.manifest is Object(root)
  guard! root.get("components") is Some(Array(comps))
  guard! comps.get(0) is Some(Object(board))
  guard! comps.get(1) is Some(Object(slot))
  @debug.assert_eq(
    board.get("provide"),
    Some(
      Json::array([
        Json::object({
          "name": Json::string("theme"),
          "source": Json::string(".theme"),
        }),
        Json::object({
          "name": Json::string("Cell"),
          "source": Json::string("self"),
        }),
      ]),
    ),
  )
  // A lookup with no default carries an empty string, which is the wire's way
  // of spelling "none" — the manifest is JSON and every other absent string
  // key spells it the same way.
  @debug.assert_eq(
    slot.get("lookup"),
    Some(
      Json::array([
        Json::object({
          "name": Json::string("theme"),
          "default": Json::string(""),
        }),
        Json::object({
          "name": Json::string("color"),
          "default": Json::string("'gray'"),
        }),
        Json::object({
          "name": Json::string("Cell"),
          "default": Json::string(""),
        }),
      ]),
    ),
  )
  // The key the HOST reads. It used to be `requests`, which nothing read, so a
  // card could not have declared a served intent even in principle.
  @debug.assert_eq(board.get("serves"), Some(Json::array([])))
}
