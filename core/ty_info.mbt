// A declared field's TYPE, as data the runtime can walk.
//
// This is the schema's type lattice projected into the value world. Here the
// spelling and the kind are both FUNCTIONS of the type, so they cannot
// disagree.
//
// It is a PROJECTION of `@statedef.StateTy`, not the same enum. Two differences,
// both because generation-time lookups are not available here: a `flags` set
// carries its members inline rather than by reference to a declaration, and a
// record / enum / variant keeps only its name — enough to label it, not enough
// to open it. Opening those is what the instance itself answers.

///|
/// What a declared field carries.
pub(all) enum TyInfo {
  TyBool
  /// Every `s8`..`s32` / `u8`..`u32`. The width is a decode-time range check,
  /// which the generated codec has already applied by the time a value is here.
  TyInt
  TyFloat
  TyText
  TyList(TyInfo)
  TyTuple(Array[TyInfo])
  TyOption(TyInfo)
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
  TyOMap(TyInfo)
  /// A child-component slot; None when the schema said only `component`.
  TyComp(String?)
  /// Tabular data: typed columns of equal width (`tables.table`).
  ///
  /// The one named shape whose contents the schema DOES know. `TyRecord` keeps
  /// a name and nothing else because a record's fields are the instance's to
  /// answer; a table is standard, so the projection can describe it fully, a
  /// validator can check it, and an agent can be told how to write one. That
  /// is the whole reason it is a case here rather than `TyRecord("table")`.
  TyTable
  TyAny
} derive(Eq, Debug)

///|
/// How the author wrote it. The WIT spelling, because that is what is in the
/// file and what they will edit.
pub fn TyInfo::show_source(self : TyInfo) -> String {
  match self {
    TyBool => "Bool"
    TyInt => "Int"
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
    TyComp(Some(c)) => "Component[" + c + "]"
    TyComp(None) => "Component"
    TyTable => "Table"
    TyAny => "Any"
  }
}

///|
/// What this type CONTAINS, or None when it contains nothing.
///
/// Strict, and deliberately not the same question `@statedef.StateTy::elem`
/// answers. That one asks "may a view `@each` over this?", where `any` and a
/// child slot must both say yes — a dynamic value may turn out to be a list and
/// a component iterates its own entries, neither knowable at generation time.
/// Answering the two with one method put a meaningless `elem: any` on 117
/// fields of the corpus and showed it in the inspector, where the question is
/// the other one: what is in here?
pub fn TyInfo::elem(self : TyInfo) -> TyInfo? {
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
pub fn TyInfo::slot(self : TyInfo) -> String? {
  match self {
    TyComp(Some(c)) => Some(c)
    TyComp(None) => Some("")
    _ => None
  }
}

///|
/// A closed set's declared members. Empty for every other type, and for a set
/// with open membership — which is a real answer, not a missing one.
pub fn TyInfo::members(self : TyInfo) -> Array[String] {
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
pub fn TyInfo::kind(self : TyInfo) -> FieldKind {
  match self {
    TyBool => FBool
    TyInt => FInt
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
pub fn TyInfo::zero(self : TyInfo) -> Value {
  match self {
    TyBool => Bool(false)
    TyInt | TyFloat => Num(0.0)
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
    TyVariant(_) | TyOption(_) | TyComp(_) | TyAny => Null
  }
}
