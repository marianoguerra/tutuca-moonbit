// Spec for the state schema: the public data types plus `declare` stubs.
// Implementations live in names.mbt / lex.mbt / parse.mbt / types.mbt.
//
// The pipeline is two pure stages:
//
//   block text --parse_state--> Array[StateDef]   (lex.mbt + parse.mbt)
//              --emit_*-------> String            (types.mbt)
//
// A StateDef is the whole data contract of one component: the fields its
// views may read, the messages its update may receive, and the named types
// those two mention.
//
// The surface is tutuca's own: `state`, `struct`, `enum`, and the three
// message buckets, with MoonBit-shaped type spellings and source spans on
// every diagnostic.

///|
/// A state field's type after parsing and name resolution.
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
  /// A named sum with at least one payload-bearing case.
  TVariant(String)
  /// A set whose membership is closed by a named enum.
  TFlags(String)
  /// A string set with open membership.
  TSet
  /// A string-keyed ordered map.
  TOMap(StateTy)
  /// A child-component slot; None for an untyped `Component`.
  TComp(String?)
  /// A child slot constrained by one or more canonical protocol ids.
  ///
  /// This is deliberately distinct from `TComp`: a component name is a
  /// construction hint, while protocols are capabilities checked when an
  /// instance is installed in the slot.
  TCompProtocols(Array[String])
  /// An arbitrary `@tutuca.Value`.
  TAny
} derive(Eq, @debug.Debug)

///|
/// A value written in an attribute: `#[min = 0]`, `#[format = "email"]`,
/// `#[required]`.
pub(all) enum AttrValue {
  ANum(Double)
  AStr(String)
  /// An attribute written with no value, which is its own assertion.
  AFlag
} derive(Eq, @debug.Debug)

///|
/// One field of the state record.
pub(all) struct FieldDef {
  /// The one name used by the state block, views, messages, and JSON.
  name : String
  /// The MoonBit struct field name: `name`, escaped if it is a keyword.
  binding : String
  ty : StateTy
  doc : String?
  /// `#[…]` attributes, in source order, unresolved.
  ///
  /// Unresolved on purpose: `statedef` knows a field carries `min = 0` and
  /// has no opinion about what a minimum MEANS. `dyncomp/jsonschema` does,
  /// and a parser that validated them would be the second place that decides
  /// which bounds exist.
  attrs : Array[(String, AttrValue)]
} derive(Eq, @debug.Debug)

///|
/// One case of a receive or intent bucket.
pub(all) struct MsgDef {
  /// The case name exactly as the author wrote it.
  source_name : String
  /// The dispatch name raised at runtime (lowerCamel).
  name : String
  /// The MoonBit enum variant name.
  variant : String
  payload : Array[StateTy]
  doc : String?
} derive(Eq, @debug.Debug)

///|
/// A protocol name in source and the canonical string id it resolves to.
/// Aliases are lexical conveniences only; ids are what metadata and runtime
/// checks carry, so separately loaded modules agree without sharing a path.
pub(all) struct ProtocolRef {
  local_name : String
  id : String
  span : Span
} derive(Eq, @debug.Debug)

///|
/// A typed readable observation. It promises an operation, not storage: an
/// implementation may bind it to a field or to a zero-argument computation.
pub(all) struct PropertyDef {
  name : String
  ty : StateTy
  doc : String?
} derive(Eq, @debug.Debug)

///|
/// A protocol's full capability surface.
pub(all) struct ProtocolDef {
  local_name : String
  id : String
  handle_message : Array[MsgDef]
  handle_intent : Array[MsgDef]
  express_message : Array[MsgDef]
  express_intent : Array[MsgDef]
  properties : Array[PropertyDef]
  views : Array[String]
  provides : Array[PropertyDef]
  lookups : Array[PropertyDef]
  doc : String?
  span : Span
} derive(Eq, @debug.Debug)

///|
/// An explicit implementation binding. `source` is `.field`, `$compute`, or
/// a local view name depending on the section that owns it.
pub(all) struct ProtocolBinding {
  protocol_id : String
  member_name : String
  source : String
  span : Span
} derive(Eq, @debug.Debug)

///|
/// A named type the state or its messages mention.
///
/// The state language has one sum declaration. Payload-free sums become
/// `UEnum`; a payload on any case makes the declaration a `UVariant`.
pub(all) enum UserTyKind {
  URecord(Array[FieldDef])
  /// Every case payload-free, so it encodes as its case name.
  UEnum(Array[(String, String)])
  /// At least one case carries a payload.
  UVariant(Array[MsgDef])
} derive(Eq, @debug.Debug)

///|
/// A named type declared beside a component's state, with its MoonBit name.
pub(all) struct UserTy {
  /// The type name exactly as the author wrote it.
  source_name : String
  /// The generated MoonBit type name, component-prefixed (`CounterItem`).
  name : String
  kind : UserTyKind
  doc : String?
} derive(Eq, @debug.Debug)

