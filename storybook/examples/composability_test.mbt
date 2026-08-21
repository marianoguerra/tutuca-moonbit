///|
/// This example had no test, which is how a dead slot survived: `dnd` is declared
/// as the bare `component` marker (`DnDExample` has adjacent capitals, which
/// kebab-case cannot round-trip), so its name comes from `slots~`.
///
/// Asserting on the CHILD's own markup, not on the slot being non-null: a slot
/// holding an instance whose view never renders would still be non-null. The
/// panes are `@show`-gated, so only the active one is in the tree — which is what
/// scopes these selectors, since the harness matches ONE compound selector and
/// has no descendant combinator.
test "composability: the dnd slot, named through slots~, renders its child" {
  let h = @harness.mount(composability_module(), "Composability")
  // the default pane is `todo`, so DnDExample's markup is not in the tree yet
  assert_eq(h.find_all("[data-dragtype]").length(), 0)
  h.click("#tab-dnd")
  // ...and now it is: draggable rows are DnDExample's and nothing else's
  assert_true(h.find_all("[data-dragtype]").length() > 0)
}

///|
/// A slot the SCHEMA names takes a different path through `component()`, so cover
/// one too — otherwise a regression in the shared path reads as the `slots~` one.
test "composability: a schema-named slot renders its child" {
  let h = @harness.mount(composability_module(), "Composability")
  // `todo` is declared `resource items`, so its component name is in the block,
  // and the todo pane is the one that shows by default. Its list starts empty, so
  // the child's own "Add Task" button is what proves the slot was filled.
  assert_eq(h.text(".add"), "Add Task")
}
