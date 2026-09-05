///|
/// The same card in the section notation, through the same door.
///
/// The card compiler takes source text and splits it internally, so a `.tutu`
/// card needs no second entry point and a host has nothing to choose between:
/// what a page hands `compile` is compiled, whichever notation it is in.
test "a .tutu card compiles the same way an .html one does" {
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

///|
/// And the `.html` beside it still compiles: the two are told apart by what
/// the source holds, because nothing at this seam has a filename to go on.
test "an .html card is untouched by the .tutu entry" {
  let card =
    #|<script type="tutuca/spec">
    #|  state Counter { count: Int }
    #|</script>
    #|<template id="Counter:main" data-root>
    #|  <output @text=".count"></output>
    #|</template>
  let out = @emit.compile(card, name="counter")
  assert_eq(out.component, "Counter")
  assert_eq(out.fields, ["count"])
}
