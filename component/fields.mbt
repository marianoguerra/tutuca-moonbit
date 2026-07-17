// Field specs (the field half of src/oo.js classFromData).

///|
pub fn FieldSpec::of_default(v : @tutuca.Value) -> FieldSpec {
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
  args? : Map[String, @tutuca.Value] = {},
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
pub fn FieldSpec::omap(default? : Map[String, @tutuca.Value] = {}) -> FieldSpec {
  { kind: FOMap, default: Map(default) }
}

///|
/// Build a Map-backed set from member values: key = member display string,
/// value = Bool(true). Duplicate members collapse (set semantics).
fn set_value(members : Array[@tutuca.Value]) -> @tutuca.Value {
  let m : Map[String, @tutuca.Value] = {}
  for v in members {
    m[v.to_display_string()] = Bool(true)
  }
  Map(m)
}

///|
pub fn FieldSpec::coerce_or_default(
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
