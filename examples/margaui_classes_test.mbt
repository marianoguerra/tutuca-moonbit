// The margaui pipeline's MB half, end-to-end: mount a real example (compiled
// views, macros expanded) and collect the class set exactly like
// demo/examples/main.mbt does before handing it to margaui's compiler.

///|
fn collected_classes(h : @harness.Harness) -> Set[String] {
  let classes : Set[String] = Set([])
  for _, comp in h.app.scope.comps.by_id {
    for _, view in comp.views {
      match view.anode {
        Some(node) => node.collect_classes(classes)
        None => ()
      }
    }
  }
  classes
}

///|
test "counter example exposes its margaui classes to the collector" {
  let h = @harness.mount(counter_module(), "Counter")
  let classes = collected_classes(h)
  for
    c in [
      "join", "join-vertical", "btn", "btn-error", "btn-success", "stats", "stat",
      "text-center", "stat-title", "stat-value", "stat-desc",
    ] {
    assert_true(classes.contains(c), msg="missing class: \{c}")
  }
}

///|
test "macro-expanded and @if.class classes are collected (todo_macros, conditionals)" {
  let h = @harness.mount_example(todo_macros_module(), "Empty List")
  let classes = collected_classes(h)
  // btn-rm / btn-action macros expand to margaui buttons
  for c in ["btn", "btn-soft", "btn-error", "btn-circle", "btn-success"] {
    assert_true(classes.contains(c), msg="missing class: \{c}")
  }
  let h2 = @harness.mount(tabbed_ui_module(), "TabbedUI")
  let classes2 = collected_classes(h2)
  // @if.class branches: 'tab tab-active' / 'tab'
  assert_true(classes2.contains("tab"))
  assert_true(classes2.contains("tab-active"))
}
