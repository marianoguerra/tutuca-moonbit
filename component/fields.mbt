// Field specs (the field half of src/oo.js classFromData).
//
// There is no `FieldSpec::of_default` any more. It read a field's KIND off the
// seed value — which is why `FInt` vs `FFloat` used to depend on whether a
// double happened to be integral — and it existed because a component might
// arrive without a schema to state the kind instead. None does.

///|
fn FieldSpec::comp(
  name : String,
  args? : Map[String, @tutuca.Value] = Map([]),
) -> FieldSpec {
  { kind: FComp(comp=name, args~), default: Null }
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

// `FieldInfo::new` / `SchemaInfo::new` / `SchemaInfo::field` moved to
// `@tutuca` (core/schema.mbt) along with the types they build, so that code
// holding only a `Value` can read a component's declared description. They are
// re-exported from spec.mbt and callers are unchanged.
