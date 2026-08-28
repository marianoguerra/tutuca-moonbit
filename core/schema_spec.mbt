// Spec for the declared-description layer: what a component STATES about
// itself, as data a holder of a bare `Value` can read.
//
// These types lived in the component package, which put them out of reach of
// everything that only has a `Value` — the inspector needed a `Components`
// registry to name an instance's own fields, `Value::to_json` had nothing to
// walk, and a dyncomp guest was described as `fields: []`. They mention only
// `Value`, so living here costs nothing and is what lets `Obj::obj_schema`
// exist at all. The component package re-exports them (`pub using`) so
// `@component.SchemaInfo` keeps resolving.
//
// READONLY by convention: types + `declare` stubs; implementations in
// schema.mbt.

///|
/// What a field carries at runtime. DECLARED, never inferred.
///
/// `FComp` fields hold a child component instance created through the
/// registration scope; `FSet`/`FOMap` are the Map-backed set / ordered-map
/// refinements.
pub(all) enum FieldKind {
  FBool
  FText
  FInt
  FFloat
  FList
  FMap
  FAny
  FComp(comp~ : String, args~ : Map[String, Value])
  FSet
  FOMap
} derive(Debug)

///|
/// One declared field of a component's state.
///
/// Two parts, where there were six. The WIT spelling, the runtime kind, a
/// collection's element type, a slot's component and a closed set's members are
/// all FUNCTIONS of the type (`ty_info.mbt`), so they are asked rather than
/// stored — which is what stops them from contradicting each other, and what
/// lets a reader descend into `list<card>` instead of receiving the string
/// `"card"` and having nowhere to take it.
pub(all) struct FieldInfo {
  name : String
  ty : TyInfo
}

///|
/// Runtime projection of a protocol surface. All names are wire names and the
/// id is canonical; source aliases never cross this boundary.
pub(all) struct ProtocolInfo {
  id : String
  handle_messages : Array[String]
  handle_intents : Array[String]
  express_messages : Array[String]
  express_intents : Array[String]
  properties : Array[(String, TyInfo)]
  views : Array[String]
  provides : Array[(String, TyInfo)]
  lookups : Array[(String, TyInfo)]
} derive(Eq, Debug)

///|
/// A component's explicit provider for one protocol operation.
pub(all) struct ProtocolBindingInfo {
  protocol_id : String
  member_name : String
  source : String
} derive(Eq, Debug)

///|
/// The result of checking one runtime schema against a protocol assumption.
pub(all) enum ProtocolConformance {
  Verified
  Deferred(Array[String])
  Invalid(Array[String])
} derive(Eq, Debug)

///|
/// What a component declares, as static metadata.
///
/// `inputs` is the one that matters most: the names `update` answers are
/// UNKNOWABLE at runtime (it is one opaque pattern match), so introspection
/// could only ever report THAT an update exists. The generator knows them.
pub(all) struct SchemaInfo {
  /// The component's declared name. Here rather than only on `Component`
  /// because the schema-derived `obj_debug` and the JSON projection label
  /// themselves with it, and those run off a `Value` with no registry in hand.
  /// Empty means "not stated here" — `component()` stamps its own `name~` in
  /// when it builds the Component, so an instance always has one.
  name : String
  /// Structural identity of the schema — over shape, not source text.
  fingerprint : String
  fields : Array[FieldInfo]
  /// The `@on` handler names the views raise.
  ///
  /// Distinct from `receives` — which is what the SCHEMA declares — because the
  /// two have different sources, not different destinations: both are addressed
  /// messages and both land in the `Receive` bucket. A component whose views
  /// arrive at runtime has no generator to state these, so the component layer
  /// recovers them from the compiled views instead.
  view_handlers : Array[String]
  receives : Array[String]
  /// The ROUTED names this component answers.
  intents : Array[String]
  express_messages : Array[String]
  express_intents : Array[String]
  /// `$name` callables in VALUE positions.
  methods : Array[String]
  /// The rules this component KEEPS: the `invariant` names its spec block
  /// declares, sorted.
  ///
  /// Names and not bodies, because the body is already here — an invariant is a
  /// `pred` with a role, so it is one of the `methods` above and the component
  /// layer calls it the way a view does. What this list adds is the ROLE, which
  /// nothing else records: that the runtime should ask it after every dispatch,
  /// including the ones no view raised and no handler mentions.
  ///
  /// Sorted, because WHICH rule broke is part of the answer and a report that
  /// depended on declaration order would move when an unrelated rule was added
  /// above it.
  invariants : Array[String]
  /// The DOMAINS this component's fields are declared over: the `where`
  /// clauses of its spec block, as data.
  ///
  /// Beside `invariants` rather than on `FieldInfo`, and for two reasons that
  /// point the same way. `FieldInfo`'s own doc says its parts are FUNCTIONS of
  /// the type, and a domain is not one — `0 <= i < len(items)` mentions a
  /// second field, which no type can. And several clauses may name one field,
  /// so what is carried is a list of pairs rather than an attribute of each
  /// field.
  ///
  /// Source order, not sorted: `broken_domains` sorts what it REPORTS, and the
  /// order here is the one a generator walks to decide what depends on what.
  domains : Array[FieldDomain]
  /// Constant element ids — the selectors a test addresses.
  ids : Array[String]
  view_names : Array[String]
  /// Named fixtures from the `tutuca/init` block.
  init_names : Array[String]
  protocols : Array[ProtocolInfo]
  implements : Array[String]
  property_bindings : Array[ProtocolBindingInfo]
  view_bindings : Array[ProtocolBindingInfo]
  provide_bindings : Array[ProtocolBindingInfo]
  lookup_bindings : Array[ProtocolBindingInfo]
}

