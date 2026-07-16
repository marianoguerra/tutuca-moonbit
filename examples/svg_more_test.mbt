///|
test "svg-bar-chart: bars and labels render as real SVG, geometry from @enrich-with" {
  let h = @harness.mount_example(svg_bar_chart_module(), "Default")
  inspect(h.ns_of("svg"), content="svg")
  inspect(h.ns_of("rect"), content="svg")
  inspect(h.find_all("rect").length(), content="6")
  inspect(h.find_all("text").length(), content="6")
  // @loop-with laid out 6 bars in a 300-wide viewBox: step = 50, barW = 31
  debug_inspect(
    h.attr("rect", "width"),
    content=(
      #|Some("31")
    ),
  )
  // bar 0: x = 0*50 + (50-31)/2 = 9.5, h = 40, y = 110-40 = 70
  debug_inspect(
    h.attr("rect", "x", nth=0),
    content=(
      #|Some("9.5")
    ),
  )
  debug_inspect(
    h.attr("rect", "height", nth=0),
    content=(
      #|Some("40")
    ),
  )
  debug_inspect(
    h.attr("rect", "y", nth=0),
    content=(
      #|Some("70")
    ),
  )
  // the labels echo the values
  debug_inspect(
    h.texts("text"),
    content=(
      #|["40", "72", "28", "90", "55", "63"]
    ),
  )
}

///|
test "svg-bar-chart: add / remove bars, and the layout adapts" {
  let h = @harness.mount_example(svg_bar_chart_module(), "Default")
  h.click(".add")
  inspect(h.find_all("rect").length(), content="7")
  // step is now 300/7, so the widths shrank
  debug_inspect(
    h.attr("rect", "width"),
    content=(
      #|Some("26.57142857142857")
    ),
  )
  h.click(".remove")
  h.click(".remove")
  inspect(h.find_all("rect").length(), content="5")
}

///|
test "svg-bar-chart: remove is capped at one bar, add at nine" {
  let h = @harness.mount_example(svg_bar_chart_module(), "Single bar")
  inspect(h.find_all("rect").length(), content="1")
  h.click(".remove") // capped — cannot go below 1
  inspect(h.find_all("rect").length(), content="1")
  // the single-bar layout fills the width: step = 300, barW = 186
  debug_inspect(
    h.attr("rect", "width"),
    content=(
      #|Some("186")
    ),
  )
}

///|
test "svg-bar-chart: randomize keeps the bar count and re-renders" {
  let h = @harness.mount_example(svg_bar_chart_module(), "Default")
  let before = h.texts("text")
  h.click(".randomize")
  inspect(h.find_all("rect").length(), content="6") // count unchanged
  @test.assert_not_eq(h.texts("text"), before) // values changed
}

///|
test "svg-icon-macro: each icon macro expands to a real SVG subtree" {
  let h = @harness.mount_example(svg_icon_macro_module(), "Default")
  inspect(h.find_all(".icons svg").length(), content="0") // no descendant combinator
  // three icons in the reactive row + three fixed = 6 svgs
  inspect(h.find_all("svg").length(), content="6")
  inspect(h.ns_of("svg"), content="svg")
  inspect(h.ns_of("path"), content="svg")
  // :size=".size" -> 40 on the reactive icons; ^color passed as a literal
  debug_inspect(
    h.attr("svg", "width", nth=0),
    content=(
      #|Some("40")
    ),
  )
  debug_inspect(
    h.attr("svg", "stroke", nth=0),
    content=(
      #|Some("#e11d48")
    ),
  )
  // the fixed icons carry the static size="20"
  debug_inspect(
    h.attr("svg", "width", nth=3),
    content=(
      #|Some("20")
    ),
  )
}

///|
test "svg-icon-macro: the size slider drives every reactive icon at once" {
  let h = @harness.mount_example(svg_icon_macro_module(), "Default")
  inspect(h.text(".sizeval"), content="40")
  h.fire("input", @render.DomEvent::new(name="input", value=Str("64")))
  inspect(h.text(".sizeval"), content="64")
  debug_inspect(
    h.attr("svg", "width", nth=0),
    content=(
      #|Some("64")
    ),
  )
  debug_inspect(
    h.attr("svg", "height", nth=1),
    content=(
      #|Some("64")
    ),
  )
  // the fixed 20px icons are unaffected
  debug_inspect(
    h.attr("svg", "width", nth=3),
    content=(
      #|Some("20")
    ),
  )
}
