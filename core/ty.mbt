// A declared field's TYPE.
//
// ONE type lattice. There were two — this one, `TyInfo`, which the runtime
// walks, and `@statedef.StateTy`, which the schema parses into and the
// generators emit from — described as a "projection" of each other. They were
// not: they had the same sixteen shapes, and the projection between them was a
// hand-maintained table in `statedef/types.mbt` with a hand-maintained twin in
// `statedef/info/info.mbt`, one emitting SOURCE and the other building VALUES.
// A type added to the schema had to be added in four places, and the one that
// was forgotten was the one nobody read until a manifest lost a field's
// element type.
//
// What made them look different was one honest asymmetry: a closed set's
// members and a record's fields need a DECLARATION to resolve, and the runtime
// has none. That is answered by carrying what only the schema knows — a
// `TyFlags` carries its members inline — and by keeping a name where the shape
// is the instance's to open: a record, an enum and a variant keep a name and
// nothing else, which is enough to label them and not enough to open them.
//
// `TyInfo` is the older name and still reads.

///|
/// What a declared field carries.
#alias(TyInfo)
pub(all) enum Ty {
  TyBool
  /// Every `Int8`..`Int`/`UInt8`..`UInt`. Width and signedness survive so a
  /// decode can range-check, even though every one of them emits a MoonBit
  /// `Int` — by the time a value reaches the runtime the generated codec has
  /// already applied the check.
  TyInt(width~ : Int, signed~ : Bool)
  TyFloat
  TyText
  TyList(Ty)
  TyTuple(Array[Ty])
  TyOption(Ty)
  /// A named record. The name labels it; its fields are the instance's to
  /// answer.
  TyRecord(String)
  TyEnum(String)
  TyVariant(String)
  /// A set with CLOSED membership, carrying the members the schema declared —
  /// the one thing about a set that only the schema knows, since the encoded
  /// value is just a Map.
  TyFlags(String, Array[String])
  /// A set with OPEN membership.
  TySet
  /// An ordered map. WIT's own `map` is unordered by definition, so this is a
  /// refinement of it rather than a spelling for it.
  TyOMap(Ty)
  /// A child-component slot; None when the schema said only `component`.
  TyComp(String?)
  /// A dynamically composed child constrained by canonical protocol ids.
  ///
  /// Deliberately distinct from `TyComp`: a component name is a construction
  /// hint, while protocols are capabilities checked when an instance is
  /// installed in the slot.
  TyCompProtocols(Array[String])
  /// Tabular data: typed columns of equal width (`tables.table`).
  ///
  /// The one named shape whose contents the schema DOES know. `TyRecord` keeps
  /// a name and nothing else because a record's fields are the instance's to
  /// answer; a table is standard, so the projection can describe it fully, a
  /// validator can check it, and an agent can be told how to write one. That
  /// is the whole reason it is a case here rather than `TyRecord("table")`.
  TyTable
  /// An arbitrary `Value`.
  TyAny
} derive(Eq, Debug)

///|
/// How the author wrote it. The WIT spelling, because that is what is in the
/// file and what they will edit.
pub fn Ty::show_source(self : Ty) -> String {
  match self {
    TyBool => "Bool"
    TyInt(width~, signed~) =>
      match (width, signed) {
        (32, true) => "Int"
        (8, true) => "Int8"
        (16, true) => "Int16"
        (32, false) => "UInt"
        (8, false) => "UInt8"
        _ => "UInt16"
      }
    TyFloat => "Double"
    TyText => "String"
    TyList(e) => "Array[" + e.show_source() + "]"
    TyTuple(ts) => "(" + ts.map(t => t.show_source()).join(", ") + ")"
    TyOption(e) => e.show_source() + "?"
    TyRecord(n) | TyEnum(n) | TyVariant(n) => n
    // A closed set names its enum, which is where the membership is written.
    TyFlags(n, _) => "Set[" + n + "]"
    TySet => "Set[String]"
    TyOMap(v) => "Map[String, " + v.show_source() + "]"
    TyComp(Some(c)) => "Instance[" + c + "]"
    TyComp(None) => "Instance"
    TyCompProtocols(ids) => "Instance[protocol " + ids.join(" & ") + "]"
    TyTable => "Table"
    TyAny => "Any"
  }
}

///|
/// What this type CONTAINS, or None when it contains nothing.
///
/// Strict, and deliberately not the same question `iterable_elem` answers.
/// That one asks "may a view `@each` over this?", where `any` and a child slot
/// must both say yes — a dynamic value may turn out to be a list and a
/// component iterates its own entries, neither knowable at generation time.
/// Answering the two with one method put a meaningless `elem: any` on 117
/// fields of the corpus and showed it in the inspector, where the question is
/// the other one: what is in here?
pub fn Ty::elem(self : Ty) -> Ty? {
  match self {
    TyList(e) | TyOMap(e) => Some(e)
    // A set iterates its members, which are text either way.
    TySet | TyFlags(_, _) => Some(TyText)
    _ => None
  }
}

