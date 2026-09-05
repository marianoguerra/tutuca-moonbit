// A macro's parameters have to reach its body.
//
// The call site was tested and the body was not, so the map was built and an
// empty one was passed — and a parameter read as an unbound render binding,
// which renders EMPTY. The same family as everything else this week: an
// answer silently smaller than what was written.

///|
test "a macro parameter reaches the body that reads it" {
  let src =
    #|spec:
    #|  Page:
    #|    field status :: String
    #|
    #|view:
    #|  macro badge(~label: "New", ~kind: "info"):
    #|    @span(~class: @str{badge badge-@(kind)}){@(label)}
    #|
    #|  Page:
    #|    @div{@badge(~label: it.status)}
    #|
  let out = lower_text(src)
  assert_eq(out.reports.length(), 0)
  // `^name` is a macro parameter: substituted at the call site, which is
  // neither a field nor something a loop put in scope
  assert_true(out.text.contains("<x text=\"^label\"></x>"))
  assert_true(out.text.contains("badge badge-{^kind}"))
  // and what a parameter is NOT is a render binding, which reads null here
  assert_false(out.text.contains("@label"))
  assert_false(out.text.contains("@kind"))
}
