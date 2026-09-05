// The frozen `tgc/2` ABI.
//
// READONLY by convention: the public data types plus `declare` stubs for every
// function. Implementations are in `tag.mbt`, `op.mbt` and `preamble.mbt`.
//
// Everything in this file is FROZEN. A tag number, an op number, an export name
// and — above all — the shape of the types in `preamble_wap` are the
// identity of the format, not choices it makes. Wasm GC canonicalizes a
// recursion group structurally: two modules that declare the same group get the
// SAME runtime type and can pass references to each other with no conversion,
// no linker and no registry. Change one field and every type in the group
// becomes a different type, in every module, retroactively.
//
// So: extend through `TagExt` and through the op space, never by adding an arm
// to the group.

///|
/// The ABI version, exported by every module as `tgc.abi`.
///
/// It is the identity of the frozen rec group, not a release number: it changes
/// when and only when the group changes. A host that reads a different one
/// REFUSES the module rather than adapting to it — there is nothing to adapt
/// to, because a different group is a different set of types and no reference
/// can cross between them.
pub const ABI_VERSION : Int = 2

///|
/// The tag every `tg_val` carries in its first field.
///
/// `TagNull` is 0 so that a zeroed struct is the null value, and `ref.null`
/// stays free to mean ABSENCE — "there is no such field" as against "the field
/// is null", which is the distinction the WIT needed `option<value>` for.
pub(all) enum Tag {
  TagNull
  TagBool
  TagNum
  TagInt
  TagStr
  TagBin
  TagInstant
  TagList
  TagMap
  TagFunc
  TagComp
  TagExt
} derive(Eq, Compare, Hash, Debug)

///|
/// The tag's wire number. Frozen: a value written by a module built today is
/// read by one built years later, and this number is the whole of what says
/// which case it is.
declare pub fn Tag::code(self : Tag) -> Int

///|
/// The tag for a wire number, or `None` for one this ABI does not define.
///
/// It cannot happen through a reference — a foreign tag would mean a foreign
/// group, and then no reference crosses at all — but it can happen through the
/// JSON boundary, which is text and believes whoever wrote it.
declare pub fn Tag::of_code(code : Int) -> Tag?

///|
/// The name of the Wax type that holds this case, e.g. `tg_str`.
declare pub fn Tag::type_name(self : Tag) -> String

///|
/// Every tag this ABI defines, in code order.
declare pub fn all_tags() -> Array[Tag]

///|
/// What the single `call` vtable slot is being asked to do.
///
/// One op-coded entry point rather than one slot per operation, and that is the
/// design rather than a saving: the vtable's TYPE is inside the frozen group, so
/// a slot added later would change the identity of every type in it. An `i32` op
/// space extends forever and costs one `br_table`.
///
/// Getting a field is absent on purpose — it has its own vtable slot, because it
/// runs once per `.name` per render and is the only call on the hot path.
pub(all) enum Op {
  OpWithField
  OpHandleMessage
  OpHandleIntent
  OpCompute
  OpWhen
  OpEnrich
  OpEnrichScope
  OpGetProperty
  OpSetProperty
  OpSeqEntries
  OpImplements
  OpPersist
  OpRestore
  OpIdentity
  OpDebug
} derive(Eq, Compare, Hash, Debug)

///|
/// The op's wire number. Frozen for the same reason a tag is.
declare pub fn Op::code(self : Op) -> Int

///|
/// The op for a wire number, or `None`.
///
/// A module that meets an unknown op answers `ref.null` — "I do not do that" —
/// which is exactly the answer an older module gives for an op invented after it
/// was built. That is what makes the space extensible rather than merely large.
declare pub fn Op::of_code(code : Int) -> Op?

///|
/// The op's name, as a host writes it in a log.
declare pub fn Op::name(self : Op) -> String

///|
/// Every op this ABI defines, in code order.
declare pub fn all_ops() -> Array[Op]

///|
/// The four names a `tgc` module exports. A module missing any of them is not a
/// `tgc` module; a module exporting more is free to.
pub let export_abi : String = "tgc.abi"

///|
pub let export_describe : String = "tgc.describe"

///|
pub let export_make : String = "tgc.make"