///|
/// One component's whole data contract.
pub(all) struct StateDef {
  /// The state declaration's name exactly as the author wrote it.
  source_name : String
  /// The component name, as a MoonBit type prefix (`Counter`).
  component : String
  fields : Array[FieldDef]
  /// Every MESSAGE the component accepts beyond the ones its own views send:
  /// what a parent sends it, what the host sends it, and every answer it reads.
  receive : Array[MsgDef]
  /// Every INTENT it answers — a routed dispatch, offered to each hop of a
  /// route until something replies. An answer to one comes back as an ordinary
  /// message, so it is declared in `receive` rather than here.
  intent : Array[MsgDef]
  /// Outbound capabilities declared by this component's implicit protocol.
  express_message : Array[MsgDef]
  express_intent : Array[MsgDef]
  /// Canonical ids this component claims to implement.
  implements : Array[String]
  /// Protocol declarations and imports visible in this state block. A batch
  /// compiler reconciles declarations with the same id across files.
  protocols : Array[ProtocolDef]
  protocol_imports : Array[ProtocolRef]
  property_bindings : Array[ProtocolBinding]
  view_bindings : Array[ProtocolBinding]
  provide_bindings : Array[ProtocolBinding]
  lookup_bindings : Array[ProtocolBinding]
  types : Array[UserTy]
  /// What this component PUBLISHES to its subtree, in declaration order.
  ///
  /// Wiring rather than schema, and in the schema block anyway, because a card
  /// has no other place to say it: the manifest a host reads is a projection
  /// of this file rather than a second thing to author.
  provide : Array[ProvideDecl]
  /// What it asks its ancestors for. A lookup names what it WANTS, not who
  /// supplies it.
  lookup : Array[LookupDecl]
  doc : String?
} derive(Eq, @debug.Debug)

///|
/// One `provide` entry: a name, and the source text that produces it.
///
/// `source` is the value language and is NOT read here — a lowercase name
/// takes an addressable path (`.field`, `.seq[.key]`), and an uppercase one
/// publishes a component type, where `self` is the only thing it can be.
/// Which is which, and whether the text parses, is the component layer's
/// question; this records what was written and where.
pub(all) struct ProvideDecl {
  name : String
  source : String
  span : Span
} derive(Eq, @debug.Debug)

///|
/// One `lookup` entry: a name, and the fallback expression to use when nothing
/// above provides it. There is no alias — the local name IS the provided name.
pub(all) struct LookupDecl {
  name : String
  default : String?
  span : Span
} derive(Eq, @debug.Debug)

///|
/// Anything that makes a state block unusable. Rendered by `Show` into the
/// message the CLI reports.
///
/// Each invalid construct has its own variant so the boundary is explained
/// where the author hits it.
pub suberror DefError {
  /// The block does not parse. `span` is where in it, so a caller can point at
  /// a column in the state block.
  Syntax(msg~ : String, span~ : Span)
  /// A declaration kind that does not exist.
  UnknownDecl(got~ : String, span~ : Span)
  /// Two `state` declarations claim the same component.
  DuplicateComponent(name~ : String, span~ : Span)
  /// A file mixes bare `state { … }` with named `state Counter { … }`, so a
  /// bare one could mean either the file's single component or a nameless one.
  MixedStateNames(span~ : Span)
  /// The block declares types or messages and no `state` at all.
  NoState(span~ : Span)
  /// A type the state cannot carry, with the reason it cannot.
  UnsupportedType(ty~ : String, why~ : String, span~ : Span)
  /// A named type the block never declares, and that is not a builtin or a
  /// sibling component.
  UnknownTypeRef(name~ : String, span~ : Span)
  /// A type application whose argument count is wrong: `Array[A, B]`.
  BadTypeArgs(name~ : String, want~ : Int, got~ : Int, span~ : Span)
  /// A named type that refers to itself with no `?` or `Array` in between.
  CyclicType(name~ : String, span~ : Span)
  /// Two names collapse onto one MoonBit identifier.
  Collision(
    kind~ : String,
    ident~ : String,
    first~ : String,
    second~ : String,
    span~ : Span
  )
  /// A component name that cannot head a MoonBit type.
  BadComponentName(name~ : String, span~ : Span)
  /// A builtin type name used as a user type name.
  ReservedName(name~ : String, span~ : Span)
  /// A protocol alias used by an implementation or component constraint was
  /// not declared or imported in this source unit.
  UnknownProtocol(local_name~ : String, span~ : Span)
  /// Two declarations in one source unit claim the same canonical id with
  /// incompatible surfaces.
  ProtocolConflict(id~ : String, span~ : Span)
}

///|
/// The user-facing one-line message for a schema failure.
declare pub fn DefError::message(self : DefError) -> String

///|
/// Where in the block the failure is.
///
/// Every declaration carries its range, so state and script diagnostics point
/// into their source blocks the same way.
declare pub fn DefError::span(self : DefError) -> Span

