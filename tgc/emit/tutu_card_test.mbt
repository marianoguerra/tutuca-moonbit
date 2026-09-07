///|
/// A card, end to end, through the one door there is.
///
/// The card compiler takes SOURCE TEXT and reads it internally, so a page
/// hands `compile` a `.tutu` and gets a module: no second entry point, and
/// nothing for a host to choose between.
test "a .tutu card compiles" {
  let card =
    #|spec:
    #|  Counter ~root:
    #|    field count :: Int
    #|    field label :: String
    #|
    #|logic:
    #|  Counter:
    #|    receive inc: it.count += 1
    #|    receive set_to(n): it.count := n
    #|    compute shown(): @str{count: @(it.count)}
    #|
    #|view:
    #|  Counter:
    #|    @output{@(shown())}
  let out = @emit.compile(card, name="counter")
  assert_eq(out.component, "Counter")
  assert_eq(out.fields, ["count", "label"])
  assert_eq(out.refusals.map(r => r.name), [])
  assert_true(out.wasm.length() > 100, msg="\{out.wasm.length()} bytes")
}
