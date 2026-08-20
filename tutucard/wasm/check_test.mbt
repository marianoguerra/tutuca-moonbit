// What `check_card` makes of a file, at the seams multi-component moved.
//
// These are the shapes the starter cards actually take, and the reason they
// are pinned here rather than left to the node gate: the gate compiles a card
// end to end and says only that it failed.

///|
/// The common shape, and the one that broke when the schema lookup first
/// learned to match by name: a card names its component in the STATE block and
/// leaves the `<template>` bare. The two names do not agree — the schema says
/// `Counter`, the component is named from the fallback — and with one of each
/// there is nothing for that to be ambiguous with.
test "a named state and a bare template still find each other" {
  let out = @wasm.check_card(
    (
      #|<script type="tutuca/state">
      #|  state Counter { count: Int }
      #|</script>
      #|<script type="tutuca/script">
      #|  receive inc { .count += 1 }
      #|</script>
      #|<template><button @on.click="inc"></button></template>
    ),
    name="Card",
  )
  inspect(out.component, content="Card")
  @debug.assert_eq(out.components, ["Card"])
  // The schema was found, so `.count` resolves. Before it was, every field in
  // every handler read as NO_FIELD.
  @debug.assert_eq(out.issues.map(i => i.code), [])
}

///|
test "a card may declare two components, each checked against its own schema" {
  let out = @wasm.check_card(
    (
      #|<script type="tutuca/state">
      #|  state Board { tally: Int }
      #|  state Row { done: Bool }
      #|</script>
      #|<script type="tutuca/script" for="Board">
      #|  receive bump { .tally += 1 }
      #|</script>
      #|<script type="tutuca/script" for="Row">
      #|  receive toggle { .done = not .done }
      #|</script>
      #|<template id="Board:main"><b></b></template>
      #|<template id="Row:main"><i></i></template>
    ),
    name="Card",
  )
  inspect(out.component, content="Board")
  @debug.assert_eq(out.components, ["Board", "Row"])
  @debug.assert_eq(out.issues.map(i => i.code), [])
}

///|
/// A schema is one component's, and reaching into another's is the mistake
/// this separation exists to catch. `Row` has no `.tally`.
test "a component cannot read a sibling's field" {
  let out = @wasm.check_card(
    (
      #|<script type="tutuca/state">
      #|  state Board { tally: Int }
      #|  state Row { done: Bool }
      #|</script>
      #|<script type="tutuca/script" for="Row">
      #|  receive toggle { .tally += 1 }
      #|</script>
      #|<template id="Board:main"><b></b></template>
      #|<template id="Row:main"><i></i></template>
    ),
    name="Card",
  )
  @debug.assert_eq(out.issues.map(i => (i.comp, i.code)), [("Row", "NO_FIELD")])
}

///|
/// `data-root` decides what a host mounts, and does not reorder the file.
test "data-root names the component a host mounts" {
  let src =
    #|<script type="tutuca/state">
    #|  state Board { tally: Int }
    #|  state Row { done: Bool }
    #|</script>
    #|<template id="Row:main" data-root><i></i></template>
    #|<template id="Board:main"><b></b></template>
  let out = @wasm.check_card(src, name="Card")
  inspect(out.component, content="Row")
  // …and `components` is still the order the file writes them in.
  @debug.assert_eq(out.components, ["Row", "Board"])
}
