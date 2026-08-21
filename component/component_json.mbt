// A registration scope as a `ComponentSource`, and the short name for the
// round trip.
//
// The codec itself is in `@tutuca` (core/component_json.mbt), because once
// resolution is a trait it needs nothing but `Obj::obj_schema` and `TyInfo`.
// What is here is the one implementation everything in this repo actually
// uses: a lexical `ComponentStack`, which is the same namespace a view resolves
// a child component through — so a document names a component exactly the way
// a template does, and an alias works in both.
//
// The MODULE is ignored. A stack is one namespace; a page that hosts several —
// bundles loaded at runtime — says so with a source of its own that decides
// which stack a `$module` means before falling through to this one.

///|
pub impl @tutuca.ComponentSource for ComponentStack with fn describe(
  self,
  _module_,
  name,
) {
  self.lookup_component(name).map(c => c.schema)
}

///|
/// Build through `Component::make`, which is what applies the rule this whole
/// codec defers to: a field the document supplied and coerced is used, and a
/// field it did not is the component's own default — including a child slot,
/// which `make` constructs through this same scope.
pub impl @tutuca.ComponentSource for ComponentStack with fn build(
  self,
  _module_,
  name,
  args,
  // A stack keeps no side table, so WHERE an instance sits says nothing to it.
  at~ : String,
) {
  ignore(at)
  self.lookup_component(name).map(c => c.make(args))
}

///|
/// A tagged document back into an instance, resolved through THIS component's
/// registration scope.
///
/// None for a component that was never registered — `scope` is filled by
/// `ComponentStack::register_components`, so a `Component` still in hand from
/// `component()` has nowhere to look a name up.
pub fn Component::from_json(self : Component, j : Json) -> @tutuca.Value? {
  guard self.scope is Some(s) else { return None }
  @tutuca.Value::from_component_json(j, s)
}

///|
/// This instance as a tagged document. The inverse of `from_json`.
///
/// A method on `Component` for symmetry only — it holds nothing the projection
/// needs, since an instance describes itself. `Value::to_component_json` is the
/// same call without one in hand.
pub fn Component::to_json(_self : Component, v : @tutuca.Value) -> Json {
  v.to_component_json()
}
