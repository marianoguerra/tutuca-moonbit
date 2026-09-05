// A diagnostic points at the line to edit.
//
// The printers work over expressions, which carry no spans, so a failure
// raised inside one has nothing of its own to point at. It is re-raised
// against the declaration it was printing — the narrowest thing that does —
// and the test is that the reported line is the line with the mistake in it,
// not the top of the file.

///|
fn line_of_first_report(src : String) -> Int {
  let sources = @report.Sources::new()
  let id = sources.add("card.tutu", src)
  let out = lower(src, id)
  guard out.reports.length() > 0 else { return -1 }
  guard out.reports[0].anchor() is Some(label) else { return -1 }
  guard sources.fetch(id) is Some(source) else { return -1 }
  let (line, _) = source.line_col(label.span.start)
  line
}

///|
test "a failure lands on the declaration that holds it" {
  let src =
    #|spec:
    #|  Counter:
    #|    field count :: Int
    #|
    #|logic:
    #|  Counter:
    #|    receive fine:
    #|      it.count += 1
    #|
    #|    receive broken:
    #|      it.count := it.items.sorted()
    #|
  // line 11 is the `receive broken`, not line 1 and not the file
  assert_eq(line_of_first_report(src), 10)
}

///|
test "and a spec failure lands on the member, which is narrower still" {
  let src =
    #|spec:
    #|  Counter:
    #|    field count :: Int
    #|
    #|  Broken:
    #|    field n :: Nonesuch.of(Int)
    #|
  // line 6 is the field, not line 5 which is only the component holding it
  assert_eq(line_of_first_report(src), 6)
}
