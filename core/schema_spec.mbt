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
/// What a field carries at runtime. DECLARED, never inferred: reading the kind
/// off a seed value is what used to make `FInt` vs `FFloat` depend on whether
/// a double happened to be integral.
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
  inputs : Array[String]
  receives : Array[String]
  /// The ROUTED names this component answers. v2's, and the one `bubbles` and
  /// `responses` fold into — both go in the contract step.
  intents : Array[String]
  bubbles : Array[String]
  responses : Array[String]
  /// `$name` callables in VALUE positions.
  methods : Array[String]
  /// Constant element ids — the selectors a test addresses.
  ids : Array[String]
  view_names : Array[String]
  /// Named fixtures from the `tutuca/init` block.
  init_names : Array[String]
}

///|
/// One declared field: its name and its type.
///
/// There is nothing to default any more. The five optional parts this used to
/// take were all recoverable from the type, and letting a caller state them
/// separately meant letting a caller state them WRONG — a descriptor reading
/// `("rows", "value-omap", FMap)` named an ordered map and then gave it a plain
/// map's kind, and nothing could notice.
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
/// component raises no `bubble`, not that nobody looked.
///
/// `name` defaults to empty because a hand-written descriptor is already being
/// passed to a `component(name~ = ...)` that knows it; the component layer
/// stamps it in. The generator writes it out, since it also knows it.
declare pub fn SchemaInfo::new(
  name? : String,
  fingerprint~ : String,
  fields? : Array[FieldInfo],
  inputs? : Array[String],
  receives? : Array[String],
  intents? : Array[String],
  bubbles? : Array[String],
  responses? : Array[String],
  methods? : Array[String],
  ids? : Array[String],
  view_names? : Array[String],
  init_names? : Array[String],
) -> SchemaInfo

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
