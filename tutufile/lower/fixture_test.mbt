// The three constructs the `std` kit turns on, each written the way that file
// writes it. Named for what they carry rather than for the form they use: a
// protocol member that does not empty, an assertion that cannot tell, and a
// binding written to rather than a field.

///|
test "emptying a held instance writes a null, and the protocol keeps meaning" {
  // `Holder@1::empty` is public API. If this lowers to a write of something
  // other than null, the hole keeps drawing what it held, the `x` does
  // nothing, and nothing anywhere refuses.
  let src =
    #|spec:
    #|  protocol Holder = "tutuca.dev/universal/Holder@1":
    #|    message empty
    #|  Hole:
    #|    implements Holder
    #|    field child :: Any
    #|    field editable :: Bool
    #|    message Holder::empty
    #|
    #|logic:
    #|  Hole:
    #|    receive Holder::empty:
    #|      it.child := none
    #|      it.editable := false
    #|
  let out = lower_text(src)
  assert_eq(out.reports.length(), 0)
  assert_true(out.text.contains("receive Holder::empty {"))
  assert_true(out.text.contains(".child = null"))
  assert_true(out.text.contains(".editable = false"))
}

///|
test "a scene may assert that a place holds nothing" {
  let src =
    #|spec:
    #|  Hole:
    #|    field child :: Any
    #|
    #|tests:
    #|  "emptying leaves nothing behind":
    #|    click("button.x")
    #|    expect state it.child == none
    #|
  let out = lower_text(src)
  assert_eq(out.reports.length(), 0)
  // the assertion path is not the expression path: this is a value in JSON,
  // and the `null? x` fold has no place in it
  assert_true(out.text.contains("\"expect\": \"state\""))
  assert_true(out.text.contains("\"at\": \".child\""))
  assert_true(out.text.contains("\"is\": null"))
}

///|
test "an enricher writes a binding, which is not a field" {
  // `@active = @key is .active` is what makes a tab strip show one page
  // instead of all of them, and it writes to the render scope rather than to
  // the component.
  let src =
    #|spec:
    #|  Tabs:
    #|    field pages :: List.of(Any)
    #|    field active :: Int
    #|
    #|logic:
    #|  Tabs:
    #|    enrich tab(item, i):
    #|      active = i == it.active
    #|
    #|view:
    #|  Tabs:
    #|    @ul{
    #|      @each(item, i in it.pages, ~enrich_with: tab){
    #|        @li(~class: if active | "on" | "off"){@(item)}
    #|      }
    #|    }
    #|
  let out = lower_text(src)
  assert_eq(out.reports.length(), 0)
  assert_true(out.text.contains("enrich tab {"))
  assert_true(out.text.contains("@active = (@key is .active)"))
  // and the view reads the binding the enricher wrote, under its own name
  assert_true(out.text.contains("@enrich-with=\"tab\""))
  assert_true(out.text.contains("@each=\".pages\""))
}