///|
pub let export_serve : String = "tgc.serve"

///|
/// The one import namespace.
///
/// A module's import section is its COMPLETE authority list — a `tgc` module
/// declares no memory and no table, so there is nothing else to reach through —
/// which is the property `tgc/SECURITY.md` relies on, made total.
pub let import_namespace : String = "tut"

///|
/// The canonical preamble as **wap** source: the form a generator emits and a
/// person reads. Every `tgc` module is compiled with exactly these types.
///
/// Byte-for-byte identity is not REQUIRED — wap names are local and each group
/// is canonicalized structurally — but it is what the emitters do. A deliberate
/// re-spelling is a thing to test (`tgc/proto/clock`) rather than a thing to
/// leave lying around.
declare pub fn preamble_wap() -> String

///|
/// The same types as **WAT** text, for a hand-written module and for the error
/// a host prints when a module's types do not match.
///
/// It IS derived from `preamble_wap`, by lowering and printing it. `tgc/1` kept
/// a second hand-written copy and a test that the two canonicalized the same;
/// the test could only ever find a drift that had already been committed, so
/// the second copy is gone and the compiler answers instead.
declare pub fn preamble_wat() -> String raise PreambleError

///|
/// The name wap gives the preamble module, and therefore the qualifier a
/// generated module writes in front of every type it names.
///
/// A generated module must name these types NOMINALLY — `tgabi.tg_vals`, never
/// an inline `[tg_val?]`. wap interns an anonymous array or function type into a
/// group of its own, which is a different wasm type from the nominal one and
/// fails to link against a runtime built from this text.
pub let preamble_module : String = "tgabi"

///|
/// The preamble failed to compile, which is a bug in this package.
///
/// It cannot be an input error: there is no input. A caller that catches this
/// is catching a broken build, so the message says which stage rather than
/// offering a remedy.
pub suberror PreambleError {
  PreambleBug(String)
}

///|
pub impl Show for PreambleError with fn output(self, logger) {
  match self {
    PreambleBug(m) => logger.write_string(m)
  }
}

///|
/// The function vocabulary a generated module reaches for, as TYPES.
///
/// `tgc/1` kept this as eighty signature STRINGS in `tgc/emit`, spliced into
/// generated Wax and never compared against what `tgc/rt` actually exported. The
/// two could disagree, and when they did the first thing to notice was a
/// browser refusing to instantiate. Here they are wap types, one table, read by
/// three parties: `tgc/emit` builds its `tut` import block from it, `tgc/rt`'s
/// test asserts the runtime exports exactly these, and a host names the
/// offender when a link fails.
///
/// ── Why no entry names a frozen FUNCTION type ────────────────────────────
///
/// `tgc/1` bound `get_field` and `call_op` to `tg_get` and `tg_call` so the
/// link would check against the recursion group rather than against a singleton
/// that looked like it. wap cannot say that — an imported function carries an
/// inline signature and no named type — and under `tgc/2` it does not need to:
/// both take a `tg_inst`, `tg_inst` is IN the one recursion group, and a
/// parameter type carries its group's identity. A module whose group differs
/// still fails to link, at the parameter instead of at the signature.
pub(all) enum Supplier {
  /// `tgc/rt` exports it. A pure function over values, available to any module
  /// that links the runtime.
  Runtime
  /// The HOST supplies it, and the runtime must not. Every effect is here, and
  /// that is the authority story rather than a division of labour: an effect is
  /// something done to the world outside the module, so it comes from whoever
  /// owns that world. A runtime that exported `eff_send` would be a runtime
  /// that could send.
  Host
} derive(Eq, Debug)

///|
pub(all) struct VocabFn {
  /// What the generated module calls it.
  name : String
  /// Who answers when a card calls it.
  supplier : Supplier
  /// What `tut` exports it as. The two differ where a constructor reads better
  /// from inside a card than from inside the runtime — `tg_num` there is
  /// `mk_num` here.
  import_name : String
  params : Array[(String, @wast.Type)]
  results : Array[@wast.Type]
}

///|
/// The whole vocabulary. The emitter filters it by what a card actually
/// called, so a module's import section stays a truthful authority list.
declare pub fn vocab() -> Array[VocabFn]
