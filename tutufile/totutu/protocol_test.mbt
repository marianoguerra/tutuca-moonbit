// A protocol, converted: the two halves of a qualified name, and which one is
// allowed to move.

///|
let card_with_protocols : String =
  #|<script type="tutuca/spec">
  #|  /// What a thing with cells promises.
  #|  protocol Container = "tutuca.dev/universal/Container@1" {
  #|    handle { message { appendCell, removeAt(Int) } }
  #|    express { intent { insertRequested(Int) } }
  #|    property { count: Int, cellField: String }
  #|  }
  #|
  #|  /// A component that draws its own settings.
  #|  protocol Editable = "tutuca.dev/universal/Editable@1" {
  #|    view { editor }
  #|  }
  #|
  #|  state Box implements Container, Editable {
  #|    cellItems : Array[Any]
  #|    property {
  #|      pub count : Int { get }
  #|      pub cellField : String { get }
  #|      Container::count = count
  #|      Container::cellField = cellField
  #|    }
  #|    view { Editable::editor = arrangeCells }
  #|  }
  #|
  #|  handle Box { message { Container::appendCell } }
  #|  express Box { intent { Container::insertRequested(Int) } }
  #|</script>
  #|
  #|<script type="tutuca/script" for="Box">
  #|  get count { len .cellItems }
  #|  get cellField { 'cellItems' }
  #|  receive Container::appendCell { .cellItems.push 0 }
  #|  receive askInsert(i) { ask Container::insertRequested i }
  #|</script>
  #|
  #|<template id="Box"><div></div></template>
  #|<template id="Box:arrangeCells"><ul></ul></template>
  #|

///|
/// The second doc is the one that used to go missing: shrubbery hangs a `///`
/// written between two declarations off the FIRST one's suffix, so a printer
/// reading only a declaration's own leading doc drops every doc but the first.
test "a protocol keeps its id, its members and its doc" {
  let got = @totutu.convert(card_with_protocols, name="Box")
  @debug.assert_eq(got.refusals, [])
  assert_true(
    got.text.contains(
      "protocol Container = \"tutuca.dev/universal/Container@1\":",
    ),
  )
  assert_true(got.text.contains("/// What a thing with cells promises."))
  assert_true(got.text.contains("/// A component that draws its own settings."))
  assert_true(got.text.contains("    view editor\n"))
}

///|
/// The rename stops at `::`. A protocol id and its members are a wire
/// vocabulary dispatched by a second host as those exact strings, so
/// `appendCell` stays `appendCell` in a file where every local name has become
/// `snake_case` — and the LOCAL half of a binding moves with the rest.
test "a wire name does not move, and a local name does" {
  let got = @totutu.convert(card_with_protocols, name="Box")
  @debug.assert_eq(got.refusals, [])
  assert_true(got.text.contains("    message appendCell\n"))
  assert_true(got.text.contains("    message removeAt(Int)\n"))
  assert_true(got.text.contains("    property cellField :: String\n"))
  assert_true(got.text.contains("    message Container::appendCell\n"))
  assert_true(
    got.text.contains("    property Container::cellField = cell_field\n"),
  )
  assert_true(got.text.contains("    view Editable::editor = arrange_cells\n"))
  // the component's own property is a local name and IS renamed
  assert_true(got.text.contains("    property cell_field :: String ~public\n"))
}

///|
/// `implements` stores the protocol ID, because that is what dispatch uses.
/// The notation writes the local name, and the declaration that pairs them is
/// the only thing that knows which.
test "a claim names the protocol the way the file does" {
  let got = @totutu.convert(card_with_protocols, name="Box")
  @debug.assert_eq(got.refusals, [])
  assert_true(got.text.contains("    implements Container\n"))
  assert_true(got.text.contains("    implements Editable\n"))
}

///|
/// `ask Container::insertRequested i` is one NAME and an argument, not a read
/// of anything — the message an effect carries. Quoting it would have made it
/// a string, which is a different tree from the one the file had.
test "an effect carries a qualified message as the name it is" {
  let got = @totutu.convert(card_with_protocols, name="Box")
  @debug.assert_eq(got.refusals, [])
  assert_true(got.text.contains("ask(Container::insertRequested, i)"))
}
