// Spec for the state schema: the public data types plus `declare` stubs.
// Implementations live in names.mbt / markers.mbt / from_wit.mbt / emit.mbt.
//
// The pipeline is two pure stages:
//
//   WIT source text --parse_state--> Array[StateDef]   (from_wit.mbt)
//                   --emit_*-------> String            (emit.mbt)
//
// A StateDef is the whole data contract of one component: the fields its
// views may read, the messages its update may receive, and the named types
// those two mention.

///|
/// A state field's type, after the WIT subset gate.
///
/// This is deliberately NOT WIT's type lattice: it is tutuca's `FieldKind`
/// lattice with the element types WIT can carry. `TSet`, `TOMap`, `TComp`
/// and `TAny` have no structural WIT spelling and arrive as marker names
/// (markers.mbt); everything else is written in plain WIT.
pub(all) enum StateTy {
  TBool
  /// `s8`..`s32` / `u8`..`u32`. Width and signedness survive so decode can
  /// range-check even though every one of them emits a MoonBit `Int`.
  TInt(width~ : Int, signed~ : Bool)
  TFloat
  TText
  TList(StateTy)
  TTuple(Array[StateTy])
  TOption(StateTy)
  /// A named `record` declared alongside the state.
  TRecord(String)
  /// A named payload-free `enum`.
  TEnum(String)
  /// A named `variant` with payloads.
  TVariant(String)
  /// A named `flags` — a set with CLOSED membership.
  TFlags(String)
  /// The `text-set` marker — a set with OPEN membership.
  TSet
  /// The ordered-map marker. WIT `map` is unordered by definition, so this
  /// is a refinement WIT cannot spell rather than a substitute for it.
  TOMap(StateTy)
  /// A child-component slot; None for the untyped `component` marker.
  TComp(String?)
  /// The `any` marker — an arbitrary @tutuca.Value.
  TAny
} derive(Eq, @debug.Debug)

///|
/// One field of the state record.
pub(all) struct FieldDef {
  /// The name as written in WIT, kebab-case.
  wit_name : String
  /// The tutuca runtime field name (lowerCamel) — the name a view's
  /// `.field` read and the JSON encoding both use.
  name : String
  /// The MoonBit struct field name: `name`, escaped if it is a keyword.
  binding : String
  ty : StateTy
  doc : String?
} derive(Eq, @debug.Debug)

///|
/// One case of a message `variant` (a receive / bubble / response bucket).
pub(all) struct MsgDef {
  wit_name : String
  /// The dispatch name raised at runtime (lowerCamel).
  name : String
  /// The MoonBit enum variant name.
  variant : String
  payload : Array[StateTy]
  doc : String?
} derive(Eq, @debug.Debug)

///|
/// A `$`-callable the component answers, declared as a WIT `func`.
///
/// Views declare most methods just by calling them (`$label`), and the
/// generator reads them off the view. This is for the ones no view of THIS
/// component names: a method a PARENT calls on it — `contains-text` on a list
/// item, say, which the list's `@when` asks every child regardless of the
/// child's own shape. Undeclared, such a method is a string only MoonBit knows,
/// and the enum a handler match is written over cannot contain it.
pub(all) struct MethodDef {
  wit_name : String
  /// The runtime name a `$name` call and a `Value::field` read both use.
  name : String
  params : Array[StateTy]
  /// None for a `func` with no result — the value world has no Unit, so this
  /// is what tells `to_wit` to write the arrow back the way it found it.
  result : StateTy?
  doc : String?
} derive(Eq, @debug.Debug)

///|
/// A named type the state or its messages mention.
pub(all) enum UserTyKind {
  URecord(Array[FieldDef])
  UEnum(Array[(String, String)])
  UVariant(Array[MsgDef])
  UFlags(Array[(String, String)])
} derive(Eq, @debug.Debug)

///|
/// A named type declared in a component's interface, with its MoonBit name.
pub(all) struct UserTy {
  wit_name : String
  /// The generated MoonBit type name, component-prefixed (`CounterItem`).
  name : String
  kind : UserTyKind
  doc : String?
} derive(Eq, @debug.Debug)

///|
/// One component's whole data contract.
pub(all) struct StateDef {
  /// The interface name as written in WIT, kebab-case.
  wit_name : String
  /// The component name, as a MoonBit type prefix (`Counter`).
  component : String
  fields : Array[FieldDef]
  receive : Array[MsgDef]
  bubble : Array[MsgDef]
  response : Array[MsgDef]
  /// `func` declarations: the `$`-callables no view of this component names.
  methods : Array[MethodDef]
  types : Array[UserTy]
  doc : String?
} derive(Eq, @debug.Debug)

