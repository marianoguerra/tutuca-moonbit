// The fixed runtime has to compile before the generator that calls into it
// does. Same argument as `stdlib_test.mbt`: a syntax error in `runtime/*.wax`
// is a problem with THAT file, and finding it here rather than inside a
// `BadModule` from some card is most of fixing it.
//
// The prelude below stands in for what the generator puts between the stdlib
// and the runtime — the memory, the heap pointer and the bump allocator. It is
// the smallest thing that makes `runtime.wax` a complete module, and if it ever
// drifts from `emit_module` the tests that drive a real card will say so.

///|
let test_prelude : String =
  #|memory mem: i32 [2];
  #|let heap: i32 = 1024;
  #|fn alloc(size: i32, align: i32) -> i32 {
  #|    let base = (heap + align - 1) /u align * align;
  #|    let end = base + size;
  #|    let have = mem.size() * 65536;
  #|    if end >s have {
  #|        let need = (end - have + 65535) /u 65536;
  #|        if mem.grow(need) <s 0 { return 0; }
  #|    }
  #|    heap = end;
  #|    base
  #|}
  #|

///|
/// A parse error with the line it landed on. The concatenation is one module,
/// so the line is into the WHOLE of it — `report_line` below turns that back
/// into a file and a line a reader can open.
fn report_where(e : @basic.Report) -> String {
  "line " + e.loc.start.lnum.to_string() + ": " + e.message
}

///|
fn check_wax(src : String, what : String) -> Unit raise {
  let r = @waxfacade.parse_string(src, fname=what)
  guard r.module_ is Some(fields) else {
    fail(what + " did not parse: " + r.errors.map(report_where).join("; "))
  }
  if r.errors.length() > 0 {
    fail(what + " parsed with errors: " + r.errors.map(report_where).join("; "))
  }
  let session = @compile.Session::new()
  let checked = session.check(fields)
  let reports = session.reports()
  if @compile.rejected(reports) {
    fail(
      what +
      " did not type-check: " +
      reports.map(d => @message.to_plain_string(d.message)).join("; "),
    )
  }
  let bytes = checked.to_bytes()
  assert_true(bytes.length() > 30_000)
}

///|
test "the card runtime compiles, lowering scalars" {
  check_wax(
    stdlib_src + test_prelude + runtime_src + lower_src("lower_scalar.wax"),
    "<runtime+scalar>",
  )
}

///|
test "the card runtime compiles, lowering through the value arena" {
  check_wax(
    stdlib_src + test_prelude + runtime_src + lower_src("lower_values.wax"),
    "<runtime+values>",
  )
}

///|
/// The optional halves compile too, and they only ever appear on top of a
/// complete runtime — so this is the combination a card that says `num` gets,
/// rather than the file on its own.
test "the number parser compiles on top of the runtime" {
  check_wax(
    stdlib_src +
    test_prelude +
    runtime_src +
    lower_src("lower_scalar.wax") +
    optional_src("parse_num.wax"),
    "<runtime+scalar+parse_num>",
  )
}
