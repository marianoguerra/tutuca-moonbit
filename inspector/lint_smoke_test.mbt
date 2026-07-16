// Lint every inspector component with the full component checker (mirrors
// examples/lint_all_test.mbt): the components all mount and pass interaction
// tests, so an error-level finding here is either a real authoring bug in the
// port or a linter bug — both worth failing on.

///|
test "no inspector component has error-level lint findings" {
  let module_ = @inspector.inspector_module()
  let scope = module_.build_scope()
  ignore(scope)
  let errors : Array[String] = []
  for comp in module_.components {
    for f in @cli.check_component(comp) {
      if f.level is Error {
        errors.push(f.line())
      }
    }
  }
  if !errors.is_empty() {
    fail(errors.join("\n"))
  }
}
