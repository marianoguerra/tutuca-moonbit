// The vendored stdlib has to compile, on its own, before anything is built on
// it. This is the test that says so: parse the concatenation, check it, emit
// it. A failure here is a vendoring problem — a bad copy, a wrong order, or a
// stdlib that wants a Wax newer than the one this module depends on — and it
// should not be discovered later, wearing the costume of a generator bug.

///|
test "the vendored Wax stdlib parses" {
  let r = @waxfacade.parse_string(stdlib_src, fname="<wax-stdlib>")
  let errors = r.errors.map(e => e.message).join("; ")
  assert_eq(errors, "")
  match r.module_ {
    Some(fields) => assert_true(fields.length() > 100)
    None => fail("the stdlib parsed to no module at all")
  }
}

///|
test "the vendored Wax stdlib type-checks and emits" {
  let r = @waxfacade.parse_string(stdlib_src, fname="<wax-stdlib>")
  let fields = match r.module_ {
    Some(f) => f
    None => fail("the stdlib did not parse")
  }
  let session = @compile.Session::new()
  let checked = session.check(fields)
  let reports = session.reports()
  if @compile.rejected(reports) {
    fail(
      "the stdlib did not type-check: " +
      reports.map(d => @message.to_plain_string(d.message)).join("; "),
    )
  }
  let bytes = checked.to_bytes()
  // ~37 KB today. This is the FLOOR every compiled card now carries: Wax's
  // emitter does no dead-code elimination, so a card that never builds a set
  // still ships `phs_*`, and one that never uses a transient still ships the
  // `jvt_*` half. That is the price of the value model and it is worth saying
  // out loud rather than discovering in an archive listing.
  //
  // The bound is a drift alarm, not a budget. If it trips, find out what grew
  // before widening it.
  assert_true(bytes.length() > 30_000 && bytes.length() < 45_000)
  assert_eq(bytes[0], b'\x00')
  assert_eq(bytes[1], b'a')
  assert_eq(bytes[2], b's')
  assert_eq(bytes[3], b'm')
}