///|
/// Anything that makes a state block unusable. Rendered by `Show` into the
/// message the CLI reports.
///
/// Every out-of-subset WIT construct gets its OWN variant rather than a
/// generic "unsupported": the whole point of a subset is that the boundary
/// is explained where you hit it.
pub suberror DefError {
  /// The block is not valid WIT. `offset` indexes the block's own source.
  WitSyntax(msg~ : String, offset~ : Int)
  /// A `package` declaration inside the block (viewgen supplies it).
  UnexpectedPackage(String)
  /// A `world`, or a freestanding `func` — neither describes state.
  UnsupportedItem(iface~ : String, item~ : String, why~ : String)
  /// The interface declares no `record state`.
  NoStateRecord(String)
  /// `state` is declared, but not as a record.
  StateNotRecord(String)
  /// A type WIT accepts but component state cannot carry.
  UnsupportedType(where_~ : String, ty~ : String, why~ : String)
  /// A named type the block never declares and that is not a marker or a
  /// sibling component.
  UnknownTypeRef(where_~ : String, name~ : String)
  /// A named type that refers to itself with no `option`/`list` in between.
  CyclicType(String)
  /// Two names collapse onto one MoonBit identifier.
  Collision(kind~ : String, ident~ : String, first~ : String, second~ : String)
  /// Two interfaces claim the same component.
  DuplicateInterface(String)
  /// An interface name that cannot head a MoonBit type.
  BadInterfaceName(String)
  /// A marker name used as a user type name.
  ReservedName(String)
}

///|
/// The user-facing one-line message for a schema failure.
declare pub fn DefError::message(self : DefError) -> String

///|
/// The identifier to look for in the block when pointing at this error, or
/// None when it has no single locus.
///
/// mizchi/wit carries no per-declaration spans, so a semantic failure cannot
/// report a position of its own; naming the identifier lets the caller find
/// the line by scanning.
declare pub fn DefError::locus(self : DefError) -> String?

///|
/// Parse a `<script type="tutuca/state">` block into one StateDef per
/// interface it declares.
///
/// `source` is the block's text exactly as written, so a `WitSyntax` offset
/// indexes it directly. A `package` header is neither required nor allowed:
/// viewgen supplies one, because the package identity belongs to the module,
/// not to the block.
declare pub fn parse_state(source : String) -> Array[StateDef] raise DefError

///|
/// The field with this runtime name, or None.
declare pub fn StateDef::field(self : StateDef, name : String) -> FieldDef?

///|
/// The named type with this WIT name, or None.
declare pub fn StateDef::user_ty(self : StateDef, wit_name : String) -> UserTy?

///|
/// The element type an `@each` over this type binds, or None when the type
/// is not iterable — the check behind the `@each` diagnostic.
declare pub fn StateTy::elem(self : StateTy) -> StateTy?

///|
/// The type reached by reading `name` off `ty`, or None when `ty` has no
/// such field — the check behind the unknown-`.field` diagnostic.
declare pub fn StateDef::field_of(
  self : StateDef,
  ty : StateTy,
  name : String,
) -> StateTy?

///|
/// How to write this type in a diagnostic: the WIT spelling, because that is
/// what the author wrote and what they will edit.
declare pub fn StateTy::show_wit(self : StateTy) -> String

///|
/// The name in `names` closest to `name`, when one is close enough to be
/// worth suggesting — the "did you mean" behind a misspelt field read.
declare pub fn nearest(name : String, names : Array[String]) -> String?

///|
/// True when a field of this type lives in the state struct. A child-
/// component slot does not — the runtime makes it from the `specs~` entry.
declare pub fn StateTy::in_struct(self : StateTy) -> Bool

///|
/// True when a value of this type is a sensible thing to put in a boolean
/// position (`@show`, `@hide`, a predicate).
declare pub fn StateTy::is_boolish(self : StateTy) -> Bool

///|
/// True when `<x render>` can address a value of this type.
declare pub fn StateTy::is_renderable(self : StateTy) -> Bool

///|
/// The tutuca `FieldKind` this type maps to, as the MoonBit source text of a
/// `@component.FieldKind` expression.
///
/// Text and not a `@component.FieldKind` value: statedef stays a pure
/// text-in/text-out package like viewgen, and importing component/ here
/// would drag @tutuca.Value in for the sake of one enum.
declare pub fn StateTy::field_kind_src(self : StateTy) -> String

///|
/// The MoonBit type expression for a state field of this type, with named
/// types resolved through `def`.
declare pub fn StateDef::moonbit_ty(self : StateDef, ty : StateTy) -> String

///|
/// The MoonBit expression for this type's zero value.
declare pub fn StateDef::zero_expr(self : StateDef, ty : StateTy) -> String

///|
/// The schema back out as a self-contained WIT document, with every marker
/// LOWERED to its structural form — external tooling cannot know tutuca's
/// readings of `any`, `text-set` or a component slot.
declare pub fn to_wit(defs : Array[StateDef], pkg? : String) -> String

///|
/// Parse and validate a `<script type="tutuca/init">` block against a
/// component's schema. WIT declares no defaults, so named initial states get
/// a block of their own rather than a comment convention in the schema.
declare pub fn parse_init(
  source : String,
  def : StateDef,
) -> Array[InitState] raise InitError

///|
/// The one-line message the CLI reports for a bad init block.
declare pub fn InitError::message(self : InitError) -> String

///|
/// A dyncomp guest's state struct and its four shape-derived accessors:
/// `get_field`, `with_field`, `to_json` and `seq_entries`.
///
/// Not `handle` or `call_method` — those are behaviour, which is what a
/// guest is for. The schema owns the shape; the author owns the conduct.
declare pub fn to_guest(
  def : StateDef,
  trait_name? : String,
  values? : String,
) -> String

///|
/// A stable structural fingerprint of the schema: over shape, not over
/// source text, so reindenting the block does not change it but renaming a
/// field does. What notices that a stored state can no longer be read back.
declare pub fn fingerprint(defs : Array[StateDef]) -> String
