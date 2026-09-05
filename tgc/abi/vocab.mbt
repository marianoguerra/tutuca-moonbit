///|
/// A nominal type of the preamble module, qualified the way a generated module
/// must write it.
///
/// Never build these inline. wap interns an anonymous `[tg_val?]` into a
/// recursion group of its own, which is a different wasm type from `tg_vals`
/// and fails to link against the runtime.
fn t(name : String) -> @wast.Type {
  Named(preamble_module + "." + name)
}

///|
/// A value that may have NO ANSWER. This is the two-nulls rule in the type: an
/// operation with no answer for its arguments answers null, and the transition
/// above it does not happen.
let opt_val : @wast.Type = Nullable(Named("tgabi.tg_val"))

///|
fn f(
  name : String,
  import_name? : String? = None,
  supplier? : Supplier = Runtime,
  params : Array[(String, @wast.Type)],
  results : Array[@wast.Type],
) -> VocabFn {
  {
    name,
    supplier,
    import_name: match import_name {
      Some(n) => n
      None => name
    },
    params,
    results,
  }
}

///|
/// One `&?tg_val` in, one out — the shape most of the vocabulary has.
fn un(name : String) -> VocabFn {
  f(name, [("v", opt_val)], [opt_val])
}

///|
/// Two in, one out.
fn bin(name : String) -> VocabFn {
  f(name, [("a", opt_val), ("b", opt_val)], [opt_val])
}

///|
/// An effect: arguments in, nothing out. Performed through the host, which
/// brackets the call and discards what a transition that abandoned had done.
fn eff(name : String, params : Array[(String, @wast.Type)]) -> VocabFn {
  f(name, supplier=Host, params, [])
}

///|
/// The whole vocabulary, in the order a reader wants it rather than the order
/// the emitter needs — the emitter filters by what a card actually called.
pub fn vocab() -> Array[VocabFn] {
  let bytes = t("tg_bytes")
  let val = t("tg_val")
  let vals = t("tg_vals")
  let entry = t("tg_entry")
  let entries = t("tg_entries")
  let inst = t("tg_inst")
  let i32_ : @wast.Type = I32
  let f64_ : @wast.Type = F64
  [
    // ── composition: the two calls that are the whole of it ──────────────
    f("get_field", [("inst", inst), ("name", bytes)], [opt_val]),
    f(
      "call_op",
      [
        ("inst", inst),
        ("op", i32_),
        ("name", bytes),
        ("args", vals),
        ("v", opt_val),
      ],
      [opt_val],
    ),
    // ── constructors: these cannot fail, and say so ──────────────────────
    f("tg_null", import_name=Some("mk_null"), [], [val]),
    f("tg_bool", import_name=Some("mk_bool"), [("b", i32_)], [val]),
    f("tg_num", import_name=Some("mk_num"), [("n", f64_)], [val]),
    f("tg_str", import_name=Some("mk_str"), [("b", bytes)], [val]),
    f("tg_list", import_name=Some("mk_list"), [("items", vals)], [val]),
    f("tg_map", import_name=Some("mk_map"), [("entries", entries)], [val]),
    f("tg_comp", import_name=Some("mk_comp"), [("inst", inst)], [val]),
    f(
      "tg_entry_of",
      import_name=Some("entry_of"),
      [("key", bytes), ("value", opt_val)],
      [entry],
    ),
    f("tg_no_args", import_name=Some("no_args"), [], [vals]),
    // ── reading arguments and text ───────────────────────────────────────
    f(
      "tg_arg",
      import_name=Some("arg"),
      [("args", opt_val), ("key", bytes), ("zero", opt_val)],
      [opt_val],
    ),
    f("tg_arg_at", import_name=Some("arg_at"), [("args", vals), ("i", i32_)], [
      opt_val,
    ]),
    f("str_eq", [("a", bytes), ("b", bytes)], [i32_]),
    f("tg_truthy", import_name=Some("truthy"), [("v", opt_val)], [i32_]),
    f("display", [("v", opt_val)], [bytes]),
    f("concat", [("a", bytes), ("b", bytes)], [bytes]),
    // Which arm a value is, for the one place a compiled body has to ask:
    // `cur` is materialized at its first READ, and "has it been already" is
    // that question.
    f("kind_of", [("v", val)], [i32_]),
    // ── arithmetic and comparison ────────────────────────────────────────
    un("trunc"),
    bin("op_add"),
    bin("op_sub"),
    bin("op_mul"),
    bin("op_div"),
    bin("op_mod"),
    un("op_neg"),
    bin("op_lt"),
    bin("op_le"),
    bin("op_gt"),
    bin("op_ge"),
    bin("op_is"),
    bin("op_is_not"),
    // ── the closed builtin vocabulary ────────────────────────────────────
    un("b_empty"),
    un("b_truthy"),
    un("b_falsy"),
    un("b_null"),
    un("b_not"),
    un("b_len"),
    bin("b_has"),
    bin("b_contains"),
    bin("b_min"),
    bin("b_max"),
    f("b_clamp", [("v", opt_val), ("lo", opt_val), ("hi", opt_val)], [opt_val]),
    un("b_int"),
    un("b_num"),
    un("b_str"),
    un("b_lower"),
    un("b_upper"),
    un("b_trim"),
    // ── reading and rebuilding a place ───────────────────────────────────
    f("item", [("coll", opt_val), ("key", opt_val)], [opt_val]),
    f("member", [("v", opt_val), ("name", bytes)], [opt_val]),
    f("with_item", [("coll", opt_val), ("key", opt_val), ("x", opt_val)], [
      opt_val,
    ]),
    f("with_member", [("v", opt_val), ("name", bytes), ("x", opt_val)], [
      opt_val,
    ]),
    bin("coll_push"),
    f("coll_insert_at", [("v", opt_val), ("at", opt_val), ("x", opt_val)], [
      opt_val,
    ]),
    f("coll_set_at", [("v", opt_val), ("at", opt_val), ("x", opt_val)], [
      opt_val,
    ]),
    f("coll_delete_at", [("v", opt_val), ("at", opt_val)], [opt_val]),
    bin("coll_add"),
    bin("coll_remove"),
    bin("coll_toggle"),
    // ── the reified path a `sendAt` addresses ────────────────────────────
    f("mk_step_field", [("name", bytes)], [opt_val]),
    f("mk_step_key", [("field", bytes), ("key", opt_val)], [opt_val]),
    // ── the effects ──────────────────────────────────────────────────────
    eff("eff_send", [("name", bytes), ("args", vals)]),
    eff("eff_send_at", [("path", opt_val), ("name", bytes), ("args", vals)]),
    eff("eff_reply", [("name", bytes), ("args", vals)]),
    eff("eff_answer", [("v", opt_val)]),
    eff("eff_ask", [("name", bytes), ("args", vals), ("route", i32_)]),
    eff("eff_notify", [("name", bytes), ("args", vals), ("route", i32_)]),
    eff("eff_forward", [("args", vals), ("route", i32_)]),
    eff("eff_fail", [("v", opt_val)]),
    eff("eff_drop", []),
    // What a DECLINED rule says. A transition that stopped and said nothing is
    // indistinguishable from a click that missed.
    eff("eff_log", [("msg", bytes)]),
  ]
}
