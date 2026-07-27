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
pub(all) struct FieldInfo {
  name : String
  /// The WIT spelling verbatim — `list<card>`, `option<string>`, `text-set`.
  /// Carried rather than reconstructed, so an inspector shows what is in the
  /// file.
  ty : String
  kind : FieldKind
  /// A collection's element type, so a viewer can descend rather than stop
  /// at "list". None for a scalar.
  elem : String?
  /// The component a child slot holds; None for a data field.
  slot : String?
  /// A `flags` field's declared members — the one thing about a set that only
  /// the schema knows, since the encoded value is just a Map. Empty for every
  /// other field, and for a set with open membership.
  members : Array[String]
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
/// One declared field, with the parts most fields do not use defaulted.
///
/// The generator writes every part out because it knows every part. A
/// hand-written schema — a dyncomp guest's manifest, the storybook shell's
/// computed field set, a test fixture — usually has a name, a WIT spelling and
/// a kind, and `elem`/`slot`/`members` are the shapes it does not have. Making
/// those defaults is a shorthand for writing them empty, not a way to leave
/// them unsaid: the struct is still `pub(all)` and a caller that knows more
/// still writes it whole.
declare pub fn FieldInfo::new(
  name : String,
  ty : String,
  kind : FieldKind,
  elem? : String,
  slot? : String,
  members? : Array[String],
) -> FieldInfo

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
  bubbles? : Array[String],
  responses? : Array[String],
  methods? : Array[String],
  ids? : Array[String],
  view_names? : Array[String],
  init_names? : Array[String],
) -> SchemaInfo

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