///|
/// The component a child slot holds, or None for a data field. `Some("")` is a
/// slot whose component the schema did not name.
pub fn Ty::slot(self : Ty) -> String? {
  match self {
    TyComp(Some(c)) => Some(c)
    TyComp(None) => Some("")
    TyCompProtocols(_) => Some("")
    _ => None
  }
}

///|
/// A closed set's declared members. Empty for every other type, and for a set
/// with open membership — which is a real answer, not a missing one.
pub fn Ty::members(self : Ty) -> Array[String] {
  match self {
    TyFlags(_, ms) => ms
    _ => []
  }
}

///|
/// The runtime kind: how a value of this type is REPRESENTED, once the shape
/// that distinguishes it no longer matters.
///
/// A projection rather than a stored field, which is the point.
pub fn Ty::kind(self : Ty) -> FieldKind {
  match self {
    TyBool => FBool
    TyInt(..) => FInt
    TyFloat => FFloat
    // An enum is payload-free, so it travels as its case name.
    TyText | TyEnum(_) => FText
    TyList(_) | TyTuple(_) => FList
    // A table travels as `{"columns": [...]}` — a Map, like a record. What
    // makes it different is what the SCHEMA can say about it, not how the
    // value is carried.
    TyRecord(_) | TyTable => FMap
    // A variant travels as EITHER a bare case name or a case name followed by
    // its payload — `Str("Ping")` or `List(["SetTo", 7])`. No single narrow
    // kind covers both, and the old table said `FMap`, which covers neither: a
    // write of a perfectly good variant value hit `coerce_or_default`, failed
    // the `Map` shape test and was replaced by the field's default.
    TyVariant(_) => FAny
    TySet | TyFlags(_, _) => FSet
    TyOMap(_) => FOMap
    // The slot's construction arguments are not part of its TYPE; the component
    // layer fills them in from what the author wired.
    TyComp(c) => FComp(comp=c.unwrap_or(""), args=Map([]))
    TyCompProtocols(_) => FComp(comp="", args=Map([]))
    // An `option` is its value or absent, so the kind is the widest one: the
    // field may hold the inner shape or nothing.
    TyOption(_) | TyAny => FAny
  }
}

///|
/// The empty value of this type, as the runtime carries it.
///
/// Type-directed, like the generated `<T>State::zero()` — which is the point:
/// a default is not an independent fact about a field, so storing one beside
/// the type would be a second thing to keep true. The one default a TYPE cannot
/// give is a child slot's construction arguments, and those are a value the
/// author chooses rather than anything the schema knows.
///
/// This is what an inspector shows in a field's "default" column, reachable
/// from a bare `Value`.
pub fn Ty::zero(self : Ty) -> Value {
  match self {
    TyBool => Bool(false)
    TyInt(..) | TyFloat => Num(0.0)
    TyText | TyEnum(_) => Str("")
    TyList(_) | TyTuple(_) => List([])
    TyRecord(_) | TyOMap(_) => Map(Map([]))
    // No columns and therefore no rows. Spelled out rather than left as an
    // empty Map because `{"columns": []}` is a VALID table and `{}` is not:
    // the zero of a table should decode, not fail the first check made of it.
    TyTable => Map({ "columns": List([]) })
    // Both sets start EMPTY: the CONTAINER decides the zero and the enum
    // decides the membership, which is one idea in each place.
    TyFlags(_, _) | TySet => Map(Map([]))
    // A variant's zero is its first case, which this cannot name; an option
    // is absent; a slot is filled by the registration scope at make time.
    TyVariant(_) | TyOption(_) | TyComp(_) | TyCompProtocols(_) | TyAny => Null
  }
}

///|
/// Whether a runtime value has this declared outer shape. Named records and
/// variants remain permissive because their structural declaration is not
/// carried by `Ty`; generated decoders perform the deeper check.
pub fn Ty::accepts(self : Ty, value : Value) -> Bool {
  match (self, value) {
    (TyBool, Bool(_)) => true
    (TyInt(..) | TyFloat, Num(_)) => true
    (TyText | TyEnum(_), Str(_)) => true
    (TyList(_) | TyTuple(_), List(_)) => true
    (TyRecord(_) | TyOMap(_) | TySet | TyFlags(_, _) | TyTable, Map(_)) => true
    (TyComp(_) | TyCompProtocols(_), Obj(_)) => true
    (TyVariant(_), Str(_) | List(_)) => true
    (TyOption(_), Null) => true
    (TyOption(inner), other) => inner.accepts(other)
    (TyAny, _) => true
    _ => false
  }
}

