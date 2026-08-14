// The fixed half of every emitted module, in the two pieces a card cannot
// decide: the linear-memory allocator, and the constant helpers the expression
// compiler leans on.
//
// This file used to be the WHOLE value runtime — thirty-four functions built as
// an AST, because a value was a 16-byte `values.value` cell in linear memory
// and every one of them was pointer arithmetic. A value is now a `&jv_value`,
// the Wax data stdlib does the work, and tutuca's own semantics over it read
// far better as Wax source than as MoonBit that assembles Wax: see
// `runtime/runtime.wax`.
//
// What stayed is what the source half CANNOT say. `alloc` needs `heap`, whose
// initial value is the top of a constant pool only the generator knows the size
// of, and `cabi_realloc` is an export whose name the ABI fixes.

///|
/// A double from the constant pool: eight bytes, exactly as written.
///
/// Still the pool rather than a Wax float literal, for the reason it always
/// was: the spellings that survive a round trip exactly are the awkward ones,
/// and a generator that got one wrong would produce a module that is merely
/// slightly off rather than one that fails.
fn fconst(pool : @abi.Pool, x : Double) -> @abi.I {
  mem("loadf64", [i32c(pool.double(x))])
}

///|
/// The value of a string constant, by the index `#[start]` interned it at.
fn text_const(pool : @abi.Pool, s : String) -> @abi.I {
  call("tc_const", [i32c(pool.string_index(s))])
}

///|
/// The `&utf8_string` of a string constant — what a name is compared against.
fn text_const_str(pool : @abi.Pool, s : String) -> @abi.I {
  call("tc_const_str", [i32c(pool.string_index(s))])
}

///|
/// The allocator, as module fields.
///
/// Emitted between the memory and `runtime/runtime.wax`, which calls `alloc` to
/// put a string's bytes somewhere the host can read them.
fn runtime_fields() -> Array[@abi.Field] {
  let fs : Array[@abi.Field] = []

  // A bump allocator with no free. Every allocation an emitted module makes
  // lives until the instance is dropped, which for a card is the lifetime of
  // one edit-and-mount: the alternative is a real allocator, and a real
  // allocator is a much larger thing to be sure of than everything else here
  // put together.
  //
  // It now allocates far less than it used to. An expression node was an
  // allocation here; it is a GC object now, and what is left in linear memory
  // is only what crosses the ABI boundary — a string on its way out, and
  // whatever the host lowers on its way in.
  fs.push(
    func("alloc", params=[("size", i32_), ("align", i32_)], results=[i32_], body=[
      let_(
        "base",
        andi(
          add(get("heap"), sub(get("align"), i32c(1))),
          sub(i32c(0), get("align")),
        ),
      ),
      let_("end", add(get("base"), get("size"))),
      let_("have", mul(mem("size", []), i32c(65536))),
      if_(
        gts(get("end"), get("have")),
        [
          if_(
            lts(
              mem("grow", [
                divu(
                  add(sub(get("end"), get("have")), i32c(65535)),
                  i32c(65536),
                ),
              ]),
              i32c(0),
            ),
            [ret(Some(i32c(0)))],
            [],
          ),
        ],
        [],
      ),
      set("heap", get("end")),
      get("base"),
    ]),
  )

  // The canonical ABI's allocator. The host calls it to lower a string or a
  // list into guest memory; `old_ptr` is always 0 in that direction, and a
  // growing realloc never happens, so it is `alloc` under the name the ABI
  // insists on.
  fs.push(
    func(
      "cabi_realloc",
      params=[
        ("old_ptr", i32_),
        ("old_size", i32_),
        ("align", i32_),
        ("size", i32_),
      ],
      results=[i32_],
      export_as="cabi_realloc",
      body=[
        if_(
          gts(get("old_size"), i32c(0)),
          [
            let_("moved", call("alloc", [get("size"), get("align")])),
            mem("copy", [get("moved"), get("old_ptr"), get("old_size")]),
            ret(Some(get("moved"))),
          ],
          [],
        ),
        call("alloc", [get("size"), get("align")]),
      ],
    ),
  )
  fs
}
