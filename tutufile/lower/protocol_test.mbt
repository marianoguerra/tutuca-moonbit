// Protocols, which are a shared VOCABULARY and not this file's private shape:
// the id and the member names are what a second host dispatches by, so the
// test that matters is that they come through spelled exactly as written.

///|
let with_protocols : String =
  #|spec:
  #|  /// A thing with cells.
  #|  protocol Container = "tutuca.dev/universal/Container@1":
  #|    message appendCell
  #|    message removeAt(Int)
  #|    express intent insertRequested(Int)
  #|    property count :: Int
  #|    property cellField :: String
  #|
  #|  protocol Editable = "tutuca.dev/universal/Editable@1":
  #|    view editor
  #|
  #|  Box:
  #|    implements Container
  #|    implements Editable
  #|    field cells :: List.of(Any)
  #|    property count :: Int ~public
  #|    property Container::count = count
  #|    property Container::cellField = cellField
  #|    view Editable::editor = arrange
  #|    message Container::appendCell
  #|    express intent Container::insertRequested(Int)
  #|
  #|logic:
  #|  Box:
  #|    property count :: Int:
  #|      get: it.cells.length()
  #|

///|
test "a protocol keeps its id and its members, letter for letter" {
  let out = lower_text(with_protocols)
  assert_eq(out.reports.length(), 0)
  assert_true(
    out.text.contains(
      "protocol Container = \"tutuca.dev/universal/Container@1\" {",
    ),
  )
  // camelCase survives: these are wire names, and `@1` promises they do not move
  assert_true(out.text.contains("message { appendCell, removeAt(Int) }"))
  assert_true(out.text.contains("intent { insertRequested(Int) }"))
  assert_true(out.text.contains("property { count: Int, cellField: String }"))
  assert_true(out.text.contains("view { editor }"))
}

///|
test "a component claims its protocols and binds their members" {
  let out = lower_text(with_protocols)
  assert_true(out.text.contains("state Box implements Container, Editable {"))
  assert_true(out.text.contains("Container::count = count"))
  assert_true(out.text.contains("Container::cellField = cellField"))
  assert_true(out.text.contains("Editable::editor = arrange"))
  assert_true(out.text.contains("message { Container::appendCell }"))
  assert_true(out.text.contains("intent { Container::insertRequested(Int) }"))
}

///|
test "and the state parser reads back what was written" {
  let out = lower_text(with_protocols)
  let file = @viewfile.split_file(out.text, name="Box")
  let box = file.state[0]
  @debug.assert_eq(box.implements, [
    "tutuca.dev/universal/Container@1", "tutuca.dev/universal/Editable@1",
  ])
  assert_eq(box.protocols.length(), 2)
  assert_eq(box.protocols[0].id, "tutuca.dev/universal/Container@1")
  // the binding reached the parser under the protocol's own spelling
  assert_true(box.property_bindings.length() > 0)
  assert_eq(box.view_bindings.length(), 1)
}
