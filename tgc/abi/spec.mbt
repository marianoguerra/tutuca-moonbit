// The frozen `tgc/1` ABI.
//
// READONLY by convention: the public data types plus `declare` stubs for every
// function. Implementations are in `tag.mbt`, `op.mbt` and `preamble.mbt`.
//
// Everything in this file is FROZEN. A tag number, an op number, an export name
// and — above all — the shape of the rec group in `preamble_wax` are the
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
pub const ABI_VERSION : Int = 1

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
/// group, and then no reference crosses at all — but it can happen through
/// CBOR, which is bytes and believes whoever wrote them.
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
/// which is the property `dyncomp/SECURITY.md` already relies on, made total.
pub let import_namespace : String = "tut"

///|
/// The canonical preamble as **Wax** source: the form a generator emits and a
/// person reads. Every `tgc` module begins with exactly this text.
///
/// Byte-for-byte identity is not REQUIRED — Wax names are local and the group is
/// canonicalized structurally — but it is what the emitters do. A deliberate
/// re-spelling is a thing to test (`tgc/proto/clock`) rather than a thing to
/// leave lying around.
declare pub fn preamble_wax() -> String

///|
/// The same types as **WAT** text, for a hand-written module and for the error
/// a host prints when a group does not match.
///
/// It is not derived from `preamble_wax` and does not have to be: they are two
/// renderings that must CANONICALIZE the same, which is a stronger claim than
/// textual correspondence and is what `preamble_agreement_test` checks.
declare pub fn preamble_wat() -> String
