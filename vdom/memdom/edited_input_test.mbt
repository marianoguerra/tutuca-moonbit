// The user changes an input's value, and a checkbox's checked, without a
// render, so the element can hold something other than what the previous
// render said. A morph compares the new render against the element before
// writing either: writing a value the element already holds resets the cursor,
// and a number input showing "1." reports "1", so writing "1" drops the ".".
// memdom counts value/checked writes in `value_sets`, which tells a skipped
// write from a rewrite of the same text.

///|
fn number_input(value : @vdom.AttrValue) -> @vdom.Vdom {
  @vdom.h("input", attrs={ "type": Str("number"), "value": value })
}

///|
/// The user edits `el` to hold `value`, as typing in the browser does
fn user_types(el : @memdom.MemNode, value : String) -> Unit {
  @vdom.DomNode::set_property(el, "value", Str(value)) |> ignore
}

///|
test "morph: an edited input already holding the new value is not written" {
  let (c, o) = new_env()
  let r1 = @vdom.render(number_input(Str("1.5")), c, o)
  let el = c.childs[0]
  // the user deletes the 5: the field shows "1.", which it reports as "1"
  user_types(el, "1")
  let writes = el.value_sets
  let _ = @vdom.render(number_input(Str("1")), c, o, prev=r1)
  assert_eq(el.value_sets, writes)
  assert_eq(el.get_value(), "1")
}

///|
test "morph: a number compares numerically with the edited text" {
  let (c, o) = new_env()
  let r1 = @vdom.render(number_input(Num(1.0)), c, o)
  let el = c.childs[0]
  user_types(el, "1.50")
  let writes = el.value_sets
  let _ = @vdom.render(number_input(Num(1.5)), c, o, prev=r1)
  assert_eq(el.value_sets, writes)
  // the user's text is kept
  assert_eq(el.get_value(), "1.50")
}

///|
test "morph: an edited input is written when the new value differs" {
  let (c, o) = new_env()
  let r1 = @vdom.render(number_input(Str("1.5")), c, o)
  let el = c.childs[0]
  user_types(el, "1")
  let r2 = @vdom.render(number_input(Str("2")), c, o, prev=r1)
  assert_eq(el.get_value(), "2")
  // a blank field doesn't hold 0, though "" parses as 0 in JS
  user_types(el, "")
  let _ = @vdom.render(number_input(Num(0.0)), c, o, prev=r2)
  assert_eq(el.get_value(), "0")
}

///|
test "morph: an edited checkbox already holding the new state is not written" {
  let checkbox = fn(checked : Bool) {
    @vdom.h("input", attrs={ "type": Str("checkbox"), "checked": Bool(checked) })
  }
  let (c, o) = new_env()
  let r1 = @vdom.render(checkbox(true), c, o)
  let el = c.childs[0]
  // the user unchecks it
  @vdom.DomNode::set_property(el, "checked", Bool(false)) |> ignore
  let writes = el.value_sets
  let r2 = @vdom.render(checkbox(false), c, o, prev=r1)
  assert_eq(el.value_sets, writes)
  // a different state is still written
  let _ = @vdom.render(checkbox(true), c, o, prev=r2)
  assert_eq(el.value_sets, writes + 1)
  assert_true(el.get_checked())
}

///|
test "morph: an element the user can't edit is written as before" {
  // a progress bar's value is only changed by rendering; its indeterminate to
  // 0% transition still goes through apply_value_last's attribute path
  let (c, o) = new_env()
  let r1 = @vdom.render(@vdom.h("progress"), c, o)
  let _ = @vdom.render(
    @vdom.h("progress", attrs={ "value": Num(0.0) }),
    c,
    o,
    prev=r1,
  )
  assert_true(c.childs[0].get_attribute("value") is Some("0"))
}
