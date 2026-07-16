// Property tests: the linter must be TOTAL — no panic on any input. The
// machine has many stack-pop paths; adversarial HTML is generated two ways:
// structurally valid but arbitrary documents (via the html package's
// Arbitrary Document, serialized back to HTML), and entirely arbitrary
// strings.

///|
test "lint_html never panics on arbitrary documents' HTML" {
  // forall instead of quick_check_fn: Document implements Arbitrary but not
  // Shrink (totality needs no shrinking anyway).
  let gen : @gen.Gen[@html5.Document] = @gen.Gen::spawn()
  @qc.quick_check(
    @qc.forall(gen, fn(doc) {
      @lint.lint_html(doc.to_html()) |> ignore
      true
    }),
  )
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
    let buf = StringBuilder::new()
    for x in xs {
      let i = if x < 0 { -(x + 1) } else { x }
      buf.write_string(fragments[i % fragments.length()])
    }
    @lint.lint_html(buf.to_string()) |> ignore
    true
  })
}
