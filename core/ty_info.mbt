// A declared field's TYPE, as data the runtime can walk.
//
// This is the schema's type lattice projected into the value world. It used to
// arrive here flattened into four independent parts of `FieldInfo` — a `ty`
// string holding the WIT spelling, a `kind` from a parallel ten-case enum, an
// `elem` string, a `slot` string and a `members` list — which had two costs.
//
// A caller could not DESCEND. An inspector holding `ty = "list<card>"` and
// `elem = "card"` has two strings and no way to ask what a `card` is, so it
// stops at the first level. And nothing tied the parts together: a hand-written
// descriptor picked the spelling and the kind separately, so `("rows",
// "value-omap", FMap)` was accepted while the kind an ordered map actually has
// is `FOMap`. Here the spelling and the kind are both FUNCTIONS of the type, so
// they cannot disagree.
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
  TyAny
} derive(Eq, Debug)

///|
/// How the author wrote it. The WIT spelling, because that is what is in the
/// file and what they will edit.
pub fn TyInfo::show_wit(self : TyInfo) -> String {
  match self {
    TyBool => "bool"
    TyInt => "s32"
    TyFloat => "f64"
    TyText => "string"
    TyList(e) => "list<" + e.show_wit() + ">"
    TyTuple(ts) => "tuple<" + ts.map(t => t.show_wit()).join(", ") + ">"
    TyOption(e) => "option<" + e.show_wit() + ">"
    TyRecord(n) | TyEnum(n) | TyVariant(n) | TyFlags(n, _) => n
    TySet => "text-set"
    TyOMap(v) => "an ordered map of " + v.show_wit()
    TyComp(Some(c)) => "the " + c + " component"
    TyComp(None) => "component"
    TyAny => "any"
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
/// A projection rather than a stored field, which is the point — the kind used
/// to be written beside the spelling and could contradict it.
pub fn TyInfo::kind(self : TyInfo) -> FieldKind {
  match self {
    TyBool => FBool
    TyInt => FInt
    TyFloat => FFloat
    // An enum is payload-free, so it travels as its case name.
    TyText | TyEnum(_) => FText
    TyList(_) | TyTuple(_) => FList
    TyRecord(_) => FMap
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
