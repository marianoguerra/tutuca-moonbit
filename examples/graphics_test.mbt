///|
test "svg-interactive: the swatches render as real namespaced SVG elements" {
  let h = @harness.mount_example(svg_interactive_module(), "Default")
  inspect(h.find_all("circle").length(), content="8")
  inspect(h.ns_of("svg"), content="svg")
  inspect(h.ns_of("circle"), content="svg")
  // @enrich-with laid the swatches out along the row
  debug_inspect(
    h.find_all("circle").map(n => n.get_attribute("cx")),
    content=(
      #|[
      #|  Some("32"),
      #|  Some("78"),
      #|  Some("124"),
      #|  Some("170"),
      #|  Some("216"),
      #|  Some("262"),
      #|  Some("308"),
      #|  Some("354"),
      #|]
    ),
  )
  // viewBox keeps its camelCase spelling in the SVG namespace
  debug_inspect(
    h.attr("svg", "viewBox"),
    content=(
      #|Some("0 0 380 130")
    ),
  )
}

///|
test "svg-interactive: clicking a circle sets the color, and the ring follows" {
  let h = @harness.mount_example(svg_interactive_module(), "Default")
  debug_inspect(
    h.attr(".preview", "fill"),
    content=(
      #|Some("#ef4444")
    ),
  )
  // only the selected swatch has a visible ring
  debug_inspect(
    h.find_all("circle").map(n => n.get_attribute("stroke")),
    content=(
      #|[
      #|  Some("#0f172a"),
      #|  Some("transparent"),
      #|  Some("transparent"),
      #|  Some("transparent"),
      #|  Some("transparent"),
      #|  Some("transparent"),
      #|  Some("transparent"),
      #|  Some("transparent"),
      #|]
    ),
  )
  // @on.click on an SVG element: the handler gets the loop's @value
  h.click("circle", nth=5)
  debug_inspect(
    h.attr(".preview", "fill"),
    content=(
      #|Some("#3b82f6")
    ),
  )
  inspect(h.text(".label"), content="Selected: #3b82f6")
  debug_inspect(
    h.attr("circle", "stroke", nth=5),
    content=(
      #|Some("#0f172a")
    ),
  )
  debug_inspect(
    h.attr("circle", "stroke", nth=0),
    content=(
      #|Some("transparent")
    ),
  )
}

///|
test "mathml-formula: the formula renders as real MathML" {
  let h = @harness.mount_example(mathml_formula_module(), "Two roots")
  inspect(h.ns_of("math"), content="mathml")
  inspect(h.ns_of(".m-a"), content="mathml")
  inspect(h.text(".m-a"), content="1")
  inspect(h.text(".m-b"), content="-3")
  inspect(h.text(".m-c"), content="2")
  // 9 - 8 = 1 > 0
  inspect(h.text(".disc"), content="1")
  inspect(h.text(".classify"), content="two distinct real roots")
}

///|
test "mathml-formula: editing a coefficient re-renders the <mn> and the verdict" {
  let h = @harness.mount_example(mathml_formula_module(), "Two roots")
  // @on.input="$setC valueAsInt" — the raw event value, coerced to an Int
  h.type_into(".in-c", "5")
  inspect(h.text(".m-c"), content="5")
  inspect(h.text(".disc"), content="-11") // 9 - 20
  inspect(h.text(".classify"), content="no real roots")
  h.type_into(".in-b", "-4")
  h.type_into(".in-c", "4")
  inspect(h.text(".disc"), content="0") // 16 - 16
  inspect(h.text(".classify"), content="one repeated real root")
}
