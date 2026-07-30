///|
fn immediate_child_texts(node : ANode) -> Array[String] {
  let texts : Array[String] = []
  node.for_each_child(child => {
    match child {
      Text(d) => texts.push(d.val)
      _ => texts.push("?")
    }
  })
  texts
}

///|
test "for_each_child defines the structural children once" {
  let value = const_str("value")
  let one = text("one")
  let two = text("two")
  for node in [h("div", [], [one, two]), frag([one, two])] {
    assert_eq(immediate_child_texts(node), ["one", "two"])
  }
  for
    node in [
      show(value, one),
      hide(value, one),
      push_view(value, one),
      scope(0, value, one),
      slot("body", one),
      each(0, value, one),
      MacroCall({
        name: "macro",
        attrs: Map([]),
        slots: Map([]),
        px: ParseContext::new(),
        node: Some(one),
        data_attrs: Map([]),
      }),
    ] {
    assert_eq(immediate_child_texts(node), ["one"])
  }
  for
    node in [
      text("leaf"),
      comment("leaf"),
      dyn_text(value),
      render(0, value),
      render_it(0),
    ] {
    assert_eq(immediate_child_texts(node), [])
  }
}
