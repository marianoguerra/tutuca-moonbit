// Field specs (the field half of src/oo.js classFromData).

///|
fn FieldSpec::of_default(v : @tutuca.Value) -> FieldSpec {
  let kind : FieldKind = match v {
    Bool(_) => FBool
    Str(_) => FText
    Num(n) => if n.to_int().to_double() == n { FInt } else { FFloat }
    List(_) => FList
    Map(_) => FMap
    _ => FAny
  }
  { kind, default: v }
}

///|
pub fn FieldSpec::comp(
  name : String,
  args? : Map[String, @tutuca.Value] = Map([]),
) -> FieldSpec {
  { kind: FComp(comp=name, args~), default: Null }
}

///|
/// A Map-backed set field (JS FieldSet). Default is the set of `members`
/// (keyed by member, value Bool(true) — the ps_set_of shape). Coercion turns
/// a List into a set and dedups; a Map is kept as-is.
pub fn FieldSpec::set(members? : Array[String] = []) -> FieldSpec {
  { kind: FSet, default: set_value(members.map(m => Str(m))) }
}

///|
/// An ordered-map field (JS FieldOMap), backed by @tutuca.Value::Map.
pub fn FieldSpec::omap(
  default? : Map[String, @tutuca.Value] = Map([]),
) -> FieldSpec {
  { kind: FOMap, default: Map(default) }
}

///|
/// Build a Map-backed set from member values: key = member display string,
/// value = Bool(true). Duplicate members collapse (set semantics).
fn set_value(members : Array[@tutuca.Value]) -> @tutuca.Value {
  let m : Map[String, @tutuca.Value] = Map([])
  for v in members {
    m[v.to_display_string()] = Bool(true)
  }
  Map(m)
}

///|
fn FieldSpec::coerce_or_default(
  self : FieldSpec,
  v : @tutuca.Value,
) -> @tutuca.Value {
  match (self.kind, v) {
    (FBool, Bool(_))
    | (FText, Str(_))
    | (FInt, Num(_))
    | (FFloat, Num(_))
    | (FList, List(_))
    | (FMap, Map(_))
    | (FComp(..), Obj(_)) => v
    (FAny, _) => v
    // A set/omap already in Map shape passes through; a List coerces into a
    // Map-backed set (JS isetCoercer: array -> ISet). Anything else -> default.
    (FSet, Map(_)) | (FOMap, Map(_)) => v
    (FSet, List(items)) => set_value(items)
    _ => self.default
  }
}

///|
/// The declared description of a field, by runtime name.
pub fn SchemaInfo::field(self : SchemaInfo, name : String) -> FieldInfo? {
  for f in self.fields {
    if f.name == name {
      return Some(f)
    }
  }
  None
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
pub fn FieldInfo::new(
  name : String,
  ty : String,
  kind : FieldKind,
  elem? : String,
  slot? : String,
  members? : Array[String] = [],
) -> FieldInfo {
  { name, ty, kind, elem, slot, members }
}

///|
/// A component's declared schema, with the channels it does not use defaulted
/// to empty.
///
/// Empty is a real answer here, and a different one from absent: it says the
/// component raises no `bubble`, not that nobody looked. `component()` and
/// `Component::for_type` both require a schema for that reason — what this
/// removes is the eight lines of `[]` between the two or three lists a
/// hand-written descriptor actually fills.
pub fn SchemaInfo::new(
  fingerprint~ : String,
  fields? : Array[FieldInfo] = [],
  inputs? : Array[String] = [],
  receives? : Array[String] = [],
  bubbles? : Array[String] = [],
  responses? : Array[String] = [],
  methods? : Array[String] = [],
  ids? : Array[String] = [],
  view_names? : Array[String] = [],
  init_names? : Array[String] = [],
) -> SchemaInfo {
  {
    fingerprint,
    fields,
    inputs,
    receives,
    bubbles,
    responses,
    methods,
    ids,
    view_names,
    init_names,
  }
}
