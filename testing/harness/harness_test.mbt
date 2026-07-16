// End-to-end demo: mount a real example module, fire a real event, and read
// both the re-rendered DOM and the settled root value back. This is the shape
// an app author's own `moon test` blocks take — built-in assertions
// (`inspect`, `assert_eq`, `assert_true(x is Pattern)`) over the harness.

///|
test "harness drives an example: click re-renders the DOM" {
  let h = @harness.mount(@examples.counter_module(), "Counter")
  inspect(h.text(".stat-value"), content="0")
  h.click(".btn-success") // @on.click="$inc"
  inspect(h.text(".stat-value"), content="1")
}

///|
test "drive_value exposes the settled root value" {
  let h = @harness.mount(@examples.counter_module(), "Counter")
  // the root is a live component instance, not a plain value
  assert_true(h.drive_value() is Obj(_))
  h.click(".btn-success")
  assert_true(h.drive_value() is Obj(_))
}

///|
test "harness batches one re-render per interaction" {
  let h = @harness.mount(@examples.counter_module(), "Counter")
  let before = h.render_count()
  h.click(".btn-success")
  assert_eq(h.render_count(), before + 1)
}
