///|
test "counter: renders the initial count" {
  let h = @harness.mount(counter_module(), "Counter")
  inspect(h.text(".stat-value"), content="0")
}

///|
test "counter: $inc (a method) increments, dec (an input handler) decrements" {
  let h = @harness.mount(counter_module(), "Counter")
  h.click(".btn-success") // the + button, @on.click="$inc"
  inspect(h.text(".stat-value"), content="1")
  h.click(".btn-error") // the - button, @on.click="dec"
  h.click(".btn-error")
  inspect(h.text(".stat-value"), content="-1")
}

///|
test "counter: starts from the example's initial count" {
  let h = @harness.mount(counter_module(), "Counter", args={ "count": Num(-5) })
  h.click(".btn-success")
  inspect(h.text(".stat-value"), content="-4")
}

///|
test "counter: one re-render per interaction (batching)" {
  let h = @harness.mount(counter_module(), "Counter")
  let before = h.render_count()
  h.click(".btn-success")
  assert_eq(h.render_count(), before + 1)
}
