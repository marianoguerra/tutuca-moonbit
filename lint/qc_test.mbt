// Property tests: the linter must be TOTAL — no panic on any input. The
// machine has many stack-pop paths, so adversarial HTML is generated three
// ways: WELL-FORMED nesting, entirely arbitrary strings, and tag soup.

///|
/// The well-formed half, and the one arbitrary strings almost never reach: a
/// random string is overwhelmingly likely to be text, so without this the deep
/// stack-pop paths are never entered at all.
///
/// The tree is built HERE rather than taken from the html package. It used to
/// come from that package's `Arbitrary for Document`, which moved into a
/// white-box test file and stopped being a consumer's to use — and what this
/// test actually needs is varied nesting, not any particular generator.
test "lint_html never panics on well-formed nesting" {
  let containers = [
    "div", "span", "p", "ul", "li", "table", "tr", "td", "b", "i", "svg",
  ]
  @qc.quick_check_fn(fn(xs : Array[Int]) -> Bool {
    let buf = StringBuilder()
    let open : Array[String] = []
    buf.write_string("<!doctype html><html><head><title>t</title></head><body>")
    for x in xs {
      let i = if x < 0 { -(x + 1) } else { x }
      // Close on every third draw, so the tree both deepens and unwinds
      // rather than nesting monotonically to the depth of the input.
      if i % 3 == 0 && open.length() > 0 {
        buf.write_string("</\{open.unsafe_pop()}>")
      } else {
        let tag = containers[i % containers.length()]
        open.push(tag)
        buf.write_string("<\{tag}>text ")
      }
    }
    while open.length() > 0 {
      buf.write_string("</\{open.unsafe_pop()}>")
    }
    buf.write_string("</body></html>")
    @lint.lint_html(buf.to_string()) |> ignore
    true
  })
}

///|
test "lint_html never panics on arbitrary strings" {
  @qc.quick_check_fn(fn(s : String) -> Bool {
    @lint.lint_html(s) |> ignore
    true
  })
}

///|
test "lint_html never panics on adversarial tag soup" {
  // Arbitrary ints select fragments from a soup of valid and broken markup
  // (mismatched closes, foreign content, table parts, bogus comments).
  let fragments = [
    "<div>", "</div>", "<table>", "</table>", "<tr>", "<td>", "</span>", "<svg>",
    "</svg>", "<math>", "<annotation-xml encoding=\"text/html\">", "<b>", "<i>",
    "</b>", "</i>", "<x:m>", "</x:m>", "text ", "<!-- c -->", "<!bogus>", "<![CDATA[x]]>",
    "<br></br>", "<select>", "<option>a", "<form>", "<input value=>", "<p CLASS=\"a\" class=\"b\">",
    "<MyTag>", "<font color=\"r\">", "<foreignObject>", "</p>", "</li>", "<li>",
  ]
  @qc.quick_check_fn(fn(xs : Array[Int]) -> Bool {
    let buf = StringBuilder()
    for x in xs {
      let i = if x < 0 { -(x + 1) } else { x }
      buf.write_string(fragments[i % fragments.length()])
    }
    @lint.lint_html(buf.to_string()) |> ignore
    true
  })
}