///|
/// One declared field: its name and its type.
declare pub fn FieldInfo::new(name : String, ty : TyInfo) -> FieldInfo

///|
/// The runtime kind this field carries — a projection of its type, never a
/// second statement about it.
declare pub fn FieldInfo::kind(self : FieldInfo) -> FieldKind

///|
/// The empty value this field starts at — its type's zero.
declare pub fn FieldInfo::default(self : FieldInfo) -> Value

///|
/// The name of a field's generated mutator: `mutator_name("set", "count")` is
/// `"setCount"`. One home for a convention two unrelated places must agree on.
declare pub fn mutator_name(verb : String, field : String) -> String

///|
/// A component's declared schema, with the channels it does not use defaulted
/// to empty.
///
/// Empty is a real answer here, and a different one from absent: it says the
/// component answers no intent, not that nobody looked.
///
/// `name` defaults to empty because a hand-written descriptor is already being
/// passed to a `component(name~ = ...)` that knows it; the component layer
/// stamps it in. The generator writes it out, since it also knows it.
declare pub fn SchemaInfo::new(
  name? : String,
  fingerprint~ : String,
  fields? : Array[FieldInfo],
  view_handlers? : Array[String],
  receives? : Array[String],
  intents? : Array[String],
  express_messages? : Array[String],
  express_intents? : Array[String],
  methods? : Array[String],
  invariants? : Array[String],
  domains? : Array[FieldDomain],
  ids? : Array[String],
  view_names? : Array[String],
  init_names? : Array[String],
  protocols? : Array[ProtocolInfo],
  implements? : Array[String],
  property_bindings? : Array[ProtocolBindingInfo],
  view_bindings? : Array[ProtocolBindingInfo],
  provide_bindings? : Array[ProtocolBindingInfo],
  lookup_bindings? : Array[ProtocolBindingInfo],
) -> SchemaInfo

///|
/// Check an instance schema against a known protocol surface.
declare pub fn SchemaInfo::conforms(
  self : SchemaInfo,
  protocol : ProtocolInfo,
) -> ProtocolConformance

///|
/// A structural fingerprint of a schema built at RUNTIME, for a holder with no
/// generated one to carry (the dynamic-component host). See the implementation
/// for how it relates to `@statedef.fingerprint`.
declare pub fn SchemaInfo::shape_fingerprint(self : SchemaInfo) -> String

///|
/// The declared description of a field, by runtime name.
declare pub fn SchemaInfo::field(self : SchemaInfo, name : String) -> FieldInfo?

///|
/// Every declared field name, in declaration order.
declare pub fn SchemaInfo::field_names(self : SchemaInfo) -> Array[String]

///|
/// What a typed state struct states about itself: its declared schema and its
/// conversion to and from the fields map the render and path layers read.
///
/// A generic BOUND, not a trait object — `schema` and `decode` are facts about
/// the TYPE, and `Value::Obj` already carries the object-safe half of the
/// protocol (`Obj`). Nothing ever needs a `&Fields`.
///
/// Three methods, all of them things only the author (or the generator reading
/// the author's WIT) knows. There is no fourth: every dynamic operation OVER
/// the result — typed reads, defaults, sizes, item lookup, method calls, field
/// enumeration — is a free function in this package, written once rather than
/// implemented per type.
pub(open) trait Fields {
  fn schema() -> SchemaInfo
  fn encode(Self) -> Map[String, Value]
  fn decode(Map[String, Value]) -> Self?
}
