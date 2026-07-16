// Lint every ported example module with the full component checker: the
// examples double as the linter's false-positive corpus (they all mount and
// pass interaction tests, so an error-level finding here is either a real
// authoring bug in the port or a linter bug — both worth failing on).

///|
test "no example module has error-level lint findings" {
  let errors : Array[String] = []
  for e in all_examples() {
    // the lint-errors module is the linter's INTENTIONAL-error fixture
    // (asserted separately in lint_errors_test.mbt)
    if e.name == "lint-errors" {
      continue
    }
    let scope = e.module_.build_scope() catch {
      _ => {
        errors.push("\{e.name}: build_scope failed")
        continue
      }
    }
    ignore(scope)
    for comp in e.module_.components {
      for f in @cli.check_component(comp) {
        if f.level is Error {
          errors.push("\{e.name}: \{f.line()}")
        }
      }
    }
  }
  if !errors.is_empty() {
    fail(errors.join("\n"))
  }
}