///|
/// What a view may `@each` OVER, and what one item of it is.
///
/// Deliberately more permissive than `elem`, and a different question: this one
/// asks "may a view iterate this?", where `any` and a child slot must both say
/// yes — a dynamic value may turn out to be a list at run time, and a component
/// iterates its own `seq_entries` — while `elem` asks what is actually IN here
/// and answers nothing for both.
pub fn Ty::iterable_elem(self : Ty) -> Ty? {
  match self {
    TyList(e) | TyOMap(e) => Some(e)
    // A set iterates its members, which are text either way: a closed set has
    // declared membership, an open one does not.
    TySet | TyFlags(_, _) => Some(TyText)
    TyTuple(_) => Some(TyAny)
    // A table iterates its columns.
    TyTable => Some(TyAny)
    TyAny | TyComp(_) | TyCompProtocols(_) => Some(TyAny)
    _ => None
  }
}

///|
/// True when this field lives in the state STRUCT — which is every field.
///
/// A slot is a `Value` field like any other, seeded with `Null` and filled at
/// make time.
pub fn Ty::in_struct(_self : Ty) -> Bool {
  true
}

///|
/// Whether writing this type in a boolean position can ever decide anything.
///
/// Everything has a truthiness at run time; this asks whether the test can
/// fail. `Value::is_truthy` answers `true` for List, Map and Obj
/// unconditionally, so a container in an `@show` is a test that cannot fail —
/// almost always a forgotten `.length` or field read.
///
/// A string, a number and an enum are NOT in that set even though they are not
/// booleans: `@show=".role"` beside `@text=".role"` is the idiomatic way to
/// hide an empty badge, and `@show=".count"` hides a zero. Flagging those would
/// cost more in false failures than the real ones are worth — the rule stated
/// at the head of `viewgen/check_state.mbt`.
pub fn Ty::is_boolish(self : Ty) -> Bool {
  match self {
    TyList(_)
    | TyTuple(_)
    | TyRecord(_)
    | TyVariant(_)
    | TyFlags(_, _)
    | TySet
    | TyOMap(_)
    | TyTable => false
    _ => true
  }
}

///|
/// The component this type names, when it names one.
///
/// `greeting?` is a slot the way `greeting` is — `is_renderable` unwraps an
/// option, so the question "which component" has to unwrap it the same way or
/// the two disagree about the same field.
pub fn Ty::component_named(self : Ty) -> String? {
  match self {
    TyComp(c) => c
    TyCompProtocols(_) => None
    TyOption(inner) => inner.component_named()
    _ => None
  }
}

///|
/// Whether `<x render=".field">` can render a value of this type.
pub fn Ty::is_renderable(self : Ty) -> Bool {
  match self {
    TyComp(_) | TyCompProtocols(_) | TyAny => true
    TyOption(inner) => inner.is_renderable()
    _ => false
  }
}

///|
/// The MoonBit source of the expression that rebuilds this type.
///
/// What `gen-views` splices into a generated `SchemaInfo`. It is a method on
/// the type rather than a table in the generator, and that is the whole point
/// of there being one `Ty`: the source form and the value form cannot describe
/// different shapes if one of them IS the shape.
///
/// The constructors are written UNQUALIFIED, and have to be: an enum
/// constructor does not resolve through the `pub using` re-export that keeps
/// `@component.Ty` spelling correct, nor through the module-root facade the
/// playground compiles examples against. Bare works in both, because the only
/// position the generator writes one into — a `FieldInfo::new` argument —
/// already knows the type.
pub fn Ty::to_mbt_source(self : Ty) -> String {
  fn quoted(s : String) -> String {
    "\"" + s + "\""
  }

  match self {
    TyBool => "TyBool"
    TyInt(width~, signed~) => "TyInt(width=\{width}, signed=\{signed})"
    TyFloat => "TyFloat"
    TyText => "TyText"
    TyList(e) => "TyList(" + e.to_mbt_source() + ")"
    TyTuple(ts) =>
      "TyTuple([" + ts.map(t => t.to_mbt_source()).join(", ") + "])"
    TyOption(e) => "TyOption(" + e.to_mbt_source() + ")"
    TyOMap(v) => "TyOMap(" + v.to_mbt_source() + ")"
    TyRecord(n) => "TyRecord(" + quoted(n) + ")"
    TyEnum(n) => "TyEnum(" + quoted(n) + ")"
    TyVariant(n) => "TyVariant(" + quoted(n) + ")"
    // A closed set's members are INLINED rather than named: this is read at
    // run time, where the declaration they would refer to does not exist.
    TyFlags(n, ms) =>
      "TyFlags(" + quoted(n) + ", [" + ms.map(quoted).join(", ") + "])"
    TySet => "TySet"
    TyTable => "TyTable"
    TyComp(Some(c)) => "TyComp(Some(" + quoted(c) + "))"
    TyComp(None) => "TyComp(None)"
    // Protocol-constrained slots retain their constraint in SchemaInfo; the
    // runtime uses it when a dynamic instance is installed.
    TyCompProtocols(ids) =>
      "TyCompProtocols([" + ids.map(quoted).join(", ") + "])"
    TyAny => "TyAny"
  }
}
