///|
test "counter: renders the initial count" {
  let h = @harness.mount(counter_module(), "Counter")
  inspect(h.text(".stat-value"), content="0")
}

///|
test "counter: $inc (a method) increments, dec (an input handler) decrements" {
  let h = @harness.mount(counter_module(), "Counter")
  h.click(".btn-success") // the + button, @on.click="inc"
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

///|
test "counter: simple and abstract properties are synchronous" {
  let h = @harness.mount(counter_module(), "Counter", args={ "count": Num(-5) })
  assert_eq(h.drive_value().property("count"), Num(-5))
  assert_eq(h.drive_value().property("magnitude"), Num(5))

  assert_true(
    h.app.transactor.set_property(
      @tutuca.DispatchPath::new(),
      "magnitude",
      Num(9),
    )
    is PChanged(_),
  )
  // The complex setter preserved the internal sign and the synchronous call
  // already rebuilt the DOM before it returned.
  assert_eq(h.drive_value().field("count"), Num(-9))
  assert_eq(h.text(".stat-value"), "-9")

  assert_true(
    h.app.transactor.set_property(@tutuca.DispatchPath::new(), "count", Num(3))
    is PChanged(_),
  )
  assert_eq(h.drive_value().property("magnitude"), Num(3))
}

///|
test "counter: a host cannot dispatch the generated field mutator" {
  let h = @harness.mount(counter_module(), "Counter")
  let refused = @harness.refusals_while(() => {
    h.send_at_root("setCount", args=[Num(7)])
  })
  assert_eq(h.drive_value().field("count"), Num(0))
  assert_eq(refused.length(), 1)
  assert_eq(refused[0].code, NoHandler)
}

///|
test "counter: public fuzzer plans generate properties, never internal mutators" {
  guard @fuzz.Plan::of_component(counter_module().components[0]) is Some(plan) else {
    fail("Counter carries its spec")
  }
  let actions = plan.script(seed=3, steps=80)
  assert_true(actions.iter().any(a => a is SetProperty(_, _)))
  assert_false(actions.iter().any(a => a is InternalMutator(_)))
}
