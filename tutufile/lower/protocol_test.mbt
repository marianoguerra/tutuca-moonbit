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

///|
test "a handler may answer a protocol's message under its own name" {
  let src =
    #|spec:
    #|  protocol Holder = "tutuca.dev/universal/Holder@1":
    #|    message hold(Any)
    #|    express intent addRequested(Bool)
    #|
    #|  Hole:
    #|    implements Holder
    #|    field child :: Any
    #|    message Holder::hold(Any)
    #|    express intent Holder::addRequested(Bool)
    #|
    #|logic:
    #|  Hole:
    #|    receive Holder::hold(inst):
    #|      it.child := inst
    #|
    #|    receive ask_for_one:
    #|      ask("Holder::addRequested", true, ~route: dyn)
    #|
  let out = lower_text(src)
  assert_eq(out.reports.length(), 0)
  // the qualified name survives `::` being the annotation operator beside it
  assert_true(out.text.contains("receive Holder::hold(inst) {"))
  assert_true(out.text.contains(".child = inst"))
  let file = @viewfile.split_file(out.text, name="Hole")
  assert_true(file.script_for("Hole") is Some(_))
  assert_eq(file.state[0].implements.length(), 1)
}

///|
/// Both arms of the qualified-name path, which is where the risk actually is:
/// the reader consumes three terms instead of one, and what follows — a
/// parameter list, a block, or neither — has to still be found.
test "a qualified receive with no parameters keeps its block" {
  let src =
    #|spec:
    #|  protocol Container = "tutuca.dev/universal/Container@1":
    #|    message appendCell
    #|  Box:
    #|    implements Container
    #|    field cells :: List.of(Any)
    #|    message Container::appendCell
    #|
    #|logic:
    #|  Box:
    #|    receive Container::appendCell:
    #|      it.cells.push("")
    #|
  let out = lower_text(src)
  assert_eq(out.reports.length(), 0)
  assert_true(out.text.contains("receive Container::appendCell {"))
  assert_true(out.text.contains(".cells.push"))
}

///|
test "a quoted role id survives the printer whole" {
  // `::` is an operator here and `@` opens a form, so a role id written as a
  // STRING is the value most likely to be eaten on the way through.
  let src =
    #|spec:
    #|  Hole:
    #|    field configuring :: Bool
    #|
    #|logic:
    #|  Hole:
    #|    compute child_view():
    #|      "tutuca.dev/universal/Editable@1::editor"
    #|
    #|view:
    #|  Hole:
    #|    @div(~push_view: child_view()){
    #|      @span{x}
    #|    }
    #|
  let out = lower_text(src)
  assert_eq(out.reports.length(), 0)
  assert_true(out.text.contains("'tutuca.dev/universal/Editable@1::editor'"))
  assert_true(out.text.contains("@push-view=\"$child_view\""))
}

///|
test "a conditional attribute is a ternary in the value, for any attribute" {
  // There is no `@if.<attr>` here and no attribute-name special case: a
  // conditional attribute is an `if` in the value, and `class` and `style`
  // reach the same printer by the same path.
  let src =
    #|spec:
    #|  Row:
    #|    field on :: Bool
    #|
    #|view:
    #|  Row:
    #|    @button(
    #|      ~class: if it.on | "arrow open" | "arrow",
    #|      ~style: if it.on | "display:block" | "display:none"
    #|    ){x}
    #|
  let out = lower_text(src)
  assert_eq(out.reports.length(), 0)
  assert_true(
    out.text.contains(":class=\"if .on { 'arrow open' } else { 'arrow' }\""),
  )
  assert_true(out.text.contains(":style=\"if .on {"))
}
