///|
/// A block converts, and the two spellings mean the same CSS.
fn css_survives(raw : String, global? : Bool = false) -> String raise {
  let out = @toshrub.css_block(raw, "", global).unwrap()
  assert_true(
    @toshrub.css_agrees(raw, out, global),
    msg="raw:\n" + raw + "\nnotation:\n" + out,
  )
  out
}

///|
test "a rule, and a bare declaration beside it" {
  inspect(
    css_survives("padding: 0.75rem; .common { color: yellow; }"),
    content=(
      #|padding: rem(0.75)
      #|class(common):
      #|  color: yellow
      #|
    ),
  )
}

///|
test "an attribute selector and a pseudo-element" {
  inspect(
    css_survives("[data-dragging=\"1\"] { opacity: 0.5; } .head:before { content: \"x\"; }"),
    content=(
      #|has_attr(data_dragging = "1"):
      #|  opacity: 0.5
      #|class(head) element(before):
      #|  content: "x"
      #|
    ),
  )
}

///|
test "a global block is a stylesheet, not a rule body" {
  inspect(
    css_survives(".a { color: green; }", global=true),
    content=(
      #|class(a):
      #|  color: green
      #|
    ),
  )
}
