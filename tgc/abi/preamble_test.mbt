///|
/// The preamble is a module a compiler accepts, not a string that looks like
/// one. Without this test `preamble_wap` is a comment.
test "the wap preamble compiles" {
  let src = @abi.preamble_wap() + "\n" + probe_wap
  match @wap.compile_string(src, fname="tgabi.wap") {
    Ok(bytes) => assert_true(bytes.length() > 8)
    Err(d) => fail("rejected: " + wap_line(d))
  }
}

///|
/// A module that only DECLARES the types carries none of them into its type
/// section unless something uses them, so the probe reaches for every arm. It is
/// also the smallest worked example of the two calls that matter: reading a
/// field of a child, and asking it to do something.
let probe_wap : String =
  #|fn tg_null() -> tg_val:
  #|  tg_val{ kind: 0 }
  #|fn mk_bool(v :: i32) -> tg_val:
  #|  tg_bool{ kind: 1, value: v }
  #|fn mk_num(v :: f64) -> tg_val:
  #|  tg_num{ kind: 2, value: v }
  #|fn mk_int(v :: i64) -> tg_val:
  #|  tg_int{ kind: 3, value: v }
  #|fn mk_str(v :: tg_bytes) -> tg_val:
  #|  tg_str{ kind: 4, value: v }
  #|fn mk_bin(v :: tg_bytes) -> tg_val:
  #|  tg_bin{ kind: 5, value: v }
  #|fn mk_instant(s :: i64, n :: i32) -> tg_val:
  #|  tg_instant{ kind: 6, secs: s, nanos: n }
  #|fn mk_list(xs :: tg_vals, n :: i32) -> tg_val:
  #|  tg_list{ kind: 7, items: xs, count: n }
  #|fn mk_map(es :: tg_entries, n :: i32) -> tg_val:
  #|  tg_map{ kind: 8, entries: es, count: n }
  #|fn mk_func(f :: tg_fn, env :: eq?) -> tg_val:
  #|  tg_func{ kind: 9, call: f, env: env }
  #|fn mk_comp(i :: tg_inst) -> tg_val:
  #|  tg_comp{ kind: 10, value: i }
  #|fn mk_ext(t :: i32, p :: eq?) -> tg_val:
  #|  tg_ext{ kind: 11, ext_kind: t, payload: p }
  #|fn mk_entry(k :: tg_bytes, v :: tg_val?) -> tg_entry:
  #|  tg_entry{ key: k, value: v }
  #|
  #|// The whole composition story, in two lines: a child from ANOTHER module is
  #|// an ordinary reference, and reading through it is a call, not a host hop.
  #|export "child_field" fn child_field(child :: tg_inst, name :: tg_bytes) -> tg_val?:
  #|  child.vt.get(child, name)
  #|
  #|export "child_call" fn child_call(child :: tg_inst, op :: i32, name :: tg_bytes,
  #|                                  args :: tg_vals, v :: tg_val?) -> tg_val?:
  #|  child.vt.call(child, op, name, args, v)
  #|

///|
/// The WAT rendering is the compiler's answer, so the only thing left to say
/// about it is that it is the answer to THIS question: every type the format
/// names appears, and nothing else does.
test "the WAT rendering names every type" {
  let wat = @abi.preamble_wat()
  for
    name in [
      "tg_bytes", "tg_val", "tg_vals", "tg_entry", "tg_entries", "tg_get", "tg_call",
      "tg_fn", "tg_vt", "tg_inst", "tg_bool", "tg_num", "tg_int", "tg_str", "tg_bin",
      "tg_instant", "tg_list", "tg_map", "tg_func", "tg_comp", "tg_ext",
    ] {
    let decl = "$tgabi__" + name
    assert_true(wat.contains(decl + " ") || wat.contains(decl + "\n"), msg=name)
  }
  assert_false(wat.contains("(module"), msg="the module wrapper is not a type")
}

///|
/// The one recursion group is the one cycle.
///
/// This is what changed at `tgc/2` and the reason the version moved: wap emits
/// a group per strongly connected component, so `tg_get`, `tg_inst`, `tg_vt`
/// and `tg_call` share one and NOTHING else shares anything. A change that
/// widens this group is a change to what a stranger's module has to match, and
/// it should fail here first.
test "only the vtable cycle is a recursion group" {
  let wat = @abi.preamble_wat()
  let mut groups = 0
  for line in wat.split("\n") {
    if line.trim(chars=" ").has_prefix("(rec") {
      groups += 1
    }
  }
  assert_eq(groups, 1)
}

///|
/// A rejection is only useful if it says WHERE.
fn wap_line(d : @wap.Diagnostics) -> String {
  let parts : Array[String] = []
  for r in d.wap {
    parts.push(r.message)
  }
  for x in d.wax {
    parts.push(@message.to_plain_string(x.message))
  }
  parts.join("; ")
}

///|
/// The WAT rendering is TEXT A COMPILER WOULD ACCEPT, not a plausible-looking
/// excerpt.
///
/// This exists because it caught a real one: the first `type_section_of` threw
/// away every line that was a bare `)`, which is exactly the line that closes a
/// type declaration spanning more than one line. Every name still appeared and
/// the module wrapper was still absent, so the two tests above stayed green
/// while `tg_entry` lost its closing paren. Counting parens is the cheapest
/// question that has a wrong answer.
test "the WAT rendering is balanced" {
  let wat = @abi.preamble_wat()
  let mut depth = 0
  let mut lowest = 0
  for c in wat {
    if c == '(' {
      depth += 1
    } else if c == ')' {
      depth -= 1
      if depth < lowest {
        lowest = depth
      }
    }
  }
  assert_eq(depth, 0, msg="unbalanced")
  assert_eq(lowest, 0, msg="closed more than it opened")
}