///|
/// Parse a `<script type="tutuca/state">` block into one StateDef per
/// component it declares.
///
/// `source` is the block's text exactly as written, so every span indexes it
/// directly.
///
/// A file's components are named the way its templates are: bare
/// `state { … }` is the file's single component, and `state Counter { … }`
/// names one. Mixing the two is refused for the same reason mixing template
/// ids is — a bare one would be ambiguous.
///
/// `name` is what a bare `state` is called, and it matters beyond a label: the
/// component name prefixes every generated type, so without it a bare block
/// would emit `Sample` beside `LoaderBarState`.
declare pub fn parse_state(
  source : String,
  name? : String,
) -> Array[StateDef] raise DefError

///|
/// Whether every protocol assumption in a compilation batch was proved.
pub(all) enum ValidationMode {
  Strict
  Gradual
} derive(Eq, @debug.Debug)

///|
/// A static protocol finding. `code` is the same enum runtime notices carry.
pub(all) struct ProtocolDiagnostic {
  code : @tutuca.ProtocolIssueCode
  component : String
  protocol_id : String
  member_name : String
  message : String
  error : Bool
  span : Span
} derive(Eq, @debug.Debug)

///|
pub(all) struct ProtocolValidation {
  mode : ValidationMode
  diagnostics : Array[ProtocolDiagnostic]
} derive(Eq, @debug.Debug)

///|
/// Validate every protocol declaration and implementation visible in a batch.
/// Missing dynamic definitions produce gradual warnings; contradictions in
/// definitions or known implementations are errors.
declare pub fn validate_protocols(defs : Array[StateDef]) -> ProtocolValidation

///|
/// The component this schema describes: its own name, or the caller's
/// fallback for a file whose single component is unnamed.
///
/// The identical rule `@viewfile.ViewSet::component_name` follows, and
/// deliberately so — a bare `state { … }` and a bare `<template>` are the same
/// claim about the same file.
declare pub fn StateDef::component_name(
  self : StateDef,
  fallback : String,
) -> String

///|
/// The field with this runtime name, or None.
declare pub fn StateDef::field(self : StateDef, name : String) -> FieldDef?

///|
/// The named type with this source name, or None.
declare pub fn StateDef::user_ty(
  self : StateDef,
  source_name : String,
) -> UserTy?

///|
/// Resolve an implicit (`save`) or protocol-qualified (`Store::save`) source
/// operation to its collision-free wire name. Raw quoted names bypass this.
declare pub fn StateDef::operation_name(
  self : StateDef,
  source_name : String,
) -> String?

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
/// How to write this type in a diagnostic, using the state-language spelling
/// the author wrote and will edit.
declare pub fn StateTy::show_source(self : StateTy) -> String

///|
/// The name in `names` closest to `name`, when one is close enough to be
/// worth suggesting — the "did you mean" behind a misspelt field read.
declare pub fn nearest(name : String, names : Array[String]) -> String?

///|
/// True when a field of this type lives in the state struct. A child-
/// component slot does not — the runtime makes it from the `specs~` entry.
declare pub fn StateTy::in_struct(self : StateTy) -> Bool

///|
/// True when a value of this type can decide anything in a boolean position
/// (`@show`, `@hide`, a predicate). False only for the container kinds, which
/// `Value::is_truthy` answers `true` for unconditionally — a test over one of
/// those cannot fail.
declare pub fn StateTy::is_boolish(self : StateTy) -> Bool

///|
/// True when `<x render>` can address a value of this type.
declare pub fn StateTy::is_renderable(self : StateTy) -> Bool

///|
/// The component this type names, unwrapping an `option` the same way
/// `is_renderable` does. None for the untyped `component` marker and for
/// everything that is not a slot.
declare pub fn StateTy::component_named(self : StateTy) -> String?

///|
/// The MoonBit source of the `@tutuca.TyInfo` expression describing this type.
///
/// Text and not a `TyInfo` value: statedef stays a pure text-in/text-out
/// package like viewgen, and importing core here would drag `@tutuca.Value`
/// in for the sake of one enum. Takes the `StateDef` because a closed set's
/// members are inlined, and only the declaration knows them.
declare pub fn StateDef::ty_info_src(self : StateDef, ty : StateTy) -> String

///|
/// The MoonBit type expression for a state field of this type, with named
/// types resolved through `def`.
declare pub fn StateDef::moonbit_ty(self : StateDef, ty : StateTy) -> String

///|
/// The MoonBit expression for this type's zero value.
declare pub fn StateDef::zero_expr(self : StateDef, ty : StateTy) -> String

///|
/// Parse and validate a `<script type="tutuca/init">` block against a
/// component's schema. Named initial states live in a block of their own so
/// the state declaration remains a type rather than a default-value format.
declare pub fn parse_init(
  source : String,
  def : StateDef,
) -> Array[InitState] raise InitError

///|
/// The one-line message the CLI reports for a bad init block.
declare pub fn InitError::message(self : InitError) -> String

///|
/// A stable structural fingerprint of the schema: over shape, not over
/// source text, so reindenting the block does not change it but renaming a
/// field does. What notices that a stored state can no longer be read back.
declare pub fn fingerprint(defs : Array[StateDef]) -> String
