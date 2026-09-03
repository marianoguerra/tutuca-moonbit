///|
/// The preamble is a module a compiler accepts, not a string that looks like
/// one. Without this test `preamble_wax` is a comment.
test "the Wax preamble compiles" {
  let src = @abi.preamble_wax() + "\n" + probe_wax
  match @wax.compile_string(src, fname="tgc/1.wax") {
    Ok(bytes) => assert_true(bytes.length() > 8)
    Err(ds) => fail("rejected: " + diagnostics_line(ds))
  }
}

///|
/// A module that only DECLARES the types carries none of them into its type
/// section unless something uses them, so the probe reaches for every arm. It is
/// also the smallest worked example of the two calls that matter: reading a
/// field of a child, and asking it to do something.
let probe_wax : String =
  #|fn tg_null() -> &tg_val { { kind: 0 } }
  #|fn tg_bool(v: i32) -> &tg_val { {tg_bool| kind: 1, value: v } }
  #|fn tg_num(v: f64) -> &tg_val { {tg_num| kind: 2, value: v } }
  #|fn tg_int(v: i64) -> &tg_val { {tg_int| kind: 3, value: v } }
  #|fn tg_str(v: &tg_bytes) -> &tg_val { {tg_str| kind: 4, value: v } }
  #|fn tg_bin(v: &tg_bytes) -> &tg_val { {tg_bin| kind: 5, value: v } }
  #|fn tg_instant(s: i64, n: i32) -> &tg_val { {tg_instant| kind: 6, secs: s, nanos: n } }
  #|fn tg_list(xs: &tg_vals, n: i32) -> &tg_val { {tg_list| kind: 7, items: xs, count: n } }
  #|fn tg_map(es: &tg_entries, n: i32) -> &tg_val { {tg_map| kind: 8, entries: es, count: n } }
  #|fn tg_func(f: &tg_fn, env: &?eq) -> &tg_val { {tg_func| kind: 9, call: f, env } }
  #|fn tg_comp(i: &tg_inst) -> &tg_val { {tg_comp| kind: 10, value: i } }
  #|fn tg_ext(t: i32, p: &?eq) -> &tg_val { {tg_ext| kind: 11, ext_kind: t, payload: p } }
  #|
  #|// The whole composition story, in two lines: a child from ANOTHER module is
  #|// an ordinary reference, and reading through it is a call, not a host hop.
  #|fn tg_child_field(child: &tg_inst, name: &tg_bytes) -> &?tg_val {
  #|    child.vt.get(child, name)
  #|}
  #|
  #|fn tg_child_call(child: &tg_inst, op: i32, name: &tg_bytes,
  #|                 args: &tg_vals, v: &?tg_val) -> &?tg_val {
  #|    child.vt.call(child, op, name, args, v)
  #|}

///|
/// A rejection is only useful if it says WHERE. The compiler's own renderer
/// wants a sink and a theme; a test wants one line.
fn diagnostics_line(ds : Array[@diagnostic.Diagnostic]) -> String {
  let parts : Array[String] = []
  for d in ds {
    parts.push("\{d.loc} \{@message.to_plain_string(d.message)}")
  }
  parts.join("; ")
}
