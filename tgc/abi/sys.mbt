///|
/// What wap cannot say, Wax says.
///
/// This is wap's own escape hatch — `import was`, which declares a signature and
/// leaves the definition to a module compiled beside it, the way Oberon reached
/// for `SYSTEM`. wap records the signature, marks the name foreign so it takes
/// no module prefix, and emits nothing; supplying the field is the embedder's
/// job, and this is it.
///
/// ── The one thing on the list ────────────────────────────────────────────
///
/// A MUTABLE GLOBAL. wap's `Decl` has `Const` and no `Var`, so a module cannot
/// hold a cell that changes, and instance identity is exactly that: a counter
/// nobody reads but everybody advances.
///
/// ── Why the counter moved into the runtime ───────────────────────────────
///
/// Under `tgc/1` it did not live here. Every generated module declared its own
/// `tgc_next_id`, starting at zero — and `val_eq` compares two component values
/// by `id` ALONE, so the first instance made by one module and the first
/// instance made by another had the same id and compared EQUAL. In a format
/// whose whole claim is that modules built by different people compose, that is
/// the wrong scope: identity has to be unique over everything that shares a
/// runtime, because that is the set of instances that can meet.
///
/// So the counter is the runtime's, exported as `next_id`, and a generated
/// module asks for one. Wap forcing the question is how it got asked.
pub fn runtime_sys_fields() -> @wax_ast.LocModule {
  let s = @build.Spans::new(fname="tgc/sys")
  let i64_ : @wasm_types.ValType[@wax_ast.Ident] = I64
  [
    @build.global(
      id_counter,
      typ=Some(i64_),
      mut_=true,
      def=s.instr(Int("0")),
      at=s.fresh(),
    ),
    @build.func(
      sys_next_id,
      results=[i64_],
      body=[
        s.instr(
          Set(s.ident(id_counter), Some(@basic.no_loc(Add)), s.instr(Int("1"))),
        ),
        s.instr(Get(s.ident(id_counter))),
      ],
      at=s.fresh(),
    ),
  ]
}

///|
/// The counter itself. Private to the runtime: nothing imports it, and the only
/// thing that reads it hands out the value after advancing it.
let id_counter : String = "tgc_id_counter"

///|
/// The `import was` block `tgc/rt` writes to reach them.
///
/// It names a file that is not on disk, and that is not a lie so much as the
/// shape of the mechanism: `import was` records signatures and lowers to
/// nothing, so the name is documentation for a reader and the fields are the
/// contract. Pointing it at `tgc/abi/sys.mbt` sends that reader somewhere they
/// can actually look.
pub fn sys_import_wap() -> String {
  let src =
    #|// What wap cannot say: a mutable global. Built by `@abi.runtime_sys_fields`,
    #|// not parsed from a file.
    #|import was "tgc/abi/sys.mbt":
    #|  fn tgc_next_id() -> i64
    #|
  src
}
