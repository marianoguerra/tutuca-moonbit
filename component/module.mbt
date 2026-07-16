// ModuleDef: the programmatic module-shape convention (see spec.mbt).

///|
pub fn ModuleDef::new(
  name~ : String,
  components~ : Array[Component],
  macros? : Map[String, @anode.Macro] = {},
  requests? : Map[String, RequestFn] = {},
  examples? : Array[ExampleDef] = [],
) -> ModuleDef {
  { name, components, macros, requests, examples }
}

///|
/// Registration half of build_scope, for callers that compile later (e.g.
/// App::new compiles as part of its own boot).
pub fn ModuleDef::register_into(
  self : ModuleDef,
  scope : ComponentStack,
) -> Unit {
  scope.register_macros(self.macros)
  scope.register_request_handlers(self.requests)
  scope.register_components(self.components)
}

///|
pub fn ModuleDef::build_scope(self : ModuleDef) -> ComponentStack raise {
  let scope = ComponentStack::new()
  self.register_into(scope)
  scope.compile_all()
  scope
}
