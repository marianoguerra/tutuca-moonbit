///|
test "styles-example: the same component renders in three views at once" {
  let h = @harness.mount_example(styles_module(), "Default")
  // one <x render> per view: main, one, two — the same value, three templates
  debug_inspect(
    h.texts("p").filter(t => t.has_prefix("View:")),
    content=(
      #|["View: main", "View: one", "View: two"]
    ),
  )
}

///|
test "styles-example: each rendered view is stamped with its own data-vid" {
  let h = @harness.mount_example(styles_module(), "Default")
  // the first <section> is the root component's own view; then one per child view
  let vids = h.find_all("section").map(n => n.get_attribute("data-vid"))
  debug_inspect(
    vids,
    content=(
      #|[Some("main"), Some("main"), Some("one"), Some("two")]
    ),
  )
}

///|
test "styles-example: style is per-view, commonStyle per-component, globalStyle unscoped" {
  let h = @harness.mount_example(styles_module(), "Default")
  let css = h.styles()
  // Styles are wrapped in a NESTED scope selector, not a descendant one:
  //   [data-cid="N"]{ … }                  <- commonStyle: every view
  //   [data-cid="N"][data-vid="main"]{ … } <- style: that view only
  // (the component id is a global counter, so assert the shape, not the number)
  inspect(css.contains("[data-vid=\"main\"]{"), content="true")
  inspect(css.contains("[data-vid=\"two\"]{"), content="true")
  // view "two" overrides .mine — red in main/one, orange + underlined in two
  inspect(css.contains("text-decoration: underline"), content="true")
  // commonStyle reaches every view of the component
  inspect(css.contains(".common { color: yellow; }"), content="true")
  // BARE declarations (no selector) land in the wrapper => they style the ROOT
  inspect(css.contains("border-radius: 0.5rem"), content="true")
  // globalStyle is emitted verbatim, with no scoping wrapper at all
  inspect(
    css.contains(".styles-example-global-class { color: green; }"),
    content="true",
  )
}
