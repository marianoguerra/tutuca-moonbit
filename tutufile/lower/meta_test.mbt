// What a component says about itself, which the old notation has nowhere to
// put — so it travels beside the text rather than through it.

///|
test "a component may say what it is and what to find it by" {
  let src =
    #|spec:
    #|  Box:
    #|    ~category: "layout"
    #|    ~keywords: ["layout", "box", "flex"]
    #|    field cells :: List.of(Any)
    #|
    #|  Grid:
    #|    ~category: "Form fields"
    #|    field rows :: Int
    #|
  let out = lower_text(src)
  assert_eq(out.reports.length(), 0)
  // both are SEARCH TEXT, matched against what a person types, so the
  // spelling and the spaces survive exactly
  @debug.assert_eq(out.meta.get("Box").unwrap(), {
    category: "layout",
    keywords: ["layout", "box", "flex"],
  })
  @debug.assert_eq(out.meta.get("Grid").unwrap(), {
    category: "Form fields",
    keywords: [],
  })
  // and the printed blocks are unchanged: the metadata left another way
  assert_true(out.text.contains("state Box {"))
  assert_false(out.text.contains("layout"))
}

///|
test "a component that says nothing is silent rather than empty" {
  let src = "spec:\n  Box:\n    field cells :: List.of(Any)\n"
  let out = lower_text(src)
  @debug.assert_eq(out.meta.get("Box").unwrap(), { category: "", keywords: [], })
}

///|
test "the comma spelling is refused with the spelling that works" {
  let src =
    #|spec:
    #|  Box:
    #|    ~keywords: "layout"
    #|    field cells :: List.of(Any)
    #|
  let out = lower_text(src)
  assert_eq(out.reports.length(), 1)
  assert_eq(out.reports[0].message, "`~keywords` takes a list")
  @debug.assert_eq(
    out.reports[0].help,
    Some(
      "write `~keywords: [\"layout\", \"box\"]` — a comma only separates inside brackets",
    ),
  )
}

///|
test "an option nobody declares is refused by name" {
  let src =
    #|spec:
    #|  Box:
    #|    ~hidden: true
    #|    field cells :: List.of(Any)
    #|
  let out = lower_text(src)
  assert_eq(out.reports.length(), 1)
  assert_eq(
    out.reports[0].message,
    "`~hidden` is not something a component declares about itself",
  )
}
