// Field specs.

///|
fn FieldSpec::comp(
  name : String,
  args? : Map[String, @tutuca.Value] = Map([]),
  protocol_ids? : Array[String] = [],
  protocols? : Array[@tutuca.ProtocolInfo] = [],
) -> FieldSpec {
  { kind: FComp(comp=name, args~), default: Null, protocol_ids, protocols }
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
    | (FComp(..), Obj(_)) => {
      if self.protocol_ids.is_empty() {
        return v
      }
      guard v.schema() is Some(schema) else {
        self.report_protocol_target(v, "component exposes no runtime schema")
        return self.default
      }
      for id in self.protocol_ids {
        if !schema.implements.contains(id) {
          self.report_protocol_target(v, "component does not implement `\{id}`")
          return self.default
        }
        match self.protocol(id) {
          Some(p) =>
            if schema.conforms(p) is Invalid(missing) {
              self.report_protocol_target(v, missing.join(", "))
              return self.default
            }
          None => () // declaration was dynamically loaded; the id claim is checkable
        }
      }
      v
    }
    (FAny, _) => v
    // A set/omap already in Map shape passes through; a List coerces into a
    // Map-backed set (array -> ISet). Anything else -> default.
    (FSet, Map(_)) | (FOMap, Map(_)) => v
    (FSet, List(items)) => set_value(items)
    _ => self.default
  }
}

///|
fn FieldSpec::protocol(self : FieldSpec, id : String) -> @tutuca.ProtocolInfo? {
  for p in self.protocols {
    if p.id == id {
      return Some(p)
    }
  }
  None
}

///|
fn FieldSpec::report_protocol_target(
  self : FieldSpec,
  value : @tutuca.Value,
  detail : String,
) -> Unit {
  @tutuca.protocol_mismatch({
    code: ProtocolTargetMismatch,
    protocol_id: self.protocol_ids.join(" & "),
    member_name: "",
    operation: "install component slot",
    detail,
    component: value.schema().map(s => s.name).unwrap_or(""),
    path: @tutuca.Path::new(),
    state: value,
    resolution: RejectedComponentValue,
  })
}

// `FieldInfo::new` / `SchemaInfo::new` / `SchemaInfo::field` moved to
// `@tutuca` (core/schema.mbt) along with the types they build, so that code
// holding only a `Value` can read a component's declared description. They are
// re-exported from spec.mbt and callers are unchanged.
